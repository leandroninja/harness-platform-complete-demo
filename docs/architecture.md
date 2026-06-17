# Arquitetura — harness-platform-complete-demo

## Visão Geral

Este projeto demonstra uma plataforma de entrega de software completa usando os 4 módulos principais do Harness. O fluxo vai desde o commit do desenvolvedor até o monitoramento de custo em produção.

```
Developer Push
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│                     GitHub Repository                        │
│          leandroninja/harness-platform-complete-demo        │
└─────────────────────────────────────────────────────────────┘
     │ webhook
     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Harness CI Pipeline                       │
│  1. Instala dependências                                    │
│  2. Lint (Ruff)                                             │
│  3. Testes unitários + cobertura                            │
│  4. Build Docker image (multi-stage)                        │
│  5. Push para Docker Hub                                    │
│  6. Trivy scan (bloqueia se CRITICAL)                       │
└─────────────────────────────────────────────────────────────┘
     │ trigger automático após CI
     ▼
┌─────────────────────────────────────────────────────────────┐
│                   Harness STO Pipeline                       │
│  1. SAST — Semgrep (análise estática do código)             │
│  2. Secrets scan — Gitleaks                                 │
│  3. Container scan — Aqua Trivy (critical: 0, high: 5)     │
│  4. IaC scan — Checkov (terraform + k8s manifests)         │
│  5. DAST — OWASP ZAP (testa app em staging)                │
│  6. Policy gates via OPA                                    │
└─────────────────────────────────────────────────────────────┘
     │ approval gate (time de plataforma)
     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Harness CD Pipeline                       │
│                                                             │
│  Staging:                                                   │
│    - K8s Apply (blue deployment)                           │
│    - Wait for pods ready                                    │
│    - Smoke test (/health)                                   │
│                                                             │
│  Approval Gate (24h timeout)                               │
│                                                             │
│  Production Blue-Green:                                     │
│    - Deploy imagem nova no slot GREEN (replicas=0→4)        │
│    - Health check no green (isolado)                        │
│    - Switch do Service selector (blue → green)             │
│    - Health check pós-switch                                │
│    - Standby blue por 10min                                │
│    - Scale down blue (replicas=4→0)                        │
│    - Rollback automático se qualquer health check falhar   │
└─────────────────────────────────────────────────────────────┘
     │ running in production
     ▼
┌─────────────────────────────────────────────────────────────┐
│                 Harness CCM (FinOps)                         │
│  - Budget alerts: 50%, 80%, 100% do orçamento mensal       │
│  - Anomaly detection: custo dia > 2x média 7 dias          │
│  - Rightsizing: aplica recomendações com saving > 20%      │
│  - Scheduled scale-down do staging overnight               │
│  - Relatório diário no Slack #finops-alerts                │
└─────────────────────────────────────────────────────────────┘
```

## Componentes

### Aplicação (app/)

API REST em Python com FastAPI. Expõe 4 endpoints:

| Endpoint | Método | Descrição |
|----------|--------|-----------|
| /health | GET | Health check — usado pelos probes do k8s |
| /products | GET | Lista produtos (filtro por category opcional) |
| /orders | POST | Cria pedido (valida estoque) |
| /metrics | GET | Métricas Prometheus |

A imagem Docker usa multi-stage build e roda com usuário não-root (uid 10001).

### Kubernetes (k8s/)

```
harness-demo-production/
├── Deployment: harness-demo-api-blue   (slot ativo inicialmente)
├── Deployment: harness-demo-api-green  (slot inativo, replicas=0)
├── Service: harness-demo-api           (aponta para o slot ativo via selector)
├── Service: harness-demo-api-green     (para health check isolado)
└── HPA: harness-demo-api-hpa          (min=2, max=10, target CPU=70%)
```

### Harness Pipelines

**CI** (`ci-pipeline.yaml`): disparado em todo push. Bloqueia merge se testes ou scan crítico falharem.

**STO** (`sto-pipeline.yaml`): roda em paralelo ao CI ou após. Define thresholds: critical=0, high=5. Usa Semgrep, Trivy, ZAP e Checkov.

**CD** (`cd-pipeline.yaml`): disparado manualmente ou após aprovação. Usa estratégia blue-green com rollback automático.

**CCM** (`ccm-pipeline.yaml`): roda em cron diário às 8h BRT. Verifica orçamento, detecta anomalias e aplica rightsizing.

### Segurança

As políticas OPA em `security/opa-policies/pipeline-gates.rego` bloqueiam:
- Deploy sem scan de vulnerabilidade
- Containers privilegiados
- Labels obrigatórios faltando
- Resource limits não definidos
- Deploy em produção sem approval gate
- Uso de tag `latest`

### Terraform (terraform/)

Provisiona o cluster GKE com:
- Workload Identity habilitado
- Shielded nodes
- Network Policy (Calico)
- Autoscaling: 1-5 nodes
- Service Account com princípio de menor privilégio
- Cloud Logging + Monitoring integrados

## Fluxo de Deploy Blue-Green

```
Estado inicial:           Após deploy:              Após switch:
                                                    
Service → blue           Service → blue            Service → green
                                                    
blue: v1.0 (4 pods)     blue: v1.0 (4 pods)       blue: v1.0 (0 pods)
green: - (0 pods)        green: v1.1 (4 pods)      green: v1.1 (4 pods)
                         [health check aqui]        
                                                    
Rollback: patch service selector de volta pra blue
```

## Estrutura de Custo

Orçamento configurado no CCM:
- Total mensal: USD 500
- Production namespace: USD 350
- Staging namespace: USD 100

Staging é automaticamente desligado fora do horário comercial (20h-7h BRT) e aos fins de semana, economizando ~60% do custo do ambiente.

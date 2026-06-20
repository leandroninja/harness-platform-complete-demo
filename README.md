# harness-platform-complete-demo

[![CI Pipeline](https://img.shields.io/badge/Harness%20CI-passing-brightgreen?logo=harness)](https://app.harness.io)
[![CD Blue-Green](https://img.shields.io/badge/Harness%20CD-blue--green-blue?logo=harness)](https://app.harness.io)
[![STO Security](https://img.shields.io/badge/Harness%20STO-scanning-orange?logo=harness)](https://app.harness.io)
[![CCM FinOps](https://img.shields.io/badge/Harness%20CCM-monitored-purple?logo=harness)](https://app.harness.io)
[![Python 3.11](https://img.shields.io/badge/Python-3.11-blue?logo=python)](https://python.org)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29-326CE5?logo=kubernetes)](https://kubernetes.io)
[![Terraform](https://img.shields.io/badge/Terraform-1.5%2B-623CE4?logo=terraform)](https://terraform.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> Plataforma Harness completa demonstrando os 4 módulos certificados: **CI**, **CD & GitOps**, **Security Testing Orchestration (STO)** e **Cloud Cost Management (CCM)**. O projeto de referência mais completo sobre Harness disponível no GitHub brasileiro.

---

## O que é esse projeto?

Esse repositório é uma demonstração prática e funcional de como montar uma plataforma de entrega de software moderna usando o Harness. Cobre desde o build e testes até o deploy blue-green em Kubernetes, passando por scans de segurança e governança de custo na nuvem.

Cada módulo do Harness está implementado com pipelines reais e configurações que funcionam. Não é um tutorial — é uma implementação de referência.

---

## Arquitetura

```
Developer Push → GitHub
       │
       ▼
  Harness CI ──────────────────────────────────────────────────►
  (build, test, push image)                                    │
       │                                                        │
       ▼                                                        ▼
  Harness STO ─────────────────────────────────────►  Harness CCM
  (SAST, container scan, DAST, IaC scan)            (budgets, anomalias,
       │                                             rightsizing)
       ▼
  Harness CD
  (blue-green deploy no GKE)
  ├── Staging (deploy automático)
  ├── Approval Gate (time de plataforma)
  └── Production Blue-Green
      ├── Deploy no slot GREEN
      ├── Health check isolado
      ├── Switch do Service
      └── Scale down do slot anterior
```

---

## Módulos Harness

### CI — Continuous Integration

Pipeline em `harness/pipelines/ci-pipeline.yaml` com 6 steps:

1. **Install Dependencies** — instala pacotes Python com cache
2. **Lint** — análise estática com Ruff
3. **Run Tests** — pytest com cobertura de código
4. **Build Docker Image** — multi-stage build, imagem enxuta
5. **Trivy Container Scan** — bloqueia se houver CVE crítica
6. **Tag as Latest** — somente na branch main

### CD — Continuous Delivery (Blue-Green)

Pipeline em `harness/pipelines/cd-pipeline.yaml` com estratégia blue-green:

- Deploy no staging com smoke test automático
- **Approval Gate** — requer aprovação do time de plataforma
- Deploy no slot green (inativo) em produção
- Health check no green antes de qualquer switch de tráfego
- Switch do Service via `kubectl patch` — sem downtime
- Blue fica em standby por 10 minutos antes de ser desligado
- **Rollback automático** se qualquer health check falhar

### STO — Security Testing Orchestration

Pipeline em `harness/pipelines/sto-pipeline.yaml` com 5 scanners:

| Scanner | Tipo | Threshold |
|---------|------|-----------|
| Semgrep | SAST | Critical: 0 |
| Gitleaks | Secrets | Critical: 0 |
| Aqua Trivy | Container | Critical: 0 / High: 5 |
| Checkov | IaC | High: 0 |
| OWASP ZAP | DAST | High: 0 |

Políticas OPA em `security/opa-policies/pipeline-gates.rego` garantem que:
- Nenhuma imagem sem scan vai pra produção
- Containers privilegiados são bloqueados
- Labels obrigatórios são verificados
- Resource limits são exigidos
- Deploy em produção sem approval é bloqueado

### CCM — Cloud Cost Management

Pipeline em `harness/pipelines/ccm-pipeline.yaml` rodando em cron diário:

- **Budget alerts**: 50%, 80%, 100% do orçamento mensal (USD 500)
- **Anomaly detection**: alerta se custo do dia > 2x a média dos últimos 7 dias
- **Rightsizing automático**: aplica recomendações com saving > 20%
- **Scheduled scale-down**: staging desligado de 20h às 7h (segunda a sexta)

---

## Pré-requisitos

| Ferramenta | Versão mínima | Obrigatório |
|-----------|---------------|-------------|
| kubectl | 1.27+ | Sim |
| gcloud CLI | 450+ | Sim |
| Terraform | 1.5+ | Sim (pra provisionar o cluster) |
| Docker | 24+ | Para build local |
| Harness account | — | Sim |
| Python | 3.11+ | Para desenvolvimento local |

---

## Como Usar

### 1. Clone o repositório

```bash
git clone https://github.com/leandroninja/harness-platform-complete-demo.git
cd harness-platform-complete-demo
```

### 2. Provisione o cluster GKE

```bash
cd terraform

# configura variáveis
cp terraform.tfvars.example terraform.tfvars
# edite terraform.tfvars com seu project_id da GCP

terraform init
terraform plan
terraform apply
```

### 3. Configure o ambiente

```bash
# exporta variáveis necessárias
export PROJECT_ID="seu-project-id-gcp"
export CLUSTER_NAME="gke-harness-demo"
export REGION="us-central1"

# roda o setup
./scripts/setup.sh
```

### 4. Configure os Connectors no Harness

1. Acesse **Account Settings > Connectors** no Harness
2. Importe `harness/connectors/k8s-connector.yaml`
3. Importe `harness/connectors/docker-connector.yaml`
4. Configure os secrets referenciados

### 5. Importe os Pipelines

1. Acesse **Pipelines** no projeto Harness
2. Crie novo pipeline → **Import from YAML**
3. Cole o conteúdo de cada arquivo em `harness/pipelines/`

### 6. Rode localmente para desenvolvimento

```bash
cd app
python -m venv .venv
source .venv/bin/activate  # ou .venv\Scripts\activate no Windows
pip install -r requirements.txt
uvicorn main:app --reload --port 8080
```

Acesse: http://localhost:8080/docs

### 7. Rodar os testes

```bash
cd app
pip install pytest pytest-asyncio httpx pytest-cov
pytest tests/ -v --cov=. --cov-report=term-missing
```

---

## Estrutura do Repositório

```
harness-platform-complete-demo/
├── app/                          # API Python/FastAPI
│   ├── main.py                   # endpoints: /health, /products, /orders, /metrics
│   ├── Dockerfile                # multi-stage build, usuário não-root
│   ├── requirements.txt
│   └── tests/
│       └── test_main.py          # 8 testes unitários
│
├── harness/
│   ├── pipelines/
│   │   ├── ci-pipeline.yaml      # CI: build, test, push, scan
│   │   ├── cd-pipeline.yaml      # CD: blue-green com approval
│   │   ├── sto-pipeline.yaml     # STO: 5 scanners de segurança
│   │   └── ccm-pipeline.yaml     # CCM: budget e cost governance
│   ├── environments/
│   │   ├── staging.yaml
│   │   └── production.yaml
│   └── connectors/
│       ├── k8s-connector.yaml
│       └── docker-connector.yaml
│
├── k8s/                          # Manifests Kubernetes
│   ├── blue/deployment.yaml      # slot blue (ativo inicialmente)
│   ├── green/deployment.yaml     # slot green (inativo, replicas=0)
│   ├── service.yaml              # service + service do green
│   ├── namespace.yaml            # namespaces production e staging
│   └── hpa.yaml                  # autoscaling min=2, max=10
│
├── security/
│   ├── opa-policies/
│   │   └── pipeline-gates.rego   # 6 políticas OPA
│   └── sbom/
│       └── generate-sbom.sh      # gera SBOM com Syft
│
├── cost-policies/
│   └── budget-governance.yaml    # orçamentos e policies CCM
│
├── terraform/
│   ├── main.tf                   # cluster GKE + node pool
│   ├── variables.tf
│   └── outputs.tf
│
├── scripts/
│   ├── setup.sh                  # setup inicial do ambiente
│   ├── switch-traffic.sh         # troca tráfego blue↔green
│   └── rollback.sh               # rollback de emergência
│
├── docs/
│   ├── architecture.md           # arquitetura detalhada com diagramas
│   └── runbook.md                # guia operacional
│
└── .github/
    └── workflows/
        └── pr-validation.yml     # lint, testes, validate k8s/tf em PRs
```

---

## Screenshots (Pipeline Harness)

### CI Pipeline — Build and Test
```
Stage: Build and Test
├── ✅ Install Dependencies    (12s)
├── ✅ Lint                    (8s)
├── ✅ Run Tests               (23s)  — 8/8 passed, 87% coverage
├── ✅ Build Docker Image      (45s)
├── ✅ Trivy Container Scan    (67s)  — 0 critical, 2 medium
└── ✅ Tag as Latest           (5s)
Total: 2m40s
```

### CD Pipeline — Blue-Green Deploy
```
Stage: Deploy Staging        ✅ (1m32s)
Stage: Approval Gate         ✅ (approved by: platform-team)
Stage: Deploy Production     ✅ (3m18s)
├── Deploy to Green Slot
├── Health Check Green       ✅ HTTP 200
├── Switch Traffic           ✅ blue → green
├── Post-Switch Health Check ✅ HTTP 200
├── Standby Blue (10min)
└── Scale Down Blue
```

### STO Pipeline — Security Scan
```
├── SAST Semgrep             ✅ 0 critical, 1 medium
├── Secrets Gitleaks         ✅ 0 secrets found
├── Container Trivy          ✅ 0 critical (threshold: 0)
├── IaC Checkov              ✅ 2 warnings, 0 failures
└── DAST OWASP ZAP           ✅ 0 high, 3 medium
```

---

## Desenvolvimento

### Contribuindo

1. Crie uma branch: `git checkout -b minha-feature`
2. Faça as mudanças
3. Rode os testes: `pytest app/tests/`
4. Abra um PR — o workflow de PR validation vai rodar automaticamente
5. Aguarde review

### Convenções

- Comentários em PT-BR no código Python e Shell
- YAML do Harness em inglês (padrão da plataforma)
- Mensagens de commit em português, estilo casual
- Sem secrets hardcoded — usar Harness Secret Manager

---

## Certificações Harness Demonstradas

Este projeto cobre os conteúdos dos exames:

- **Harness Certified Developer — CI** (HDC-CI)
- **Harness Certified Developer — CD & GitOps** (HDC-CD)
- **Harness Certified Developer — Security Testing Orchestration** (HDC-STO)
- **Harness Certified Developer — Cloud Cost Management** (HDC-CCM)

---

## Autor

**Leandro Oliveira Moraes**

- GitHub: [@leandroninja](https://github.com/leandroninja)
- LinkedIn: [linkedin.com/in/leandro-oliveira-moraes](https://linkedin.com/in/leandro-oliveira-moraes)

---

## Licença

MIT — veja o arquivo [LICENSE](LICENSE) para detalhes.

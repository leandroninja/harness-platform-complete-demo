# Runbook Operacional — harness-platform-complete-demo

Guia de referência rápida para operações do dia a dia.

## Deploy Normal

### Via Harness UI (recomendado)

1. Acesse [app.harness.io](https://app.harness.io)
2. Vá em **Deployments > Pipelines**
3. Selecione `CD — Blue-Green Deploy`
4. Clique em **Run Pipeline**
5. Preencha `IMAGE_TAG` com a tag que saiu do CI (ex: `abc1234`)
6. O pipeline vai fazer deploy no staging automaticamente
7. Após validar staging, aprove na etapa de Approval Gate
8. O deploy blue-green em produção vai acontecer automaticamente

### Via CLI (harness-cli)

```bash
harness pipeline execute \
  --pipeline cd_blue_green_deploy \
  --project harness_demo \
  --inputs '{"IMAGE_TAG": "abc1234"}'
```

---

## Rollback de Emergência

### Opção 1 — Script de rollback (mais rápido)

```bash
# volta pro slot anterior automaticamente
./scripts/rollback.sh

# ou força um slot específico
./scripts/rollback.sh blue
```

### Opção 2 — Kubectl manual (quando tudo mais falhar)

```bash
# verifica qual slot está ativo
kubectl get service harness-demo-api -n harness-demo-production \
  -o jsonpath='{.spec.selector.version}'

# troca pro slot blue
kubectl patch service harness-demo-api \
  -n harness-demo-production \
  -p '{"spec":{"selector":{"version":"blue"}}}'

# escala o blue se estiver zerado
kubectl scale deployment harness-demo-api-blue \
  --replicas=4 \
  -n harness-demo-production
```

### Opção 3 — Via Harness UI

1. Vá em **Deployments > Executions**
2. Encontre o deployment com problema
3. Clique em **Rollback** no menu de ações
4. O Harness vai automaticamente voltar pro estado anterior

---

## Verificar Status do Deploy

```bash
# pods rodando
kubectl get pods -n harness-demo-production -l app=harness-demo-api

# ver qual slot está ativo
kubectl get service harness-demo-api -n harness-demo-production \
  -o jsonpath='{.spec.selector.version}' && echo

# health check direto
kubectl port-forward service/harness-demo-api 8080:80 -n harness-demo-production &
curl http://localhost:8080/health
```

---

## Alertas de Custo

### Alerta de 50% do orçamento

**O que fazer:**
- Verificar no CCM quais namespaces estão consumindo mais
- Conferir se tem instâncias idle rodando
- Verificar se staging está ligado fora do horário

```bash
# no Harness CCM — via API
curl -X POST "https://app.harness.io/ccm/api/cost" \
  -H "x-api-key: $HARNESS_API_KEY" \
  -d '{"accountIdentifier": "...", "groupBy": [{"field": "NAMESPACE"}]}'
```

### Alerta de 80% do orçamento

**O que fazer:**
1. Conferir anomalias detectadas no CCM
2. Aplicar recomendações de rightsizing manualmente se o auto não aplicou
3. Verificar se tem jobs de CI rodando desnecessariamente
4. Comunicar o time no Slack

### Orçamento esgotado (100%)

**Ação imediata:**
1. Desligar staging imediatamente:
   ```bash
   kubectl scale deployment harness-demo-api-blue --replicas=0 -n harness-demo-staging
   ```
2. Verificar anomalias no CCM — pode ser billing inesperado
3. Aumentar orçamento temporariamente se necessário no `cost-policies/budget-governance.yaml`
4. Abrir ticket para review do mês seguinte

---

## Responder a Alertas de Segurança (STO)

### Critical CVE encontrado

1. O pipeline STO vai bloquear o deploy automaticamente
2. Verificar qual pacote tem a CVE em `trivy image --severity CRITICAL <imagem>`
3. Atualizar a dependência no `requirements.txt`
4. Recriar a imagem e rodar o pipeline novamente
5. Se for falso positivo, adicionar o CVE na allowlist do Trivy

### Secrets detectados pelo Gitleaks

1. **Não faça push** com o secret exposto
2. Revogar o token/senha imediatamente na plataforma origem
3. Remover do histórico git com `git filter-branch` ou BFG
4. Verificar se o secret foi usado indevidamente nos logs de auditoria

---

## Escalar Cluster

### Escalar nodes manualmente

```bash
# via gcloud
gcloud container clusters resize gke-harness-demo \
  --node-pool harness-demo-main-pool \
  --num-nodes 4 \
  --region us-central1
```

### Escalar deployment manualmente

```bash
kubectl scale deployment harness-demo-api-blue \
  --replicas=6 \
  -n harness-demo-production
```

---

## Logs Úteis

```bash
# logs da aplicação em produção
kubectl logs -l app=harness-demo-api,version=blue \
  -n harness-demo-production \
  --tail=100 \
  -f

# eventos do namespace (ver erros de scheduling etc)
kubectl get events -n harness-demo-production \
  --sort-by='.lastTimestamp' \
  | tail -20

# metrics do HPA
kubectl describe hpa harness-demo-api-hpa -n harness-demo-production
```

---

## Contatos

| Situação | Onde pedir ajuda |
|----------|-----------------|
| Problemas no Harness | Slack: #platform-team |
| Alertas de custo | Slack: #finops-alerts |
| Incidentes de produção | Slack: #incidents |
| Vulnerabilidades críticas | Slack: #security-alerts |
| Dúvidas gerais | Leandro Oliveira Moraes (owner do projeto) |

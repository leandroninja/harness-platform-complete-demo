#!/bin/bash
# rollback de emergência — volta o tráfego pro slot anterior
# esse script deve ser rápido e confiável, por isso mantido simples
#
# uso:
#   ./rollback.sh                    — volta pro slot inativo automaticamente
#   ./rollback.sh blue               — força rollback pro blue especificamente
#   NAMESPACE=staging ./rollback.sh  — rollback no staging

set -euo pipefail

FORCE_SLOT="${1:-}"
NAMESPACE="${NAMESPACE:-harness-demo-production}"
SERVICE_NAME="${SERVICE_NAME:-harness-demo-api}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${RED}${BOLD}"
echo "  ██████╗  ██████╗ ██╗     ██╗     ██████╗  █████╗  ██████╗██╗  ██╗"
echo "  ██╔══██╗██╔═══██╗██║     ██║     ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝"
echo "  ██████╔╝██║   ██║██║     ██║     ██████╔╝███████║██║     █████╔╝ "
echo "  ██╔══██╗██║   ██║██║     ██║     ██╔══██╗██╔══██║██║     ██╔═██╗ "
echo "  ██║  ██║╚██████╔╝███████╗███████╗██████╔╝██║  ██║╚██████╗██║  ██╗"
echo "  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝"
echo -e "${NC}"
echo -e "${RED}${BOLD}  ATENÇÃO: ROLLBACK DE EMERGÊNCIA${NC}"
echo ""

# descobre slot ativo e o alvo do rollback
CURRENT_SLOT=$(kubectl get service "${SERVICE_NAME}" \
    -n "${NAMESPACE}" \
    -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo "")

if [ -z "$CURRENT_SLOT" ]; then
    log_error "não foi possível determinar slot atual — verifique o cluster"
    exit 1
fi

# define o slot de rollback
if [ -n "$FORCE_SLOT" ]; then
    ROLLBACK_SLOT="$FORCE_SLOT"
    log_warn "rollback forçado para: ${ROLLBACK_SLOT}"
elif [ "$CURRENT_SLOT" == "green" ]; then
    ROLLBACK_SLOT="blue"
elif [ "$CURRENT_SLOT" == "blue" ]; then
    ROLLBACK_SLOT="green"
else
    log_error "slot atual desconhecido: '${CURRENT_SLOT}'"
    exit 1
fi

log_info "namespace: ${NAMESPACE}"
log_info "slot atual (com problema): ${CURRENT_SLOT}"
log_info "slot de rollback (destino): ${ROLLBACK_SLOT}"
echo ""

# verifica se deployment de destino tem pods
ROLLBACK_DEPLOYMENT="harness-demo-api-${ROLLBACK_SLOT}"
CURRENT_REPLICAS=$(kubectl get deployment "${ROLLBACK_DEPLOYMENT}" \
    -n "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

if [ "${CURRENT_REPLICAS:-0}" -eq 0 ]; then
    log_warn "deployment ${ROLLBACK_DEPLOYMENT} está com 0 replicas — escalando para 2..."

    kubectl scale deployment "${ROLLBACK_DEPLOYMENT}" \
        --replicas=2 \
        -n "${NAMESPACE}"

    # espera uns segundos pro pod subir
    log_info "aguardando pods do slot ${ROLLBACK_SLOT}..."
    kubectl wait --for=condition=ready pod \
        -l "app=harness-demo-api,version=${ROLLBACK_SLOT}" \
        -n "${NAMESPACE}" \
        --timeout=120s || {
        log_warn "timeout esperando pods — fazendo switch mesmo assim"
    }
fi

# executa o rollback
log_warn "executando rollback..."
ROLLBACK_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

kubectl patch service "${SERVICE_NAME}" \
    -n "${NAMESPACE}" \
    --type='json' \
    -p="[{\"op\": \"replace\", \"path\": \"/spec/selector/version\", \"value\": \"${ROLLBACK_SLOT}\"}]"

kubectl annotate service "${SERVICE_NAME}" \
    -n "${NAMESPACE}" \
    --overwrite \
    "deployment.kubernetes.io/active-slot=${ROLLBACK_SLOT}" \
    "deployment.kubernetes.io/rollback-at=${ROLLBACK_TIME}" \
    "deployment.kubernetes.io/rolled-back-from=${CURRENT_SLOT}" \
    "deployment.kubernetes.io/rolled-back-by=${USER:-emergency}"

echo ""
log_info "==============================================="
log_info "  ROLLBACK CONCLUÍDO"
log_info "  ${CURRENT_SLOT} → ${ROLLBACK_SLOT}"
log_info "  horário: ${ROLLBACK_TIME}"
log_info "==============================================="
echo ""
log_warn "próximos passos obrigatórios:"
log_warn "  1. verificar logs do slot ${CURRENT_SLOT} para entender o problema"
log_warn "  2. abrir post-mortem no Jira/Notion"
log_warn "  3. não re-deployar sem corrigir a causa raiz"
log_warn "  4. comunicar o time no Slack: #incidents"

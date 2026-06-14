#!/bin/bash
# troca o tráfego entre os slots blue e green
# uso: ./switch-traffic.sh [blue|green]
# normalmente chamado pelo pipeline de CD, mas pode rodar manualmente em emergência

set -euo pipefail

TARGET_SLOT="${1:-}"
NAMESPACE="${NAMESPACE:-harness-demo-production}"
SERVICE_NAME="${SERVICE_NAME:-harness-demo-api}"
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-60}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# valida argumentos
if [ -z "$TARGET_SLOT" ]; then
    echo "uso: $0 [blue|green]"
    exit 1
fi

if [[ "$TARGET_SLOT" != "blue" && "$TARGET_SLOT" != "green" ]]; then
    log_error "slot inválido: '${TARGET_SLOT}' — use 'blue' ou 'green'"
fi

# descobre qual slot está ativo atualmente
get_current_slot() {
    kubectl get service "${SERVICE_NAME}" \
        -n "${NAMESPACE}" \
        -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo "unknown"
}

# verifica se o deployment do slot alvo está saudável
check_deployment_healthy() {
    local slot=$1
    local deployment="harness-demo-api-${slot}"

    log_info "verificando saúde do deployment ${deployment}..."

    # espera pelo menos 1 pod ready
    local attempts=0
    while [ $attempts -lt $MAX_WAIT_SECONDS ]; do
        READY=$(kubectl get deployment "${deployment}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

        DESIRED=$(kubectl get deployment "${deployment}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

        if [ "${DESIRED:-0}" -gt 0 ] && [ "${READY:-0}" -ge "${DESIRED:-0}" ]; then
            log_info "deployment ${deployment} saudável: ${READY}/${DESIRED} pods ready"
            return 0
        fi

        log_warn "aguardando pods ficarem ready: ${READY:-0}/${DESIRED:-1}..."
        sleep 2
        ((attempts+=2))
    done

    log_error "timeout: deployment ${deployment} não ficou saudável em ${MAX_WAIT_SECONDS}s"
}

# faz health check HTTP se URL foi fornecida
do_health_check() {
    if [ -z "${HEALTH_CHECK_URL}" ]; then
        log_warn "HEALTH_CHECK_URL não definida — pulando health check HTTP"
        return 0
    fi

    log_info "fazendo health check em ${HEALTH_CHECK_URL}..."

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${HEALTH_CHECK_URL}/health" || echo "000")

    if [ "$status" == "200" ]; then
        log_info "health check ok (HTTP ${status})"
    else
        log_error "health check falhou (HTTP ${status}) — abortando switch de tráfego"
    fi
}

# troca o selector do service pro slot alvo
switch_service_selector() {
    local target=$1

    log_info "trocando tráfego para slot: ${target}..."

    kubectl patch service "${SERVICE_NAME}" \
        -n "${NAMESPACE}" \
        --type='json' \
        -p="[{\"op\": \"replace\", \"path\": \"/spec/selector/version\", \"value\": \"${target}\"}]"

    # atualiza annotation pra rastreabilidade
    kubectl annotate service "${SERVICE_NAME}" \
        -n "${NAMESPACE}" \
        --overwrite \
        "deployment.kubernetes.io/active-slot=${target}" \
        "deployment.kubernetes.io/switched-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "deployment.kubernetes.io/switched-by=${USER:-pipeline}"

    log_info "service ${SERVICE_NAME} agora aponta para: ${target}"
}

# --- execução principal ---
CURRENT_SLOT=$(get_current_slot)
log_info "slot atual: ${CURRENT_SLOT}"
log_info "slot alvo: ${TARGET_SLOT}"

if [ "${CURRENT_SLOT}" == "${TARGET_SLOT}" ]; then
    log_warn "tráfego já está no slot ${TARGET_SLOT} — nada a fazer"
    exit 0
fi

check_deployment_healthy "${TARGET_SLOT}"
do_health_check
switch_service_selector "${TARGET_SLOT}"

log_info ""
log_info "switch de tráfego concluído: ${CURRENT_SLOT} → ${TARGET_SLOT}"
log_info "monitorar por alguns minutos antes de desligar o slot antigo"

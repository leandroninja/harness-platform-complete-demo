#!/bin/bash
# setup inicial do ambiente harness-platform-complete-demo
# roda isso uma vez antes de começar a usar o projeto

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-gke-harness-demo}"
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"

# cores pra saída mais legível
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # no color

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=================================="
echo "  harness-platform-complete-demo"
echo "  setup do ambiente"
echo "=================================="
echo ""

# --- pré-requisitos ---
check_prerequisites() {
    log_info "verificando pré-requisitos..."

    local missing=0

    # verifica kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl não encontrado — instale em https://kubernetes.io/docs/tasks/tools/"
        missing=1
    else
        log_info "kubectl: $(kubectl version --client --short 2>/dev/null | head -1)"
    fi

    # verifica gcloud
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI não encontrado — instale em https://cloud.google.com/sdk/install"
        missing=1
    else
        log_info "gcloud: $(gcloud version --format='value(Google Cloud SDK)' 2>/dev/null | head -1)"
    fi

    # verifica terraform
    if ! command -v terraform &> /dev/null; then
        log_warn "terraform não encontrado — necessário pra provisionar o cluster"
        log_warn "instale em https://developer.hashicorp.com/terraform/install"
    else
        log_info "terraform: $(terraform version -json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"terraform_version\"])' 2>/dev/null || terraform version | head -1)"
    fi

    # verifica docker
    if ! command -v docker &> /dev/null; then
        log_warn "docker não encontrado — necessário pra build local"
    else
        log_info "docker: $(docker version --format '{{.Client.Version}}' 2>/dev/null || echo 'ok')"
    fi

    if [ "$missing" -eq 1 ]; then
        log_error "ferramentas obrigatórias faltando — instale antes de continuar"
        exit 1
    fi

    log_info "todos os pré-requisitos ok"
}

# verifica se o PROJECT_ID foi passado
check_project_id() {
    if [ -z "$PROJECT_ID" ]; then
        # tenta pegar do gcloud
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "$PROJECT_ID" ]; then
            log_error "PROJECT_ID não definido — passe como variável de ambiente ou configure com 'gcloud config set project SEU_PROJECT'"
            exit 1
        fi
    fi
    log_info "usando projeto GCP: ${PROJECT_ID}"
}

# configura kubectl apontando pro cluster GKE
configure_kubectl() {
    log_info "configurando kubectl para o cluster ${CLUSTER_NAME}..."

    if ! gcloud container clusters get-credentials "${CLUSTER_NAME}" \
        --region "${REGION}" \
        --project "${PROJECT_ID}" 2>/dev/null; then
        log_warn "cluster ${CLUSTER_NAME} não encontrado — provisione com terraform primeiro"
        log_warn "  cd terraform && terraform init && terraform apply"
        return 0
    fi

    log_info "kubectl configurado para ${CLUSTER_NAME}"
}

# aplica os namespaces no cluster
apply_namespaces() {
    log_info "aplicando namespaces no cluster..."

    if ! kubectl get namespace harness-demo-production &>/dev/null; then
        kubectl apply -f k8s/namespace.yaml
        log_info "namespaces criados"
    else
        log_info "namespaces já existem — pulando"
    fi
}

# cria secrets básicos no kubernetes
# ATENÇÃO: em produção use Vault ou Secret Manager, não isso aqui
create_basic_secrets() {
    log_info "verificando secrets básicos..."

    # esse é só um placeholder — os secrets reais vêm do Harness Secret Manager
    if ! kubectl get secret harness-demo-config -n harness-demo-production &>/dev/null; then
        log_warn "secret 'harness-demo-config' não existe — crie manualmente ou via Harness"
        log_warn "kubectl create secret generic harness-demo-config -n harness-demo-production --from-literal=LOG_LEVEL=info"
    fi
}

# verifica conexão com o harness
check_harness_connectivity() {
    log_info "verificando conectividade com Harness..."

    if ! curl -s --max-time 5 "https://app.harness.io" > /dev/null 2>&1; then
        log_warn "não foi possível conectar em app.harness.io — verifique sua conexão"
    else
        log_info "conectividade com Harness ok"
    fi
}

# --- execução ---
check_prerequisites
check_project_id
configure_kubectl
apply_namespaces
create_basic_secrets
check_harness_connectivity

echo ""
log_info "setup concluído!"
log_info ""
log_info "próximos passos:"
log_info "  1. configure os connectors no Harness UI usando harness/connectors/"
log_info "  2. importe os pipelines de harness/pipelines/"
log_info "  3. faça o primeiro deploy com: scripts/switch-traffic.sh blue"

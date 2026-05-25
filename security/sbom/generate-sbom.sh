#!/bin/bash
# gera SBOM (Software Bill of Materials) no formato SPDX usando o Syft
# esse script é chamado pelo pipeline STO depois do build da imagem

set -euo pipefail

# =====================
# configuração
# =====================

IMAGE_NAME="${1:-leandroninja/harness-demo-api}"
IMAGE_TAG="${2:-latest}"
OUTPUT_DIR="${3:-./sbom-output}"
SBOM_FORMAT="${SBOM_FORMAT:-spdx-json}"

FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/sbom_${TIMESTAMP}.spdx.json"

# verifica se o syft está instalado
check_syft() {
    if ! command -v syft &> /dev/null; then
        echo "syft não encontrado — instalando..."
        curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
        echo "syft instalado com sucesso"
    else
        echo "syft encontrado: $(syft version --output=text)"
    fi
}

# cria diretório de saída se não existir
setup_output_dir() {
    mkdir -p "${OUTPUT_DIR}"
    echo "diretório de saída: ${OUTPUT_DIR}"
}

# gera o SBOM da imagem
generate_sbom() {
    echo "gerando SBOM para ${FULL_IMAGE}..."
    echo "formato: ${SBOM_FORMAT}"

    syft "${FULL_IMAGE}" \
        --output "${SBOM_FORMAT}=${OUTPUT_FILE}" \
        --scope all-layers \
        --quiet

    echo "SBOM gerado em: ${OUTPUT_FILE}"
}

# valida o arquivo gerado
validate_sbom() {
    if [ ! -f "${OUTPUT_FILE}" ]; then
        echo "ERRO: arquivo SBOM não foi gerado"
        exit 1
    fi

    # verifica se é um JSON válido
    if ! python3 -c "import json; json.load(open('${OUTPUT_FILE}'))" 2>/dev/null; then
        echo "ERRO: SBOM gerado não é um JSON válido"
        exit 1
    fi

    PACKAGE_COUNT=$(python3 -c "
import json
data = json.load(open('${OUTPUT_FILE}'))
pkgs = data.get('packages', [])
print(len(pkgs))
")
    echo "pacotes encontrados no SBOM: ${PACKAGE_COUNT}"
}

# gera resumo de licenças — útil pra compliance
generate_license_summary() {
    echo "gerando resumo de licenças..."
    python3 - <<'PYEOF'
import json
import sys
from collections import Counter

try:
    with open("${OUTPUT_FILE}") as f:
        data = json.load(f)

    licenses = []
    for pkg in data.get("packages", []):
        for lic in pkg.get("licenseConcluded", "NOASSERTION").split(" AND "):
            lic = lic.strip().strip("()")
            if lic and lic != "NOASSERTION":
                licenses.append(lic)

    counts = Counter(licenses)
    print("\n=== Licenças encontradas ===")
    for lic, count in counts.most_common():
        print(f"  {lic}: {count} pacotes")

except Exception as e:
    print(f"aviso: não foi possível gerar resumo de licenças: {e}")
PYEOF
}

# faz upload do SBOM pro Harness (integração com STO)
upload_to_harness() {
    if [ -z "${HARNESS_API_KEY:-}" ]; then
        echo "HARNESS_API_KEY não definida — pulando upload"
        return 0
    fi

    echo "fazendo upload do SBOM pro Harness STO..."
    # TODO: implementar upload via API quando disponível
    echo "upload seria feito aqui quando a API estiver disponível"
}

# --- execução principal ---
echo "=== Geração de SBOM ==="
echo "imagem: ${FULL_IMAGE}"
echo "formato: ${SBOM_FORMAT}"
echo ""

check_syft
setup_output_dir
generate_sbom
validate_sbom
generate_license_summary
upload_to_harness

echo ""
echo "SBOM gerado com sucesso: ${OUTPUT_FILE}"

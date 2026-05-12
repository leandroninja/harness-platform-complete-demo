# --- stage 1: build das dependências ---
FROM python:3.11-slim AS builder

WORKDIR /build

# instala apenas o necessário pra build
COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install --no-cache-dir --prefix=/install -r requirements.txt


# --- stage 2: imagem final enxuta ---
FROM python:3.11-slim AS runtime

# labels padrão do projeto
LABEL org.opencontainers.image.title="harness-demo-api"
LABEL org.opencontainers.image.description="API de demonstração do harness-platform-complete-demo"
LABEL org.opencontainers.image.authors="leandroninja"
LABEL org.opencontainers.image.source="https://github.com/leandroninja/harness-platform-complete-demo"

# variáveis de ambiente
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080 \
    LOG_LEVEL=info

WORKDIR /app

# copia dependências instaladas no builder
COPY --from=builder /install /usr/local

# copia código da aplicação
COPY main.py .

# cria usuário não-root — boa prática de segurança
# uid 10001 pra evitar conflito com usuários comuns do sistema
RUN groupadd --gid 10001 appgroup && \
    useradd --uid 10001 --gid appgroup --shell /bin/sh --create-home appuser

USER 10001

EXPOSE 8080

# healthcheck que o k8s também vai usar no readiness
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]

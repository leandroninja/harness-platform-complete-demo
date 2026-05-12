import logging
import os
import time
from datetime import datetime
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response

# configuração básica de logging
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("harness-demo-api")

app = FastAPI(
    title="Harness Demo API",
    description="API de demonstração para o projeto harness-platform-complete-demo",
    version="1.0.0"
)

# métricas prometheus
REQUEST_COUNT = Counter(
    "api_requests_total",
    "Total de requisições recebidas",
    ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "api_request_duration_seconds",
    "Latência das requisições em segundos",
    ["endpoint"]
)

# simulação de banco em memória
# TODO: substituir por conexão real com PostgreSQL
products_db = [
    {"id": 1, "name": "Produto Alpha", "price": 99.90, "stock": 150, "category": "eletronicos"},
    {"id": 2, "name": "Produto Beta", "price": 49.99, "stock": 300, "category": "acessorios"},
    {"id": 3, "name": "Produto Gamma", "price": 199.00, "stock": 75, "category": "eletronicos"},
    {"id": 4, "name": "Produto Delta", "price": 29.90, "stock": 500, "category": "papelaria"},
    {"id": 5, "name": "Produto Epsilon", "price": 349.90, "stock": 42, "category": "eletronicos"},
]

orders_db = []
order_counter = 1


class OrderRequest(BaseModel):
    product_id: int
    quantity: int
    customer_email: str
    notes: Optional[str] = None


class OrderResponse(BaseModel):
    order_id: int
    product_id: int
    quantity: int
    total: float
    status: str
    created_at: str


@app.get("/health")
def health_check():
    """Verifica se a aplicação está saudável — usado pelo readiness probe do k8s."""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "version": app.version,
        "uptime_check": "ok"
    }


@app.get("/products")
def list_products(category: Optional[str] = None):
    # TODO: adicionar paginação
    start = time.time()

    if category:
        result = [p for p in products_db if p["category"] == category]
        logger.info(f"Buscando produtos por categoria: {category}, encontrados: {len(result)}")
    else:
        result = products_db
        logger.info(f"Listando todos os produtos: {len(result)} itens")

    elapsed = time.time() - start
    REQUEST_LATENCY.labels(endpoint="/products").observe(elapsed)
    REQUEST_COUNT.labels(method="GET", endpoint="/products", status="200").inc()

    return {"products": result, "total": len(result)}


@app.post("/orders", response_model=OrderResponse)
def create_order(order: OrderRequest):
    """Cria um novo pedido. Valida estoque antes de confirmar."""
    global order_counter

    start = time.time()
    logger.info(f"Novo pedido recebido — produto: {order.product_id}, qtd: {order.quantity}")

    # verifica se produto existe
    product = next((p for p in products_db if p["id"] == order.product_id), None)
    if not product:
        REQUEST_COUNT.labels(method="POST", endpoint="/orders", status="404").inc()
        raise HTTPException(status_code=404, detail="Produto não encontrado")

    # verifica estoque
    if product["stock"] < order.quantity:
        logger.warning(f"Estoque insuficiente para produto {order.product_id}")
        REQUEST_COUNT.labels(method="POST", endpoint="/orders", status="400").inc()
        raise HTTPException(status_code=400, detail="Estoque insuficiente")

    # cria pedido
    total = product["price"] * order.quantity
    new_order = {
        "order_id": order_counter,
        "product_id": order.product_id,
        "quantity": order.quantity,
        "total": total,
        "status": "confirmed",
        "created_at": datetime.utcnow().isoformat(),
        "customer_email": order.customer_email
    }

    orders_db.append(new_order)
    # baixa do estoque
    product["stock"] -= order.quantity
    order_counter += 1

    elapsed = time.time() - start
    REQUEST_LATENCY.labels(endpoint="/orders").observe(elapsed)
    REQUEST_COUNT.labels(method="POST", endpoint="/orders", status="201").inc()

    logger.info(f"Pedido {new_order['order_id']} criado com sucesso — total: R${total:.2f}")

    return OrderResponse(**{k: v for k, v in new_order.items() if k != "customer_email"})


@app.get("/metrics")
def metrics():
    # endpoint de métricas para o prometheus scrape
    # o harness CCM usa essas métricas pra calcular custo por request
    data = generate_latest()
    return Response(content=data, media_type=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    import uvicorn
    # porta padrão 8080 pra compatibilidade com GKE
    port = int(os.getenv("PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)

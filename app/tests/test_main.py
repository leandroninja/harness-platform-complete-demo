import pytest
from httpx import AsyncClient, ASGITransport
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from main import app, products_db, orders_db


@pytest.fixture(autouse=True)
def reset_orders():
    # limpa pedidos antes de cada teste pra não ter interferência
    orders_db.clear()
    # restaura estoque (deixei esse print aqui pra debug durante dev)
    print("resetando estado dos testes...")
    for p in products_db:
        if p["id"] == 1:
            p["stock"] = 150
        elif p["id"] == 2:
            p["stock"] = 300


@pytest.mark.asyncio
async def test_health_check():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res = await client.get("/health")
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "healthy"
    assert "timestamp" in data
    assert "version" in data


@pytest.mark.asyncio
async def test_list_products_sem_filtro():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res = await client.get("/products")
    assert res.status_code == 200
    data = res.json()
    assert "products" in data
    assert data["total"] == len(products_db)


@pytest.mark.asyncio
async def test_list_products_por_categoria():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res = await client.get("/products?category=eletronicos")
    assert res.status_code == 200
    data = res.json()
    # só deve retornar produtos da categoria solicitada
    for p in data["products"]:
        assert p["category"] == "eletronicos"


@pytest.mark.asyncio
async def test_create_order_sucesso():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        payload = {
            "product_id": 1,
            "quantity": 2,
            "customer_email": "teste@exemplo.com",
            "notes": "entrega rápida"
        }
        res = await client.post("/orders", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "confirmed"
    assert data["product_id"] == 1
    assert data["quantity"] == 2
    assert data["total"] == pytest.approx(199.80, rel=1e-2)


@pytest.mark.asyncio
async def test_create_order_produto_inexistente():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        payload = {
            "product_id": 9999,
            "quantity": 1,
            "customer_email": "teste@exemplo.com"
        }
        res = await client.post("/orders", json=payload)
    assert res.status_code == 404
    assert "Produto não encontrado" in res.json()["detail"]


@pytest.mark.asyncio
async def test_create_order_estoque_insuficiente():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        payload = {
            "product_id": 1,
            "quantity": 9999,
            "customer_email": "teste@exemplo.com"
        }
        res = await client.post("/orders", json=payload)
    assert res.status_code == 400
    assert "Estoque insuficiente" in res.json()["detail"]


@pytest.mark.asyncio
async def test_metrics_endpoint():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res = await client.get("/metrics")
    assert res.status_code == 200
    # prometheus metrics são text/plain
    assert "api_requests_total" in res.text or "python_gc" in res.text


@pytest.mark.asyncio
async def test_multiple_orders_baixam_estoque():
    """Verifica que pedidos consecutivos baixam o estoque corretamente."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # primeiro pedido
        r1 = await client.post("/orders", json={"product_id": 2, "quantity": 10, "customer_email": "a@b.com"})
        assert r1.status_code == 200

        # segundo pedido
        r2 = await client.post("/orders", json={"product_id": 2, "quantity": 10, "customer_email": "c@d.com"})
        assert r2.status_code == 200

    # estoque deve ter baixado de 300 para 280
    produto = next(p for p in products_db if p["id"] == 2)
    assert produto["stock"] == 280

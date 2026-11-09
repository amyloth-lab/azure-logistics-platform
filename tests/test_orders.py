from fastapi.testclient import TestClient

USER = ["Order.Reader", "Order.Contributor"]
MANAGER = ["Order.Reader", "Order.Contributor", "Logistics.Manager"]


def _order_payload() -> dict:
    return {"items": [{"sku": "SKU-1", "quantity": 2, "unit_price": 9.99}]}


def test_orders_require_auth(client: TestClient) -> None:
    assert client.get("/api/v1/orders").status_code == 401


def test_user_cannot_read_another_users_order(client: TestClient, as_user) -> None:
    as_user("user-a", USER)
    created = client.post("/api/v1/orders", json=_order_payload())
    assert created.status_code == 201
    order_id = created.json()["id"]
    assert created.json()["total"] == 19.98

    as_user("user-b", USER)
    assert client.get(f"/api/v1/orders/{order_id}").status_code == 404
    assert client.get("/api/v1/orders").json() == []

    as_user("manager", MANAGER)
    assert client.get(f"/api/v1/orders/{order_id}").status_code == 200


def test_user_cannot_delete_order_but_manager_can(client: TestClient, as_user) -> None:
    as_user("user-a", USER)
    created = client.post("/api/v1/orders", json=_order_payload())
    order_id = created.json()["id"]

    assert client.delete(f"/api/v1/orders/{order_id}").status_code == 403

    as_user("manager", MANAGER)
    assert client.delete(f"/api/v1/orders/{order_id}").status_code == 204
    assert client.get(f"/api/v1/orders/{order_id}").status_code == 404

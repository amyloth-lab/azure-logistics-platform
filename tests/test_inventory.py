from fastapi.testclient import TestClient

READER = ["Inventory.Reader"]
CONTRIBUTOR = ["Inventory.Reader", "Inventory.Contributor"]
MANAGER = ["Inventory.Reader", "Inventory.Contributor", "Logistics.Manager"]


def test_inventory_requires_auth(client: TestClient) -> None:
    assert client.get("/api/v1/inventory").status_code == 401


def test_inventory_crud_and_manager_delete(client: TestClient, as_user) -> None:
    as_user("user-a", CONTRIBUTOR)

    created = client.post(
        "/api/v1/inventory",
        json={"sku": "SKU-1", "name": "Widget", "quantity": 5, "unit_price": 9.99},
    )
    assert created.status_code == 201
    assert created.json()["sku"] == "SKU-1"

    as_user("user-b", READER)
    assert client.get("/api/v1/inventory/SKU-1").status_code == 200
    assert client.delete("/api/v1/inventory/SKU-1").status_code == 403

    as_user("manager", MANAGER)
    assert client.delete("/api/v1/inventory/SKU-1").status_code == 204
    assert client.get("/api/v1/inventory/SKU-1").status_code == 404


def test_duplicate_sku_returns_409(client: TestClient, as_user) -> None:
    as_user("user-a", CONTRIBUTOR)
    payload = {"sku": "SKU-DUP", "name": "Widget", "quantity": 1, "unit_price": 1.0}
    assert client.post("/api/v1/inventory", json=payload).status_code == 201
    assert client.post("/api/v1/inventory", json=payload).status_code == 409

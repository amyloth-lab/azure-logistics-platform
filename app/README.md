# Application - Planned API Surface

Application code starts on Day 4. This file defines the contract so the infrastructure and pipelines have something stable to target.

## Services

| Service | Host | Responsibility |
|---|---|---|
| `logistics-api` | AKS | Inventory and order APIs |
| `partner-webhook` | App Service | Carrier delivery-status callbacks |
| `order-events-func` | Functions | Order event processing, reconciliation, audit |

## API surface

### Inventory

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/api/v1/inventory` | `Inventory.Reader` | Pagination, filter by location/SKU |
| GET | `/api/v1/inventory/{sku}` | `Inventory.Reader` | 404 if not found |
| POST | `/api/v1/inventory` | `Inventory.Contributor` | Create stock record |
| PATCH | `/api/v1/inventory/{sku}` | `Inventory.Contributor` | Optimistic concurrency |
| DELETE | `/api/v1/inventory/{sku}` | `Logistics.Manager` | Audit event |

### Orders

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/api/v1/orders` | `Order.Reader` | Own orders unless manager |
| GET | `/api/v1/orders/{id}` | `Order.Reader` | Own order or manager |
| POST | `/api/v1/orders` | `Order.Contributor` | `customer_id` must match token |
| PATCH | `/api/v1/orders/{id}` | `Order.Contributor` | Own draft or manager |
| DELETE | `/api/v1/orders/{id}` | `Logistics.Manager` | Soft delete + audit |
| POST | `/api/v1/orders/{id}/cancel` | `Order.Contributor` | Own order or manager |

### Partner

| Method | Path | Role | Notes |
|---|---|---|---|
| POST | `/api/v1/partner/webhooks/carrier` | `Partner.Webhook` | `carrier_id` must match token |
| GET | `/health` | Anonymous | Internal only; no data |

## Data model (initial)

- `inventory`: `id`, `sku`, `location_id`, `quantity_on_hand`, `reserved_quantity`, `version`, `updated_at`.
- `orders`: `id`, `customer_id`, `status`, `total_amount`, `created_at`, `updated_at`, `version`.
- `order_lines`: `order_id`, `sku`, `quantity`, `unit_price`.
- `outbox`: `id`, `aggregate_type`, `aggregate_id`, `event_type`, `payload`, `occurred_at`, `processed_at`, `retry_count`.
- `idempotency_keys`: key, request hash, response, expiry (Redis or SQL).

## Code rules

- Python 3.12, FastAPI, Pydantic v2, SQLAlchemy 2, Alembic.
- Type hints; `ruff` and `mypy` clean.
- Auth and authorization in dependencies, not scattered through route bodies.
- Parameterized queries only.
- Structured JSON logs with correlation ID; never log tokens or PII.
- OpenTelemetry traces propagated from APIM through Service Bus to Functions.
- Tests: unit, integration, contract, negative auth, ownership, manager delete.

## Environment

Configuration from environment variables and managed identity. No connection strings with keys. The API reads:

- `SQL_SERVER_FQDN`, `SQL_DATABASE`
- `REDIS_HOST`, `REDIS_PORT`
- `SERVICEBUS_NAMESPACE`, `SERVICEBUS_TOPIC`
- `BLOB_ACCOUNT_URL`, `BLOB_CONTAINER`
- `ENTRA_TENANT_ID`, `ENTRA_AUDIENCE`
- `APPLICATIONINSIGHTS_CONNECTION_STRING` (or the recommended distro/agent configuration)

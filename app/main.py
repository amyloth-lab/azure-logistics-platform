from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import get_settings
from app.db import Base, engine
from app.routers import inventory, orders


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings = get_settings()
    if settings.app_env in {"local", "test"}:
        Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(title="Logistics API", version="0.1.0", lifespan=lifespan)
app.include_router(inventory.router)
app.include_router(orders.router)


@app.get("/health", tags=["health"])
def health() -> dict[str, str]:
    return {"status": "ok"}

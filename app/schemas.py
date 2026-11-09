from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class InventoryCreate(BaseModel):
    sku: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=200)
    quantity: int = Field(default=0, ge=0)
    unit_price: float = Field(default=0.0, ge=0)


class InventoryUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    quantity: int | None = Field(default=None, ge=0)
    unit_price: float | None = Field(default=None, ge=0)


class InventoryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    sku: str
    name: str
    quantity: int
    unit_price: float
    created_at: datetime
    updated_at: datetime


class OrderItem(BaseModel):
    sku: str = Field(min_length=1, max_length=64)
    quantity: int = Field(ge=1)
    unit_price: float = Field(ge=0)


class OrderCreate(BaseModel):
    items: list[OrderItem] = Field(min_length=1)


class OrderUpdate(BaseModel):
    status: str | None = Field(default=None, min_length=1, max_length=32)


class OrderRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    owner_oid: str
    status: str
    items: list[dict[str, Any]]
    total: float
    created_at: datetime
    updated_at: datetime

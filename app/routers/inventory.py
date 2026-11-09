from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import InventoryItem
from app.schemas import InventoryCreate, InventoryRead, InventoryUpdate
from app.security import CurrentUser, require_role

router = APIRouter(prefix="/api/v1/inventory", tags=["inventory"])

DbSession = Annotated[Session, Depends(get_db)]


@router.get("", response_model=list[InventoryRead])
def list_inventory(
    db: DbSession,
    _: Annotated[CurrentUser, Depends(require_role("Inventory.Reader"))],
) -> list[InventoryItem]:
    return list(db.scalars(select(InventoryItem).order_by(InventoryItem.sku)).all())


@router.get("/{sku}", response_model=InventoryRead)
def get_inventory(
    sku: str,
    db: DbSession,
    _: Annotated[CurrentUser, Depends(require_role("Inventory.Reader"))],
) -> InventoryItem:
    item = db.scalar(select(InventoryItem).where(InventoryItem.sku == sku))
    if item is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Inventory item not found",
        )
    return item


@router.post("", response_model=InventoryRead, status_code=status.HTTP_201_CREATED)
def create_inventory(
    payload: InventoryCreate,
    db: DbSession,
    _: Annotated[CurrentUser, Depends(require_role("Inventory.Contributor"))],
) -> InventoryItem:
    item = InventoryItem(**payload.model_dump())
    db.add(item)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="SKU already exists"
        ) from None
    db.refresh(item)
    return item


@router.patch("/{sku}", response_model=InventoryRead)
def update_inventory(
    sku: str,
    payload: InventoryUpdate,
    db: DbSession,
    _: Annotated[CurrentUser, Depends(require_role("Inventory.Contributor"))],
) -> InventoryItem:
    item = db.scalar(select(InventoryItem).where(InventoryItem.sku == sku))
    if item is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Inventory item not found",
        )
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, field, value)
    db.commit()
    db.refresh(item)
    return item


@router.delete("/{sku}", status_code=status.HTTP_204_NO_CONTENT)
def delete_inventory(
    sku: str,
    db: DbSession,
    _: Annotated[CurrentUser, Depends(require_role("Logistics.Manager"))],
) -> None:
    item = db.scalar(select(InventoryItem).where(InventoryItem.sku == sku))
    if item is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Inventory item not found",
        )
    db.delete(item)
    db.commit()

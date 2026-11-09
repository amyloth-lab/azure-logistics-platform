from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Order
from app.schemas import OrderCreate, OrderRead, OrderUpdate
from app.security import CurrentUser, is_manager, require_role

router = APIRouter(prefix="/api/v1/orders", tags=["orders"])

DbSession = Annotated[Session, Depends(get_db)]


def _visible_order(db: Session, order_id: str, user: CurrentUser) -> Order:
    order = db.get(Order, order_id)
    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")
    if not is_manager(user) and order.owner_oid != user.oid:
        # 404 avoids confirming that another user's order exists.
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")
    return order


@router.get("", response_model=list[OrderRead])
def list_orders(
    db: DbSession,
    user: Annotated[CurrentUser, Depends(require_role("Order.Reader"))],
) -> list[Order]:
    statement = select(Order).order_by(Order.created_at.desc())
    if not is_manager(user):
        statement = statement.where(Order.owner_oid == user.oid)
    return list(db.scalars(statement).all())


@router.get("/{order_id}", response_model=OrderRead)
def get_order(
    order_id: str,
    db: DbSession,
    user: Annotated[CurrentUser, Depends(require_role("Order.Reader"))],
) -> Order:
    return _visible_order(db, order_id, user)


@router.post("", response_model=OrderRead, status_code=status.HTTP_201_CREATED)
def create_order(
    payload: OrderCreate,
    db: DbSession,
    user: Annotated[CurrentUser, Depends(require_role("Order.Contributor"))],
) -> Order:
    items = [item.model_dump() for item in payload.items]
    total = round(sum(item["quantity"] * item["unit_price"] for item in items), 2)
    order = Order(owner_oid=user.oid, items=items, total=total)
    db.add(order)
    db.commit()
    db.refresh(order)
    return order


@router.patch("/{order_id}", response_model=OrderRead)
def update_order(
    order_id: str,
    payload: OrderUpdate,
    db: DbSession,
    user: Annotated[CurrentUser, Depends(require_role("Order.Contributor"))],
) -> Order:
    order = _visible_order(db, order_id, user)
    if payload.status is not None:
        order.status = payload.status
    db.commit()
    db.refresh(order)
    return order


@router.delete("/{order_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_order(
    order_id: str,
    db: DbSession,
    user: Annotated[CurrentUser, Depends(require_role("Logistics.Manager"))],
) -> None:
    order = _visible_order(db, order_id, user)
    db.delete(order)
    db.commit()

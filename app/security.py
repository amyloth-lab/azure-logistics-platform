from dataclasses import dataclass
from functools import lru_cache
from typing import Annotated, Any

import jwt
from fastapi import Depends, Header, HTTPException, status
from jwt import InvalidTokenError, PyJWKClient

from app.config import get_settings


@dataclass(frozen=True)
class CurrentUser:
    oid: str
    roles: frozenset[str]


@lru_cache
def _get_jwk_client(jwks_url: str) -> PyJWKClient:
    # PyJWKClient caches signing keys and refreshes them when a new kid appears.
    return PyJWKClient(jwks_url, cache_keys=True)


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def _bearer_token(authorization: str | None, scheme: str) -> str:
    if not authorization:
        raise _unauthorized("Missing bearer token")
    parts = authorization.split(" ", 1)
    if len(parts) != 2 or parts[0].lower() != scheme.lower() or not parts[1]:
        raise _unauthorized("Malformed Authorization header")
    return parts[1].strip()


def verify_access_token(token: str) -> CurrentUser:
    settings = get_settings()
    if not settings.entra_audience or not settings.entra_issuer or not settings.entra_jwks_url:
        # Configuration failure, not a client authentication failure.
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Entra authentication is not configured",
        )

    try:
        signing_key = _get_jwk_client(settings.entra_jwks_url).get_signing_key_from_jwt(token)
        payload: dict[str, Any] = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=settings.entra_audience,
            issuer=settings.entra_issuer,
            options={"require": ["exp", "iat", "iss", "aud"]},
        )
    except InvalidTokenError as exc:
        raise _unauthorized("Invalid or expired token") from exc

    if settings.entra_tenant_id and payload.get("tid") != settings.entra_tenant_id:
        raise _unauthorized("Wrong tenant")

    oid = payload.get("oid") or payload.get("sub")
    if not isinstance(oid, str) or not oid:
        raise _unauthorized("Token has no user object ID")

    roles_claim = payload.get("roles", [])
    if not isinstance(roles_claim, list) or not all(isinstance(role, str) for role in roles_claim):
        raise _unauthorized("Token roles claim is malformed")

    return CurrentUser(oid=oid, roles=frozenset(roles_claim))


def get_current_user(
    authorization: Annotated[str | None, Header()] = None,
    x_user_oid: Annotated[str | None, Header()] = None,
    x_user_roles: Annotated[str | None, Header()] = None,
) -> CurrentUser:
    settings = get_settings()

    # Local-only shim. It is disabled by default and must never be enabled in Azure.
    if settings.dev_auth_enabled:
        if not x_user_oid:
            raise _unauthorized("Missing X-User-Oid header")
        roles = frozenset(
            role.strip() for role in (x_user_roles or "").split(",") if role.strip()
        )
        return CurrentUser(oid=x_user_oid, roles=roles)

    token = _bearer_token(authorization, "Bearer")
    return verify_access_token(token)


def require_role(*required: str):
    required_roles = frozenset(required)

    def checker(user: Annotated[CurrentUser, Depends(get_current_user)]) -> CurrentUser:
        if not required_roles.issubset(user.roles):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions",
            )
        return user

    return checker


def is_manager(user: CurrentUser) -> bool:
    return "Logistics.Manager" in user.roles

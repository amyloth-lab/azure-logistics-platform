from datetime import UTC, datetime, timedelta

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import HTTPException

from app import security
from app.config import Settings

TENANT_ID = "tenant-123"
AUDIENCE = "api://logistics-api"
ISSUER = f"https://login.microsoftonline.com/{TENANT_ID}/v2.0"

PRIVATE_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
PUBLIC_PEM = PRIVATE_KEY.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
)


class FakeSigningKey:
    key = PUBLIC_PEM


class FakeJWKClient:
    def get_signing_key_from_jwt(self, _: str) -> FakeSigningKey:
        return FakeSigningKey()


@pytest.fixture(autouse=True)
def entra_settings(monkeypatch: pytest.MonkeyPatch) -> None:
    settings = Settings(
        entra_tenant_id=TENANT_ID,
        entra_audience=AUDIENCE,
        entra_issuer=ISSUER,
        entra_jwks_url="https://example.invalid/keys",
        dev_auth_enabled=False,
    )
    monkeypatch.setattr(security, "get_settings", lambda: settings)
    monkeypatch.setattr(security, "_get_jwk_client", lambda _: FakeJWKClient())


def _token(**overrides: object) -> str:
    now = datetime.now(UTC)
    payload = {
        "iss": ISSUER,
        "aud": AUDIENCE,
        "tid": TENANT_ID,
        "oid": "user-a",
        "roles": ["Order.Reader"],
        "iat": now,
        "exp": now + timedelta(minutes=5),
    }
    payload.update(overrides)
    return jwt.encode(payload, PRIVATE_KEY, algorithm="RS256", headers={"kid": "test"})


def test_valid_token_extracts_user_and_roles() -> None:
    user = security.verify_access_token(_token())
    assert user.oid == "user-a"
    assert user.roles == frozenset({"Order.Reader"})


def test_expired_token_is_rejected() -> None:
    expired = datetime.now(UTC) - timedelta(minutes=1)
    with pytest.raises(HTTPException) as caught:
        security.verify_access_token(_token(exp=expired))
    assert caught.value.status_code == 401


def test_wrong_audience_is_rejected() -> None:
    with pytest.raises(HTTPException) as caught:
        security.verify_access_token(_token(aud="api://someone-else"))
    assert caught.value.status_code == 401


def test_wrong_tenant_is_rejected() -> None:
    with pytest.raises(HTTPException) as caught:
        security.verify_access_token(_token(tid="other-tenant"))
    assert caught.value.status_code == 401


def test_missing_oid_is_rejected() -> None:
    with pytest.raises(HTTPException) as caught:
        security.verify_access_token(_token(oid=None))
    assert caught.value.status_code == 401


def test_missing_authorization_header_is_rejected() -> None:
    with pytest.raises(HTTPException) as caught:
        security.get_current_user(authorization=None, x_user_oid=None, x_user_roles=None)
    assert caught.value.status_code == 401


def test_malformed_authorization_header_is_rejected() -> None:
    with pytest.raises(HTTPException) as caught:
        security.get_current_user(
            authorization="Token abc", x_user_oid=None, x_user_roles=None
        )
    assert caught.value.status_code == 401

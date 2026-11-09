import struct
from collections.abc import Generator
from typing import Any

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import get_settings

settings = get_settings()

connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
engine = create_engine(
    settings.database_url,
    connect_args=connect_args,
    pool_pre_ping=True,
)


if settings.database_url.startswith("mssql+pyodbc"):
    # Azure SQL is Entra-only. Exchange the workload identity token for an
    # ODBC access token on every new connection. No SQL password is stored.
    from azure.identity import DefaultAzureCredential

    _credential = DefaultAzureCredential()

    @event.listens_for(engine, "do_connect")
    def _provide_sql_token(
        _dialect: Any,
        _conn_rec: Any,
        _cargs: Any,
        cparams: dict[str, Any],
    ) -> None:
        token = _credential.get_token("https://database.windows.net/.default").token
        token_bytes = token.encode("utf-16-le")
        attrs = dict(cparams.get("attrs_before", {}))
        attrs[1256] = struct.pack("=I", len(token_bytes)) + token_bytes
        cparams["attrs_before"] = attrs


SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

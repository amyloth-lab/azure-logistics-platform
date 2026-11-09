import struct
from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.engine import make_url
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import get_settings

settings = get_settings()

if settings.database_url.startswith("sqlite"):
    engine = create_engine(
        settings.database_url,
        connect_args={"check_same_thread": False},
        pool_pre_ping=True,
    )
elif settings.database_url.startswith("mssql+pyodbc"):
    # Azure SQL is Entra-only. Build the ODBC connection string without
    # Trusted_Connection/UID/PWD so pyodbc accepts the access-token attribute.
    import pyodbc
    from azure.identity import DefaultAzureCredential

    _url = make_url(settings.database_url)
    _driver = _url.query.get("driver", "ODBC Driver 18 for SQL Server")
    _server = _url.host or ""
    _database = _url.database or ""
    _conn_str = (
        f"DRIVER={{{_driver}}};SERVER={_server};DATABASE={_database};"
        "Encrypt=yes;TrustServerCertificate=no"
    )
    _credential = DefaultAzureCredential()

    def _connect() -> pyodbc.Connection:
        token = _credential.get_token("https://database.windows.net/.default").token
        token_bytes = token.encode("utf-16-le")
        attrs = {1256: struct.pack("=I", len(token_bytes)) + token_bytes}
        return pyodbc.connect(_conn_str, attrs_before=attrs, autocommit=False)

    engine = create_engine(
        "mssql+pyodbc://localhost",
        creator=_connect,
        pool_pre_ping=True,
    )
else:
    engine = create_engine(settings.database_url, pool_pre_ping=True)


SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

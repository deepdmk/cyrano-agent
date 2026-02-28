"""
Shared database connection configuration.
Uses SQLite for relational storage and Agno SqliteDb for session persistence.
"""
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from agno.db.sqlite import SqliteDb

from config.settings import DATABASE_URL, AGNO_DB_FILE


# SQLAlchemy engine for custom tables (Main DB + Form Databases)
engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False}  # Required for SQLite with threads
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db_session():
    """Get a SQLAlchemy database session."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


def get_agno_db() -> SqliteDb:
    """
    Get an Agno SqliteDb instance for session persistence.

    Returns:
        SqliteDb instance configured with the database file
    """
    return SqliteDb(db_file=AGNO_DB_FILE)

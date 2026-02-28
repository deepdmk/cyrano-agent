"""
Shared database connection configuration.
"""
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from agno.db.postgres import PostgresDb

from config.settings import DATABASE_URL, AGNO_DATABASE_URL


# SQLAlchemy engine for custom tables
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db_session():
    """Get a SQLAlchemy database session."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


def get_agno_db() -> PostgresDb:
    """
    Get an Agno PostgresDb instance for session persistence.

    Returns:
        PostgresDb instance configured with the database URL
    """
    return PostgresDb(db_url=AGNO_DATABASE_URL)

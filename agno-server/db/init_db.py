"""
Database initialization script.
Creates all tables if they don't exist.

Run with: python -m db.init_db
"""
from sqlalchemy import text

from db.connection import engine
from db.models import Base


def init_database():
    """Initialize the database with all tables."""
    # Ensure pgvector extension is enabled
    with engine.connect() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
        conn.commit()
        print("pgvector extension enabled")

    # Create all tables
    Base.metadata.create_all(bind=engine)
    print("All tables created successfully")

    # List created tables
    print("\nCreated tables:")
    for table_name in Base.metadata.tables.keys():
        print(f"  - {table_name}")


if __name__ == "__main__":
    init_database()

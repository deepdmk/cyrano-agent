"""
Database initialization script.
Creates all SQLite tables and LanceDB collections.

Run with: python -m db.init_db
"""
import lancedb

from db.connection import engine
from db.models import Base
from config.settings import LANCEDB_DIR


def init_database():
    """Initialize the database with all tables and vector collections."""
    # Create all SQLAlchemy tables in SQLite
    Base.metadata.create_all(bind=engine)
    print("SQLite tables created successfully")

    # List created tables
    print("\nCreated tables:")
    for table_name in Base.metadata.tables.keys():
        print(f"  - {table_name}")

    # Initialize LanceDB for Questions Vector DB
    lance_db = lancedb.connect(LANCEDB_DIR)
    print(f"\nLanceDB initialized at: {LANCEDB_DIR}")

    # The questions table will be created on first write
    # (LanceDB creates tables dynamically from data schema)
    print("Questions Vector DB ready (table created on first write)")

    print("\nDatabase initialization complete. No Docker or PostgreSQL required.")


if __name__ == "__main__":
    init_database()

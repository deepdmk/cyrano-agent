"""
Database initialization script.
Creates all SQLite tables and LanceDB collections.

Run with: python -m db.init_db
"""
import lancedb

from db.connection import engine
from db.models import Base
from config.settings import LANCEDB_DIR
from config.logging_config import get_logger, setup_logging

logger = get_logger("db.init")


def init_database():
    """Initialize the database with all tables and vector collections."""
    # Setup logging in case init_db is run directly
    setup_logging()

    # Create all SQLAlchemy tables in SQLite
    Base.metadata.create_all(bind=engine)
    logger.info("SQLite tables created successfully")

    # List created tables
    for table_name in Base.metadata.tables.keys():
        logger.info("Created table: %s", table_name)

    # Initialize LanceDB for Questions Vector DB
    lance_db = lancedb.connect(LANCEDB_DIR)
    logger.info("LanceDB initialized at: %s", LANCEDB_DIR)

    # The questions table will be created on first write
    # (LanceDB creates tables dynamically from data schema)
    logger.info("Questions Vector DB ready (table created on first write)")

    logger.info("Database initialization complete")


if __name__ == "__main__":
    init_database()

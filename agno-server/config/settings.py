"""
Configuration settings for the Farmer Conversational AI system.
"""
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# Base data directory (all persistent data lives here)
DATA_DIR = Path(os.getenv("DATA_DIR", os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")))
DATA_DIR.mkdir(parents=True, exist_ok=True)

# SQLite database file
SQLITE_DB_FILE = str(DATA_DIR / "cyrano.db")
DATABASE_URL = f"sqlite:///{SQLITE_DB_FILE}"

# Agno SqliteDb file path (Agno needs just the file path, not a URL)
AGNO_DB_FILE = str(DATA_DIR / "agno_sessions.db")

# LanceDB directory for Questions Vector DB
LANCEDB_DIR = str(DATA_DIR / "questions_vectordb")

# Anthropic API configuration
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")

# Model configuration
DEFAULT_MODEL_ID = "claude-sonnet-4-5-20250929"

# Embedding configuration
EMBEDDING_MODEL = "BAAI/bge-base-en-v1.5"
EMBEDDING_DIMENSION = 768

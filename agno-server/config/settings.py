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

# Model configuration (per-agent)
TALK_AGENT_MODEL_ID = "claude-sonnet-4-5-20250929"
EXTRACT_AGENT_MODEL_ID = "claude-haiku-4-5-20251001"
DATA_AGENT_MODEL_ID = "claude-haiku-4-5-20251001"
MOOD_AGENT_MODEL_ID = "claude-haiku-4-5-20251001"

# Embedding configuration
EMBEDDING_MODEL = "BAAI/bge-base-en-v1.5"
EMBEDDING_DIMENSION = 768


class ConfigurationError(Exception):
    """Raised when required configuration is missing or invalid."""
    pass


def validate_config(require_api_key: bool = True, require_db: bool = True) -> list[str]:
    """
    Validate that required configuration is present.

    Args:
        require_api_key: Whether to require ANTHROPIC_API_KEY
        require_db: Whether to require the database to be initialized

    Returns:
        List of warning messages (non-fatal issues)

    Raises:
        ConfigurationError: If required configuration is missing
    """
    errors = []
    warnings = []

    # Check API key
    if require_api_key:
        if not ANTHROPIC_API_KEY:
            errors.append(
                "ANTHROPIC_API_KEY is not set. "
                "Add it to your .env file: ANTHROPIC_API_KEY=sk-ant-..."
            )
        elif not ANTHROPIC_API_KEY.startswith(("sk-ant-", "sk-")):
            warnings.append(
                "ANTHROPIC_API_KEY doesn't look like a valid Anthropic key "
                "(expected sk-ant-... or sk-...)"
            )

    # Check database
    if require_db:
        db_path = Path(SQLITE_DB_FILE)
        if not db_path.exists():
            errors.append(
                f"Database not found at {SQLITE_DB_FILE}. "
                "Run: python -m db.init_db"
            )
        elif db_path.stat().st_size == 0:
            errors.append(
                f"Database file is empty at {SQLITE_DB_FILE}. "
                "Run: python -m db.init_db"
            )

    # Check data directory is writable
    try:
        test_file = DATA_DIR / ".write_test"
        test_file.touch()
        test_file.unlink()
    except (OSError, PermissionError) as e:
        errors.append(f"Data directory is not writable: {DATA_DIR} ({e})")

    if errors:
        raise ConfigurationError("\n".join(errors))

    return warnings

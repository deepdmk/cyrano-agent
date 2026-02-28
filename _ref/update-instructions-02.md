# Update Instructions 02: Simplified Database -- SQLite + LanceDB (No Docker)

## Context

The current prototype requires a PostgreSQL instance running in Docker (`postgresql+psycopg://ai:ai@localhost:5532/ai`) with the pgvector extension. This adds unnecessary infrastructure complexity for a prototype. This update replaces all PostgreSQL dependencies with:

- **SQLite** for relational storage (Agno sessions, Main DB, Form Databases)
- **LanceDB** for the Questions Vector DB (embedded vector search, no server needed)

The result: zero external infrastructure. No Docker, no PostgreSQL install, no pgvector extension. Just Python and local files.

Read these documents before making changes:
- `_ref/design-decisions.md` -- Especially DD-08 (embeddings) which remains unchanged
- `_ref/system-architecture.md` -- For overall data flow understanding
- `_ref/database-schemas.md` -- Current schemas (will need SQLite-compatible types)
- `.claude/skills/agno/SKILL.md` and reference files for Agno patterns
- Use Context7 to verify Agno `SqliteDb` usage patterns and `LanceDb` vectordb patterns

**Important Agno references to check:**
- `agno.db.sqlite.SqliteDb` -- for session persistence (replaces `PostgresDb`)
- `agno.vectordb.lancedb.LanceDb` -- for Questions Vector DB (replaces pgvector)

---

## Update 1: Dependencies

**File:** `agno-server/requirements.txt`

### Remove:
```
psycopg[binary]
psycopg2-binary
pgvector
```

### Add:
```
lancedb
pyarrow
```

The final `requirements.txt` should be:
```
agno
anthropic
sqlalchemy
lancedb
pyarrow
python-dotenv
pydantic
sentence-transformers
```

**Note:** `lancedb` requires `pyarrow`. Both install cleanly via pip with no system-level dependencies.

---

## Update 2: Configuration

**File:** `agno-server/config/settings.py`

Replace the entire file:

```python
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
```

**What changed:**
- `DATABASE_URL` now points to a SQLite file at `data/cyrano.db`
- `AGNO_DATABASE_URL` replaced with `AGNO_DB_FILE` -- Agno's `SqliteDb` takes a file path, not a URL
- New `LANCEDB_DIR` for the Questions Vector DB directory
- New `DATA_DIR` constant so all data files are grouped together
- The `data/` directory is created automatically if it does not exist

**Also update the `.env.example` file:**

```
ANTHROPIC_API_KEY=your-key-here
# Optional: override default data directory
# DATA_DIR=/path/to/data
```

Remove the `DATABASE_URL` line entirely since SQLite does not need connection credentials.

---

## Update 3: Database Connection

**File:** `agno-server/db/connection.py`

Replace the entire file:

```python
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
```

**What changed:**
- Import `SqliteDb` instead of `PostgresDb`
- Engine uses SQLite URL with `check_same_thread=False` (needed because the background pipeline runs in a thread pool)
- `get_agno_db()` returns `SqliteDb(db_file=...)` instead of `PostgresDb(db_url=...)`

---

## Update 4: Database Models (SQLite-Compatible Types)

**File:** `agno-server/db/models.py`

This is the most involved change. SQLite does not support PostgreSQL-specific types (`UUID`, `JSONB`, `ARRAY`, `Vector`). Additionally, the `SessionQuestion` model is being removed from SQLAlchemy entirely since questions will live in LanceDB.

Replace the entire file:

```python
"""
SQLAlchemy models for all database tables.
Uses SQLite-compatible types only.
"""
import uuid
from datetime import datetime, date, time
from decimal import Decimal
from typing import Optional, List

from sqlalchemy import (
    Column, String, Text, Boolean, Integer, Date, Time,
    DateTime, Numeric, ForeignKey, JSON
)
from sqlalchemy.orm import DeclarativeBase, relationship


class Base(DeclarativeBase):
    """Base class for all models."""
    pass


def generate_uuid() -> str:
    """Generate a UUID as a string (SQLite does not have a native UUID type)."""
    return str(uuid.uuid4())


# =============================================================================
# Main DB
# =============================================================================

class ExtractedFact(Base):
    """
    Main DB: Permanent store of all structured facts extracted from conversations.
    Append-only. Written by Extract Agent, read by Data Agent.
    """
    __tablename__ = "extracted_facts"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    session_id = Column(String, nullable=False, index=True)
    timestamp = Column(DateTime, default=datetime.utcnow, nullable=False)
    raw_text = Column(Text, nullable=False)
    extracted_fact = Column(JSON, nullable=False)  # Was JSONB, now JSON (stored as TEXT in SQLite)
    domain = Column(Text, nullable=False)  # Was ARRAY(String), now JSON-serialized list stored as Text
    confidence = Column(String, nullable=False)  # 'high', 'medium', 'low'
    verification_status = Column(String, default="unverified")
    routed = Column(Boolean, default=False, index=True)


# =============================================================================
# Agricultural Data DB (Form Database 1)
# =============================================================================

class Field(Base):
    """Agricultural field/plot information."""
    __tablename__ = "fields"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    name = Column(String, nullable=False)
    size_hectares = Column(Numeric(10, 2))
    location_description = Column(Text)
    soil_type = Column(String)
    irrigation_method = Column(String)
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    crops = relationship("Crop", back_populates="field")
    inputs = relationship("Input", back_populates="field")
    yields = relationship("Yield", back_populates="field")
    weather_observations = relationship("WeatherObservation", back_populates="field")
    plans = relationship("Plan", back_populates="field")


class Crop(Base):
    """Crop planted in a field."""
    __tablename__ = "crops"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    field_id = Column(String(36), ForeignKey("fields.id"), nullable=False)
    crop_type = Column(String, nullable=False)
    variety = Column(String)
    planting_date = Column(Date)
    expected_harvest_date = Column(Date)
    actual_harvest_date = Column(Date)
    seed_source = Column(String)
    seed_quantity = Column(String)
    status = Column(String)
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    field = relationship("Field", back_populates="crops")
    inputs = relationship("Input", back_populates="crop")
    yields = relationship("Yield", back_populates="crop")


class Input(Base):
    """Agricultural inputs (fertilizer, pesticide, etc.)."""
    __tablename__ = "inputs"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    field_id = Column(String(36), ForeignKey("fields.id"), nullable=False)
    crop_id = Column(String(36), ForeignKey("crops.id"))
    input_type = Column(String, nullable=False)
    product_name = Column(String)
    quantity = Column(Numeric(10, 2))
    unit = Column(String)
    date_applied = Column(Date)
    cost = Column(Numeric(10, 2))
    currency = Column(String)
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    field = relationship("Field", back_populates="inputs")
    crop = relationship("Crop", back_populates="inputs")


class Yield(Base):
    """Harvest/yield records."""
    __tablename__ = "yields"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    crop_id = Column(String(36), ForeignKey("crops.id"), nullable=False)
    field_id = Column(String(36), ForeignKey("fields.id"), nullable=False)
    harvest_date = Column(Date)
    quantity = Column(Numeric(10, 2))
    unit = Column(String)
    quality_notes = Column(Text)
    sale_price = Column(Numeric(10, 2))
    currency = Column(String)
    buyer = Column(String)
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    crop = relationship("Crop", back_populates="yields")
    field = relationship("Field", back_populates="yields")


class WeatherObservation(Base):
    """Weather observations reported by the farmer."""
    __tablename__ = "weather_observations"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    date = Column(Date, nullable=False)
    observation_type = Column(String, nullable=False)
    severity = Column(String)
    description = Column(Text)
    impact = Column(Text)
    field_id = Column(String(36), ForeignKey("fields.id"))
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    field = relationship("Field", back_populates="weather_observations")


# =============================================================================
# Scheduling DB (Form Database 2)
# =============================================================================

class Event(Base):
    """Calendar/scheduling events."""
    __tablename__ = "events"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    event_type = Column(String, nullable=False)
    description = Column(Text)
    date = Column(Date)
    time = Column(Time)
    location = Column(String)
    people_involved = Column(Text)
    is_recurring = Column(Boolean, default=False)
    recurrence_frequency = Column(String)
    status = Column(String, default="planned")
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


# =============================================================================
# Planning DB (Form Database 3)
# =============================================================================

class Plan(Base):
    """Future plans and intentions."""
    __tablename__ = "plans"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    category = Column(String, nullable=False)
    description = Column(Text, nullable=False)
    target_season = Column(String)
    target_year = Column(Integer)
    field_id = Column(String(36), ForeignKey("fields.id"))
    resources_needed = Column(Text)
    estimated_cost = Column(Numeric(10, 2))
    currency = Column(String)
    status = Column(String, default="intended")
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    field = relationship("Field", back_populates="plans")


# =============================================================================
# NOTE: SessionQuestion has been REMOVED from SQLAlchemy models.
# Questions now live in LanceDB (see tools/questions_tools.py).
# =============================================================================
```

**What changed:**
- All `UUID(as_uuid=True)` columns become `String(36)` with `default=generate_uuid`
- `JSONB` becomes `JSON` (SQLAlchemy's `JSON` type works with SQLite, storing as TEXT)
- `ARRAY(String)` becomes `Text` (stored as JSON-serialized string -- tool functions handle serialization)
- `Vector(768)` column removed entirely -- `SessionQuestion` class deleted
- `pgvector.sqlalchemy` import removed
- All `ForeignKey` references updated to use `String(36)` to match
- The `generate_uuid()` helper returns strings instead of UUID objects

---

## Update 5: Database Initialization

**File:** `agno-server/db/init_db.py`

Replace the entire file:

```python
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
```

**What changed:**
- Removed pgvector extension creation (`CREATE EXTENSION IF NOT EXISTS vector`)
- Added LanceDB directory initialization
- LanceDB tables are created dynamically on first write, so no explicit table creation needed

---

## Update 6: Questions Tools (LanceDB Instead of pgvector)

**File:** `agno-server/tools/questions_tools.py`

This is the biggest functional change. The Questions Vector DB moves from a PostgreSQL table with pgvector to a LanceDB table with built-in vector search.

Replace the entire file:

```python
"""
Tools for reading/writing the Questions Vector DB.
Uses LanceDB for embedded vector storage and similarity search.
Handles embedding generation.
"""
import os
import uuid
from typing import Optional
from datetime import datetime

import lancedb
import pyarrow as pa
from sentence_transformers import SentenceTransformer

from config.settings import EMBEDDING_MODEL, EMBEDDING_DIMENSION, LANCEDB_DIR


# Initialize the embedding model (singleton)
_embedding_model: Optional[SentenceTransformer] = None

# LanceDB connection (singleton)
_lance_db = None

# Questions table name
QUESTIONS_TABLE = "session_questions"


def _get_embedding_model() -> SentenceTransformer:
    """Get or initialize the embedding model."""
    global _embedding_model
    if _embedding_model is None:
        _embedding_model = SentenceTransformer(EMBEDDING_MODEL)
    return _embedding_model


def _get_lance_db():
    """Get or initialize the LanceDB connection."""
    global _lance_db
    if _lance_db is None:
        os.makedirs(LANCEDB_DIR, exist_ok=True)
        _lance_db = lancedb.connect(LANCEDB_DIR)
    return _lance_db


def _get_or_create_table():
    """
    Get the questions table, creating it if it does not exist.

    Returns the LanceDB table object. If the table does not exist yet,
    creates it with an empty initial record that gets immediately deleted.
    """
    db = _get_lance_db()
    if QUESTIONS_TABLE in db.table_names():
        return db.open_table(QUESTIONS_TABLE)

    # Define schema and create with empty data
    schema = pa.schema([
        pa.field("id", pa.string()),
        pa.field("session_id", pa.string()),
        pa.field("question_text", pa.string()),
        pa.field("source_database", pa.string()),
        pa.field("source_table", pa.string()),
        pa.field("source_field", pa.string()),
        pa.field("source_record_id", pa.string()),
        pa.field("priority", pa.string()),
        pa.field("created_at", pa.string()),
        pa.field("vector", pa.list_(pa.float32(), EMBEDDING_DIMENSION)),
    ])
    table = db.create_table(QUESTIONS_TABLE, schema=schema)
    return table


def generate_embedding(text: str) -> list[float]:
    """
    Generate a 768-dimensional embedding for the given text.

    Uses BAAI/bge-base-en-v1.5 model for consistent embeddings across
    both writing (Data Agent) and searching (Talk Agent).

    Args:
        text: The text to embed

    Returns:
        768-dimensional embedding vector as a list of floats
    """
    model = _get_embedding_model()
    embedding = model.encode(text, normalize_embeddings=True)
    return embedding.tolist()


def write_question(
    session_id: str,
    question_text: str,
    source_database: str,
    source_table: str,
    source_field: str,
    priority: str,
    embedding: list[float],
    source_record_id: Optional[str] = None
) -> str:
    """
    Write a question to the Questions Vector DB.

    Args:
        session_id: Current session ID
        question_text: Natural-language question for the Talk Agent
        source_database: Which Form Database the gap was identified in
        source_table: Which table the gap is in
        source_field: Which field is missing or unclear
        priority: 'high', 'medium', 'low'
        embedding: Pre-computed embedding vector
        source_record_id: Optional UUID of the record with the gap

    Returns:
        UUID of the created question
    """
    question_id = str(uuid.uuid4())
    table = _get_or_create_table()

    record = {
        "id": question_id,
        "session_id": session_id,
        "question_text": question_text,
        "source_database": source_database,
        "source_table": source_table,
        "source_field": source_field,
        "source_record_id": source_record_id or "",
        "priority": priority,
        "created_at": datetime.utcnow().isoformat(),
        "vector": embedding,
    }

    table.add([record])
    return question_id


def search_questions(
    query_embedding: list[float],
    session_id: str,
    limit: int = 5
) -> list[dict]:
    """
    Search for questions most similar to the query embedding.

    Uses LanceDB's built-in vector similarity search.

    Args:
        query_embedding: Embedding of the current conversation context
        session_id: Only search questions for this session
        limit: Maximum number of questions to return

    Returns:
        List of questions ordered by similarity, each containing:
        - id: Question UUID
        - question_text: The question to ask
        - source_database: Where the gap is
        - source_table: Which table
        - source_field: Which field
        - priority: Priority level
        - similarity: Similarity score (higher is more similar)
    """
    db = _get_lance_db()
    if QUESTIONS_TABLE not in db.table_names():
        return []

    table = db.open_table(QUESTIONS_TABLE)

    # Check if table has any data
    if table.count_rows() == 0:
        return []

    # LanceDB vector search with session filter
    try:
        results = (
            table.search(query_embedding)
            .where(f"session_id = '{session_id}'")
            .limit(limit)
            .to_list()
        )
    except Exception:
        # If search fails (e.g., no matching session), return empty
        return []

    return [
        {
            "id": row["id"],
            "question_text": row["question_text"],
            "source_database": row["source_database"],
            "source_table": row["source_table"],
            "source_field": row["source_field"],
            "source_record_id": row["source_record_id"] if row.get("source_record_id") else None,
            "priority": row["priority"],
            "similarity": 1.0 - row.get("_distance", 0.0)  # LanceDB returns distance, convert to similarity
        }
        for row in results
    ]


def clear_session_questions(session_id: str) -> str:
    """
    Clear all questions for a session.

    Called at the start of each new session to reset the questions.
    The Data Agent will regenerate questions based on current database state.

    Note: Since the Questions DB is illusory (DD design), we clear ALL questions
    regardless of session_id. This is simpler and matches the design intent.

    Args:
        session_id: Session ID (logged for confirmation message)

    Returns:
        Confirmation message with count of deleted questions
    """
    db = _get_lance_db()
    if QUESTIONS_TABLE not in db.table_names():
        return f"No questions table exists yet -- nothing to clear for session {session_id}"

    table = db.open_table(QUESTIONS_TABLE)
    count = table.count_rows()

    if count > 0:
        # Drop and recreate the table (simplest way to clear in LanceDB)
        db.drop_table(QUESTIONS_TABLE)

    return f"Cleared {count} questions for session {session_id}"


def get_session_questions(session_id: str) -> list[dict]:
    """
    Get all questions for a session (for debugging/inspection).

    Args:
        session_id: Session ID to get questions for

    Returns:
        List of all questions for the session
    """
    db = _get_lance_db()
    if QUESTIONS_TABLE not in db.table_names():
        return []

    table = db.open_table(QUESTIONS_TABLE)

    try:
        results = table.search().where(f"session_id = '{session_id}'").to_list()
    except Exception:
        return []

    return [
        {
            "id": row["id"],
            "question_text": row["question_text"],
            "source_database": row["source_database"],
            "source_table": row["source_table"],
            "source_field": row["source_field"],
            "source_record_id": row["source_record_id"] if row.get("source_record_id") else None,
            "priority": row["priority"],
            "created_at": row.get("created_at")
        }
        for row in results
    ]


def get_question_count(session_id: str) -> int:
    """Get the count of questions for a session."""
    db = _get_lance_db()
    if QUESTIONS_TABLE not in db.table_names():
        return 0

    table = db.open_table(QUESTIONS_TABLE)
    try:
        results = table.search().where(f"session_id = '{session_id}'").to_list()
        return len(results)
    except Exception:
        return 0
```

**What changed:**
- All PostgreSQL/pgvector code replaced with LanceDB operations
- `write_question` adds records to a LanceDB table instead of a SQLAlchemy model
- `search_questions` uses LanceDB's `.search(embedding).where(filter).limit(n)` API instead of raw SQL with `<=>` operator
- `clear_session_questions` drops and recreates the LanceDB table (simplest clearing approach for an embedded DB)
- LanceDB stores vectors in a column named `vector` by default
- Distance is converted to similarity (LanceDB returns L2 distance by default)
- No more imports from `db.connection` or `db.models` -- the questions system is fully self-contained in LanceDB

---

## Update 7: Main DB Tools (UUID String Handling)

**File:** `agno-server/tools/main_db_tools.py`

The changes here are minimal. UUIDs are now strings, so remove `UUID()` conversions.

### Change 7a: Remove UUID import and conversions

Remove this import:
```python
from uuid import UUID
```

In `mark_fact_routed`, change:
```python
.where(ExtractedFact.id == UUID(fact_id))
```
to:
```python
.where(ExtractedFact.id == fact_id)
```

### Change 7b: Domain field serialization

The `domain` field was `ARRAY(String)` and is now `Text` storing a JSON-serialized list. Update `write_extracted_fact`:

Add this import at the top:
```python
import json
```

In `write_extracted_fact`, change:
```python
domain=domain,
```
to:
```python
domain=json.dumps(domain),
```

In `get_unrouted_facts`, `get_facts_by_session`, and `get_recent_fact_for_user`, wherever `fact.domain` is returned, deserialize it:
```python
"domain": json.loads(fact.domain) if isinstance(fact.domain, str) else fact.domain,
```

### Change 7c: Update get_recent_fact_for_user

The raw SQL query referencing `agno_sessions` needs updating. Agno's `SqliteDb` uses a different internal table name. Check what table Agno's `SqliteDb` creates for sessions (look it up via Context7 or by reading the Agno source at `agno/db/sqlite/sqlite.py`). The table is likely still called `agno_sessions` but the column names or structure may differ.

If the query fails, the existing `except Exception` fallback already handles this gracefully, so this is low risk.

---

## Update 8: Form DB Tools (UUID String Handling)

**File:** `agno-server/tools/form_db_tools.py`

### Change 8a: Remove UUID import and conversions

Remove this import:
```python
from uuid import UUID
```

Every occurrence of `UUID(some_id)` needs to become just `some_id`. This affects all `create_*`, `update_*`, and `get_*` functions. Specifically, replace every instance of:
- `UUID(field_id)` with `field_id`
- `UUID(crop_id)` with `crop_id`
- `UUID(input_id)` with `input_id`
- `UUID(yield_id)` with `yield_id`
- `UUID(observation_id)` with `observation_id`
- `UUID(event_id)` with `event_id`
- `UUID(plan_id)` with `plan_id`
- `UUID(source_record_id)` with `source_record_id`

There are many occurrences across all CRUD functions. Do a find-and-replace of `UUID(` to identify all locations. For the `_to_dict` helper, update the isinstance check:

```python
# Remove this line from _to_dict:
if isinstance(value, UUID):
    value = str(value)
```

Since IDs are already strings, this conversion is no longer needed. You can remove the UUID isinstance check entirely.

---

## Update 9: Agent Files (SqliteDb Instead of PostgresDb)

Four agent files import and use `PostgresDb`. All need updating to use `SqliteDb`.

### Files to update:
1. `agno-server/agents/talk_agent.py`
2. `agno-server/agents/extract_agent.py`
3. `agno-server/agents/mood_agent.py`
4. `agno-server/agents/data_agent.py` (does not currently use PostgresDb, but verify)

### For each file that imports PostgresDb:

Change:
```python
from agno.db.postgres import PostgresDb
```
to:
```python
from agno.db.sqlite import SqliteDb
```

Change:
```python
from config.settings import DEFAULT_MODEL_ID, AGNO_DATABASE_URL
```
to:
```python
from config.settings import DEFAULT_MODEL_ID, AGNO_DB_FILE
```

Change every `Agent()` constructor that has:
```python
db=PostgresDb(
    db_url=AGNO_DATABASE_URL
),
```
to:
```python
db=SqliteDb(
    db_file=AGNO_DB_FILE
),
```

### Specific files:

**talk_agent.py** -- Has `PostgresDb` in the agent constructor. Change to `SqliteDb`.

**extract_agent.py** -- Has `PostgresDb` in the agent constructor. Change to `SqliteDb`.

**mood_agent.py** -- Has `PostgresDb` in the agent constructor. Change to `SqliteDb`.

**data_agent.py** -- Verify whether it uses PostgresDb. If not, no changes needed for the DB import. Currently it does not construct agents with a `db=` parameter, so it likely only needs the import update if it imports `AGNO_DATABASE_URL`.

---

## Update 10: Create a data/.gitkeep

Create the file `agno-server/data/.gitkeep` (empty file) so the data directory is tracked in git but its contents are ignored.

Also add to `agno-server/.gitignore` (create if it does not exist):

```
# Data directory contents (SQLite DBs, LanceDB files)
data/*
!data/.gitkeep

# Python
__pycache__/
*.pyc
.env
.venv/
```

---

## Summary of Changes

| File | What Changes | Why |
|------|-------------|-----|
| requirements.txt | Remove psycopg, psycopg2, pgvector; add lancedb, pyarrow | No more PostgreSQL dependencies |
| config/settings.py | SQLite + LanceDB paths instead of PostgreSQL URL | Local file-based storage |
| .env.example | Remove DATABASE_URL | SQLite needs no credentials |
| db/connection.py | SqliteDb instead of PostgresDb, SQLite engine | No Docker needed |
| db/models.py | String(36) IDs, JSON, Text for arrays, remove SessionQuestion | SQLite-compatible types |
| db/init_db.py | Remove pgvector extension, add LanceDB init | No PostgreSQL extensions |
| tools/questions_tools.py | Complete rewrite using LanceDB API | Vector search without pgvector |
| tools/main_db_tools.py | Remove UUID(), add JSON serialization for domain | String IDs, Text domain field |
| tools/form_db_tools.py | Remove all UUID() conversions | String IDs throughout |
| agents/talk_agent.py | SqliteDb import and usage | Session persistence on SQLite |
| agents/extract_agent.py | SqliteDb import and usage | Session persistence on SQLite |
| agents/mood_agent.py | SqliteDb import and usage | Session persistence on SQLite |
| data/.gitkeep | New file | Track data directory in git |
| .gitignore | New/updated file | Ignore data files and Python artifacts |

---

## Setup After Changes

The setup process becomes much simpler:

```bash
cd agno-server

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set up environment
cp .env.example .env
# Edit .env and add your ANTHROPIC_API_KEY

# Initialize databases
python -m db.init_db

# Run the system
python -m main
```

No Docker. No PostgreSQL installation. No pgvector extension. Just Python.

---

## Validation After Changes

1. **Database initialization:** Run `python -m db.init_db`. Should create `data/cyrano.db` with all tables and initialize `data/questions_vectordb/`.

2. **Start a conversation:** Run `python -m main`. Cyrano should greet the farmer. The conversation should work exactly as before.

3. **Check background processing:** After a few conversation turns, check that `data/cyrano.db` has records in `extracted_facts` and the relevant Form Database tables.

4. **Check vector search:** After the Data Agent runs, verify that questions appear in `data/questions_vectordb/`. The Talk Agent should be able to search for relevant questions.

5. **Check data persistence:** Stop the system and restart. The Main DB and Form Database data should persist. The Questions DB should be cleared on new session start (as designed).

6. **Verify file structure:** After a session, the `data/` directory should contain:
   - `cyrano.db` -- Main SQLite database (Main DB + Form Databases)
   - `agno_sessions.db` -- Agno session persistence
   - `questions_vectordb/` -- LanceDB directory with vector data

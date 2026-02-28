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

"""
Tools for reading/writing the Questions Vector DB.
Handles embedding generation and vector similarity search.
"""
from typing import Optional
from uuid import UUID

from sqlalchemy import select, delete, text
from sentence_transformers import SentenceTransformer

from db.connection import SessionLocal
from db.models import SessionQuestion
from config.settings import EMBEDDING_MODEL, EMBEDDING_DIMENSION


# Initialize the embedding model (singleton)
_embedding_model: Optional[SentenceTransformer] = None


def _get_embedding_model() -> SentenceTransformer:
    """Get or initialize the embedding model."""
    global _embedding_model
    if _embedding_model is None:
        _embedding_model = SentenceTransformer(EMBEDDING_MODEL)
    return _embedding_model


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
    with SessionLocal() as db:
        question = SessionQuestion(
            session_id=session_id,
            question_text=question_text,
            source_database=source_database,
            source_table=source_table,
            source_field=source_field,
            source_record_id=UUID(source_record_id) if source_record_id else None,
            priority=priority,
            embedding=embedding
        )
        db.add(question)
        db.commit()
        db.refresh(question)
        return str(question.id)


def search_questions(
    query_embedding: list[float],
    session_id: str,
    limit: int = 5
) -> list[dict]:
    """
    Search for questions most similar to the query embedding.

    Uses cosine similarity via pgvector's <=> operator.

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
        - similarity: Cosine similarity score
    """
    with SessionLocal() as db:
        # Use pgvector's cosine distance operator
        # Lower distance = more similar, so we order ascending
        stmt = text("""
            SELECT
                id,
                question_text,
                source_database,
                source_table,
                source_field,
                source_record_id,
                priority,
                1 - (embedding <=> :embedding) as similarity
            FROM session_questions
            WHERE session_id = :session_id
            ORDER BY embedding <=> :embedding
            LIMIT :limit
        """)

        results = db.execute(
            stmt,
            {
                "embedding": str(query_embedding),
                "session_id": session_id,
                "limit": limit
            }
        ).fetchall()

        return [
            {
                "id": str(row.id),
                "question_text": row.question_text,
                "source_database": row.source_database,
                "source_table": row.source_table,
                "source_field": row.source_field,
                "source_record_id": str(row.source_record_id) if row.source_record_id else None,
                "priority": row.priority,
                "similarity": float(row.similarity)
            }
            for row in results
        ]


def clear_session_questions(session_id: str) -> str:
    """
    Clear all questions for a session.

    Called at the start of each new session to reset the questions.
    The Data Agent will regenerate questions based on current database state.

    Args:
        session_id: Session ID to clear questions for

    Returns:
        Confirmation message with count of deleted questions
    """
    with SessionLocal() as db:
        stmt = delete(SessionQuestion).where(SessionQuestion.session_id == session_id)
        result = db.execute(stmt)
        db.commit()
        return f"Cleared {result.rowcount} questions for session {session_id}"


def get_session_questions(session_id: str) -> list[dict]:
    """
    Get all questions for a session (for debugging/inspection).

    Args:
        session_id: Session ID to get questions for

    Returns:
        List of all questions for the session
    """
    with SessionLocal() as db:
        stmt = select(SessionQuestion).where(SessionQuestion.session_id == session_id)
        questions = db.execute(stmt).scalars().all()

        return [
            {
                "id": str(q.id),
                "question_text": q.question_text,
                "source_database": q.source_database,
                "source_table": q.source_table,
                "source_field": q.source_field,
                "source_record_id": str(q.source_record_id) if q.source_record_id else None,
                "priority": q.priority,
                "created_at": q.created_at.isoformat() if q.created_at else None
            }
            for q in questions
        ]


def get_question_count(session_id: str) -> int:
    """Get the count of questions for a session."""
    with SessionLocal() as db:
        from sqlalchemy import func
        stmt = select(func.count(SessionQuestion.id)).where(
            SessionQuestion.session_id == session_id
        )
        return db.execute(stmt).scalar() or 0

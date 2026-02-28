"""
Tools for reading/writing the Main DB (extracted_facts table).
Used by Extract Agent to write facts and Data Agent to read/process them.
"""
import json
from datetime import datetime
from typing import Optional

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from db.connection import SessionLocal
from db.models import ExtractedFact
from config.logging_config import get_logger

logger = get_logger("tools.main_db")


def write_extracted_fact(
    session_id: str,
    raw_text: str,
    extracted_fact: dict,
    domain: list[str],
    confidence: str
) -> str:
    """
    Write a new extracted fact to the Main DB.

    Args:
        session_id: The conversation session this fact was extracted from
        raw_text: The farmer's actual words that this fact was derived from
        extracted_fact: Structured JSON representation of the information
        domain: Which database(s) this relates to ('agricultural', 'scheduling', 'planning')
        confidence: How clearly stated ('high', 'medium', 'low')

    Returns:
        The UUID of the created record
    """
    logger.debug("Writing fact to session %s: domain=%s, confidence=%s", session_id, domain, confidence)
    with SessionLocal() as db:
        fact = ExtractedFact(
            session_id=session_id,
            raw_text=raw_text,
            extracted_fact=extracted_fact,
            domain=json.dumps(domain),
            confidence=confidence,
            verification_status="unverified",
            routed=False
        )
        db.add(fact)
        db.commit()
        db.refresh(fact)
        return str(fact.id)


def get_unrouted_facts() -> list[dict]:
    """
    Get all extracted facts that have not been routed to Form Databases yet.

    Returns:
        List of fact records as dictionaries, each containing:
        - id: UUID of the fact
        - session_id: Source session
        - raw_text: Original farmer words
        - extracted_fact: Structured data
        - domain: Target database(s)
        - confidence: Confidence level
        - timestamp: When extracted
    """
    with SessionLocal() as db:
        stmt = select(ExtractedFact).where(ExtractedFact.routed == False)
        results = db.execute(stmt).scalars().all()

        return [
            {
                "id": str(fact.id),
                "session_id": fact.session_id,
                "raw_text": fact.raw_text,
                "extracted_fact": fact.extracted_fact,
                "domain": json.loads(fact.domain) if isinstance(fact.domain, str) else fact.domain,
                "confidence": fact.confidence,
                "timestamp": fact.timestamp.isoformat() if fact.timestamp else None
            }
            for fact in results
        ]


def mark_fact_routed(fact_id: str) -> str:
    """
    Mark a fact as routed after the Data Agent has processed it.

    Args:
        fact_id: UUID of the fact to mark as routed

    Returns:
        Confirmation message
    """
    with SessionLocal() as db:
        stmt = (
            update(ExtractedFact)
            .where(ExtractedFact.id == fact_id)
            .values(routed=True)
        )
        result = db.execute(stmt)
        db.commit()

        if result.rowcount > 0:
            return f"Fact {fact_id} marked as routed"
        else:
            return f"Fact {fact_id} not found"


def get_facts_by_session(session_id: str) -> list[dict]:
    """
    Get all facts extracted from a specific session.

    Args:
        session_id: The session to query

    Returns:
        List of fact records for that session
    """
    with SessionLocal() as db:
        stmt = select(ExtractedFact).where(ExtractedFact.session_id == session_id)
        results = db.execute(stmt).scalars().all()

        return [
            {
                "id": str(fact.id),
                "raw_text": fact.raw_text,
                "extracted_fact": fact.extracted_fact,
                "domain": json.loads(fact.domain) if isinstance(fact.domain, str) else fact.domain,
                "confidence": fact.confidence,
                "routed": fact.routed,
                "timestamp": fact.timestamp.isoformat() if fact.timestamp else None
            }
            for fact in results
        ]


def get_recent_fact_for_user(user_id: str) -> Optional[dict]:
    """
    Get a recent fact for a user to use in returning conversation opening.

    Returns None if no facts exist (new farmer).

    Note: Since ExtractedFact doesn't track user_id directly, this queries
    Agno's session table to find sessions belonging to this user, then
    retrieves facts from those sessions.

    Args:
        user_id: The user identifier to look up facts for

    Returns:
        A single recent fact dict, or None if this is a new user
    """
    from sqlalchemy import text

    with SessionLocal() as db:
        # Query Agno's sessions table to find session IDs for this user
        # Agno stores sessions in 'agno_sessions' table with user_id column
        try:
            sessions_query = text("""
                SELECT session_id
                FROM agno_sessions
                WHERE user_id = :user_id
                ORDER BY created_at DESC
                LIMIT 10
            """)
            session_result = db.execute(sessions_query, {"user_id": user_id})
            session_ids = [row[0] for row in session_result.fetchall()]

            if not session_ids:
                return None

            # Get the most recent fact from these sessions
            stmt = (
                select(ExtractedFact)
                .where(ExtractedFact.session_id.in_(session_ids))
                .order_by(ExtractedFact.timestamp.desc())
                .limit(1)
            )
            result = db.execute(stmt).scalar_one_or_none()

            if result:
                return {
                    "id": str(result.id),
                    "raw_text": result.raw_text,
                    "extracted_fact": result.extracted_fact,
                    "domain": json.loads(result.domain) if isinstance(result.domain, str) else result.domain,
                    "confidence": result.confidence,
                    "timestamp": result.timestamp.isoformat() if result.timestamp else None
                }
            return None

        except Exception:
            # If Agno sessions table doesn't exist or query fails,
            # fall back to checking any recent facts (prototype behavior)
            stmt = (
                select(ExtractedFact)
                .order_by(ExtractedFact.timestamp.desc())
                .limit(1)
            )
            result = db.execute(stmt).scalar_one_or_none()

            if result:
                return {
                    "id": str(result.id),
                    "raw_text": result.raw_text,
                    "extracted_fact": result.extracted_fact,
                    "domain": json.loads(result.domain) if isinstance(result.domain, str) else result.domain,
                    "confidence": result.confidence,
                    "timestamp": result.timestamp.isoformat() if result.timestamp else None
                }
            return None

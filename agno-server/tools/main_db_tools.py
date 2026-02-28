"""
Tools for reading/writing the Main DB (extracted_facts table).
Used by Extract Agent to write facts and Data Agent to read/process them.
"""
from datetime import datetime
from typing import Optional
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from db.connection import SessionLocal
from db.models import ExtractedFact


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
    with SessionLocal() as db:
        fact = ExtractedFact(
            session_id=session_id,
            raw_text=raw_text,
            extracted_fact=extracted_fact,
            domain=domain,
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
                "domain": fact.domain,
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
            .where(ExtractedFact.id == UUID(fact_id))
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
                "domain": fact.domain,
                "confidence": fact.confidence,
                "routed": fact.routed,
                "timestamp": fact.timestamp.isoformat() if fact.timestamp else None
            }
            for fact in results
        ]

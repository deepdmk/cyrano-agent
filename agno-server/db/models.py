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

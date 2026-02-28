"""
SQLAlchemy models for all database tables.
"""
import uuid
from datetime import datetime, date, time
from decimal import Decimal
from typing import Optional, List

from sqlalchemy import (
    Column, String, Text, Boolean, Integer, Date, Time,
    DateTime, Numeric, ForeignKey, ARRAY
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import DeclarativeBase, relationship
from pgvector.sqlalchemy import Vector


class Base(DeclarativeBase):
    """Base class for all models."""
    pass


# =============================================================================
# Main DB
# =============================================================================

class ExtractedFact(Base):
    """
    Main DB: Permanent store of all structured facts extracted from conversations.
    Append-only. Written by Extract Agent, read by Data Agent.
    """
    __tablename__ = "extracted_facts"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id = Column(String, nullable=False, index=True)
    timestamp = Column(DateTime, default=datetime.utcnow, nullable=False)
    raw_text = Column(Text, nullable=False)
    extracted_fact = Column(JSONB, nullable=False)
    domain = Column(ARRAY(String), nullable=False)  # ['agricultural', 'scheduling', 'planning']
    confidence = Column(String, nullable=False)  # 'high', 'medium', 'low'
    verification_status = Column(String, default="unverified")  # 'unverified', 'confirmed', 'contradicted'
    routed = Column(Boolean, default=False, index=True)


# =============================================================================
# Agricultural Data DB (Form Database 1)
# =============================================================================

class Field(Base):
    """Agricultural field/plot information."""
    __tablename__ = "fields"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
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

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    field_id = Column(UUID(as_uuid=True), ForeignKey("fields.id"), nullable=False)
    crop_type = Column(String, nullable=False)
    variety = Column(String)
    planting_date = Column(Date)
    expected_harvest_date = Column(Date)
    actual_harvest_date = Column(Date)
    seed_source = Column(String)
    seed_quantity = Column(String)
    status = Column(String)  # 'planted', 'growing', 'harvested', 'failed'
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

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    field_id = Column(UUID(as_uuid=True), ForeignKey("fields.id"), nullable=False)
    crop_id = Column(UUID(as_uuid=True), ForeignKey("crops.id"))  # Optional
    input_type = Column(String, nullable=False)  # 'fertilizer', 'pesticide', 'herbicide', etc.
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

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    crop_id = Column(UUID(as_uuid=True), ForeignKey("crops.id"), nullable=False)
    field_id = Column(UUID(as_uuid=True), ForeignKey("fields.id"), nullable=False)
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

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    date = Column(Date, nullable=False)
    observation_type = Column(String, nullable=False)  # 'rain', 'drought', 'frost', etc.
    severity = Column(String)  # 'mild', 'moderate', 'severe'
    description = Column(Text)
    impact = Column(Text)
    field_id = Column(UUID(as_uuid=True), ForeignKey("fields.id"))  # Optional
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

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_type = Column(String, nullable=False)  # 'meeting', 'delivery', 'market', etc.
    description = Column(Text)
    date = Column(Date)
    time = Column(Time)
    location = Column(String)
    people_involved = Column(Text)
    is_recurring = Column(Boolean, default=False)
    recurrence_frequency = Column(String)  # 'daily', 'weekly', 'monthly', etc.
    status = Column(String, default="planned")  # 'planned', 'completed', 'cancelled'
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


# =============================================================================
# Planning DB (Form Database 3)
# =============================================================================

class Plan(Base):
    """Future plans and intentions."""
    __tablename__ = "plans"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    category = Column(String, nullable=False)  # 'planting', 'expansion', 'investment', etc.
    description = Column(Text, nullable=False)
    target_season = Column(String)
    target_year = Column(Integer)
    field_id = Column(UUID(as_uuid=True), ForeignKey("fields.id"))  # Optional
    resources_needed = Column(Text)
    estimated_cost = Column(Numeric(10, 2))
    currency = Column(String)
    status = Column(String, default="intended")  # 'intended', 'in_progress', 'completed', 'abandoned'
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    field = relationship("Field", back_populates="plans")


# =============================================================================
# Questions Vector DB
# =============================================================================

class SessionQuestion(Base):
    """
    Questions Vector DB: Ephemeral storage for questions the Talk Agent can weave
    into conversation. Cleared at the start of each new session.
    """
    __tablename__ = "session_questions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id = Column(String, nullable=False, index=True)
    question_text = Column(Text, nullable=False)
    source_database = Column(String, nullable=False)
    source_table = Column(String, nullable=False)
    source_field = Column(String, nullable=False)
    source_record_id = Column(UUID(as_uuid=True))  # Optional
    priority = Column(String, nullable=False)  # 'high', 'medium', 'low'
    embedding = Column(Vector(768), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

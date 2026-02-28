"""
Tools for reading/writing Form Databases (Agricultural, Scheduling, Planning).
Used by Data Agent to route extracted facts and analyze gaps.
"""
from datetime import date, time, datetime
from decimal import Decimal
from typing import Optional, Any

from sqlalchemy import select, update, func
from sqlalchemy.orm import Session

from db.connection import SessionLocal
from db.models import Field, Crop, Input, Yield, WeatherObservation, Event, Plan


# =============================================================================
# Helper Functions
# =============================================================================

def _to_dict(obj, exclude: list[str] = None) -> dict:
    """Convert SQLAlchemy model to dictionary."""
    exclude = exclude or []
    result = {}
    for column in obj.__table__.columns:
        if column.name in exclude:
            continue
        value = getattr(obj, column.name)
        if isinstance(value, (datetime, date)):
            value = value.isoformat()
        elif isinstance(value, time):
            value = value.isoformat()
        elif isinstance(value, Decimal):
            value = float(value)
        result[column.name] = value
    return result


def _parse_date(value: Optional[str]) -> Optional[date]:
    """Parse date string to date object."""
    if not value:
        return None
    if isinstance(value, date):
        return value
    return datetime.fromisoformat(value).date()


def _parse_time(value: Optional[str]) -> Optional[time]:
    """Parse time string to time object."""
    if not value:
        return None
    if isinstance(value, time):
        return value
    return datetime.strptime(value, "%H:%M:%S").time()


# =============================================================================
# Fields Table
# =============================================================================

def create_field(
    name: str,
    size_hectares: Optional[float] = None,
    location_description: Optional[str] = None,
    soil_type: Optional[str] = None,
    irrigation_method: Optional[str] = None,
    notes: Optional[str] = None
) -> str:
    """
    Create a new field record.

    Args:
        name: Farmer's name for this plot (e.g., "north field")
        size_hectares: Area in hectares
        location_description: How the farmer describes where it is
        soil_type: Soil type if known
        irrigation_method: Rainfed, drip, canal, well, etc.
        notes: Anything else mentioned about this field

    Returns:
        UUID of the created field
    """
    with SessionLocal() as db:
        field = Field(
            name=name,
            size_hectares=Decimal(str(size_hectares)) if size_hectares else None,
            location_description=location_description,
            soil_type=soil_type,
            irrigation_method=irrigation_method,
            notes=notes
        )
        db.add(field)
        db.commit()
        db.refresh(field)
        return str(field.id)


def update_field(field_id: str, **kwargs) -> str:
    """
    Update an existing field record.

    Args:
        field_id: UUID of the field to update
        **kwargs: Fields to update (name, size_hectares, location_description, etc.)

    Returns:
        Confirmation message
    """
    with SessionLocal() as db:
        # Convert size_hectares to Decimal if provided
        if "size_hectares" in kwargs and kwargs["size_hectares"] is not None:
            kwargs["size_hectares"] = Decimal(str(kwargs["size_hectares"]))

        stmt = (
            update(Field)
            .where(Field.id == field_id)
            .values(**kwargs)
        )
        result = db.execute(stmt)
        db.commit()

        if result.rowcount > 0:
            return f"Field {field_id} updated"
        return f"Field {field_id} not found"


def get_field(field_id: str) -> Optional[dict]:
    """Get a field by ID."""
    with SessionLocal() as db:
        field = db.get(Field, field_id)
        return _to_dict(field) if field else None


def get_all_fields() -> list[dict]:
    """Get all fields."""
    with SessionLocal() as db:
        fields = db.execute(select(Field)).scalars().all()
        return [_to_dict(f) for f in fields]


def get_field_by_name(name: str) -> Optional[dict]:
    """Find a field by name (case-insensitive partial match)."""
    with SessionLocal() as db:
        stmt = select(Field).where(Field.name.ilike(f"%{name}%"))
        field = db.execute(stmt).scalars().first()
        return _to_dict(field) if field else None


# =============================================================================
# Crops Table
# =============================================================================

def create_crop(
    field_id: str,
    crop_type: str,
    variety: Optional[str] = None,
    planting_date: Optional[str] = None,
    expected_harvest_date: Optional[str] = None,
    actual_harvest_date: Optional[str] = None,
    seed_source: Optional[str] = None,
    seed_quantity: Optional[str] = None,
    status: Optional[str] = None,
    notes: Optional[str] = None
) -> str:
    """
    Create a new crop record.

    Args:
        field_id: UUID of the field this crop is in
        crop_type: Type of crop (maize, rice, beans, etc.)
        variety: Specific variety if mentioned
        planting_date: When planted (ISO date string)
        expected_harvest_date: Expected harvest date
        actual_harvest_date: Actual harvest date if harvested
        seed_source: Where seeds came from
        seed_quantity: Amount of seed used
        status: 'planted', 'growing', 'harvested', 'failed'
        notes: Additional notes

    Returns:
        UUID of the created crop
    """
    with SessionLocal() as db:
        crop = Crop(
            field_id=field_id,
            crop_type=crop_type,
            variety=variety,
            planting_date=_parse_date(planting_date),
            expected_harvest_date=_parse_date(expected_harvest_date),
            actual_harvest_date=_parse_date(actual_harvest_date),
            seed_source=seed_source,
            seed_quantity=seed_quantity,
            status=status,
            notes=notes
        )
        db.add(crop)
        db.commit()
        db.refresh(crop)
        return str(crop.id)


def update_crop(crop_id: str, **kwargs) -> str:
    """Update an existing crop record."""
    with SessionLocal() as db:
        # Parse dates if provided
        for date_field in ["planting_date", "expected_harvest_date", "actual_harvest_date"]:
            if date_field in kwargs:
                kwargs[date_field] = _parse_date(kwargs[date_field])

        stmt = (
            update(Crop)
            .where(Crop.id == crop_id)
            .values(**kwargs)
        )
        result = db.execute(stmt)
        db.commit()

        if result.rowcount > 0:
            return f"Crop {crop_id} updated"
        return f"Crop {crop_id} not found"


def get_crop(crop_id: str) -> Optional[dict]:
    """Get a crop by ID."""
    with SessionLocal() as db:
        crop = db.get(Crop, crop_id)
        return _to_dict(crop) if crop else None


def get_all_crops() -> list[dict]:
    """Get all crops."""
    with SessionLocal() as db:
        crops = db.execute(select(Crop)).scalars().all()
        return [_to_dict(c) for c in crops]


def get_crops_by_field(field_id: str) -> list[dict]:
    """Get all crops in a specific field."""
    with SessionLocal() as db:
        stmt = select(Crop).where(Crop.field_id == field_id)
        crops = db.execute(stmt).scalars().all()
        return [_to_dict(c) for c in crops]


# =============================================================================
# Inputs Table
# =============================================================================

def create_input(
    field_id: str,
    input_type: str,
    crop_id: Optional[str] = None,
    product_name: Optional[str] = None,
    quantity: Optional[float] = None,
    unit: Optional[str] = None,
    date_applied: Optional[str] = None,
    cost: Optional[float] = None,
    currency: Optional[str] = None,
    notes: Optional[str] = None
) -> str:
    """
    Create a new input record (fertilizer, pesticide, etc.).

    Args:
        field_id: UUID of the field
        input_type: Type of input ('fertilizer', 'pesticide', 'herbicide', etc.)
        crop_id: Optional UUID of specific crop
        product_name: Brand or generic name
        quantity: Amount applied
        unit: Unit of measure (kg, liters, bags, etc.)
        date_applied: When applied
        cost: Cost if mentioned
        currency: Currency code
        notes: Additional notes

    Returns:
        UUID of the created input
    """
    with SessionLocal() as db:
        input_record = Input(
            field_id=field_id,
            crop_id=crop_id if crop_id else None,
            input_type=input_type,
            product_name=product_name,
            quantity=Decimal(str(quantity)) if quantity else None,
            unit=unit,
            date_applied=_parse_date(date_applied),
            cost=Decimal(str(cost)) if cost else None,
            currency=currency,
            notes=notes
        )
        db.add(input_record)
        db.commit()
        db.refresh(input_record)
        return str(input_record.id)


def update_input(input_id: str, **kwargs) -> str:
    """Update an existing input record."""
    with SessionLocal() as db:
        if "date_applied" in kwargs:
            kwargs["date_applied"] = _parse_date(kwargs["date_applied"])
        if "quantity" in kwargs and kwargs["quantity"] is not None:
            kwargs["quantity"] = Decimal(str(kwargs["quantity"]))
        if "cost" in kwargs and kwargs["cost"] is not None:
            kwargs["cost"] = Decimal(str(kwargs["cost"]))
        # crop_id is already a string, no conversion needed

        stmt = (
            update(Input)
            .where(Input.id == input_id)
            .values(**kwargs)
        )
        result = db.execute(stmt)
        db.commit()

        if result.rowcount > 0:
            return f"Input {input_id} updated"
        return f"Input {input_id} not found"


def get_input(input_id: str) -> Optional[dict]:
    """Get an input by ID."""
    with SessionLocal() as db:
        input_record = db.get(Input, input_id)
        return _to_dict(input_record) if input_record else None


def get_all_inputs() -> list[dict]:
    """Get all inputs."""
    with SessionLocal() as db:
        inputs = db.execute(select(Input)).scalars().all()
        return [_to_dict(i) for i in inputs]


# =============================================================================
# Yields Table
# =============================================================================

def create_yield(
    crop_id: str,
    field_id: str,
    harvest_date: Optional[str] = None,
    quantity: Optional[float] = None,
    unit: Optional[str] = None,
    quality_notes: Optional[str] = None,
    sale_price: Optional[float] = None,
    currency: Optional[str] = None,
    buyer: Optional[str] = None,
    notes: Optional[str] = None
) -> str:
    """
    Create a new yield/harvest record.

    Args:
        crop_id: UUID of the crop
        field_id: UUID of the field
        harvest_date: When harvested
        quantity: Amount harvested
        unit: Unit of measure
        quality_notes: Farmer's quality assessment
        sale_price: Price per unit if sold
        currency: Currency code
        buyer: Who bought it
        notes: Additional notes

    Returns:
        UUID of the created yield
    """
    with SessionLocal() as db:
        yield_record = Yield(
            crop_id=crop_id,
            field_id=field_id,
            harvest_date=_parse_date(harvest_date),
            quantity=Decimal(str(quantity)) if quantity else None,
            unit=unit,
            quality_notes=quality_notes,
            sale_price=Decimal(str(sale_price)) if sale_price else None,
            currency=currency,
            buyer=buyer,
            notes=notes
        )
        db.add(yield_record)
        db.commit()
        db.refresh(yield_record)
        return str(yield_record.id)


def update_yield(yield_id: str, **kwargs) -> str:
    """Update an existing yield record."""
    with SessionLocal() as db:
        if "harvest_date" in kwargs:
            kwargs["harvest_date"] = _parse_date(kwargs["harvest_date"])
        if "quantity" in kwargs and kwargs["quantity"] is not None:
            kwargs["quantity"] = Decimal(str(kwargs["quantity"]))
        if "sale_price" in kwargs and kwargs["sale_price"] is not None:
            kwargs["sale_price"] = Decimal(str(kwargs["sale_price"]))

        stmt = (
            update(Yield)
            .where(Yield.id == yield_id)
            .values(**kwargs)
        )
        result = db.execute(stmt)
        db.commit()

        if result.rowcount > 0:
            return f"Yield {yield_id} updated"
        return f"Yield {yield_id} not found"


def get_yield(yield_id: str) -> Optional[dict]:
    """Get a yield by ID."""
    with SessionLocal() as db:
        yield_record = db.get(Yield, yield_id)
        return _to_dict(yield_record) if yield_record else None


def get_all_yields() -> list[dict]:
    """Get all yields."""
    with SessionLocal() as db:
        yields = db.execute(select(Yield)).scalars().all()
        return [_to_dict(y) for y in yields]


# =============================================================================
# Weather Observations Table
# =============================================================================

def create_weather_observation(
    date: str,
    observation_type: str,
    severity: Optional[str] = None,
    description: Optional[str] = None,
    impact: Optional[str] = None,
    field_id: Optional[str] = None,
    notes: Optional[str] = None
) -> str:
    """
    Create a new weather observation.

    Args:
        date: Date of observation
        observation_type: Type ('rain', 'drought', 'frost', 'flood', etc.)
        severity: 'mild', 'moderate', 'severe'
        description: Farmer's description
        impact: How it affected crops or activities
        field_id: Optional specific field affected
        notes: Additional notes

    Returns:
        UUID of the created observation
    """
    with SessionLocal() as db:
        obs = WeatherObservation(
            date=_parse_date(date),
            observation_type=observation_type,
            severity=severity,
            description=description,
            impact=impact,
            field_id=field_id if field_id else None,
            notes=notes
        )
        db.add(obs)
        db.commit()
        db.refresh(obs)
        return str(obs.id)


def update_weather_observation(observation_id: str, **kwargs) -> str:
    """Update an existing weather observation."""
    with SessionLocal() as db:
        if "date" in kwargs:
            kwargs["date"] = _parse_date(kwargs["date"])
        # field_id is already a string, no conversion needed

        stmt = (
            update(WeatherObservation)
            .where(WeatherObservation.id == observation_id)
            .values(**kwargs)
        )
        result = db.execute(stmt)
        db.commit()

        if result.rowcount > 0:
            return f"Weather observation {observation_id} updated"
        return f"Weather observation {observation_id} not found"


def get_weather_observation(observation_id: str) -> Optional[dict]:
    """Get a weather observation by ID."""
    with SessionLocal() as db:
        obs = db.get(WeatherObservation, observation_id)
        return _to_dict(obs) if obs else None


def get_all_weather_observations() -> list[dict]:
    """Get all weather observations."""
    with SessionLocal() as db:
        observations = db.execute(select(WeatherObservation)).scalars().all()
        return [_to_dict(o) for o in observations]


# =============================================================================
# Events Table (Scheduling DB)
# =============================================================================

def create_event(
    event_type: str,
    description: Optional[str] = None,
    date: Optional[str] = None,
    time: Optional[str] = None,
    location: Optional[str] = None,
    people_involved: Optional[str] = None,
    is_recurring: bool = False,
    recurrence_frequency: Optional[str] = None,
    status: str = "planned",
    notes: Optional[str] = None
) -> str:
    """
    Create a new calendar event.

    Args:
        event_type: Type of event ('meeting', 'delivery', 'market', etc.)
        description: What this event is about
        date: When it happens (ISO date string)
        time: Time if specified (HH:MM:SS)
        location: Where it happens
        people_involved: Names or roles of people involved
        is_recurring: Whether this repeats
        recurrence_frequency: 'daily', 'weekly', 'monthly', etc.
        status: 'planned', 'completed', 'cancelled'
        notes: Additional notes

    Returns:
        UUID of the created event
    """
    with SessionLocal() as db:
        event = Event(
            event_type=event_type,
            description=description,
            date=_parse_date(date),
            time=_parse_time(time),
            location=location,
            people_involved=people_involved,
            is_recurring=is_recurring,
            recurrence_frequency=recurrence_frequency,
            status=status,
            notes=notes
        )
        db.add(event)
        db.commit()
        db.refresh(event)
        return str(event.id)


def update_event(event_id: str, **kwargs) -> str:
    """Update an existing event."""
    with SessionLocal() as db:
        if "date" in kwargs:
            kwargs["date"] = _parse_date(kwargs["date"])
        if "time" in kwargs:
            kwargs["time"] = _parse_time(kwargs["time"])

        stmt = (
            update(Event)
            .where(Event.id == event_id)
            .values(**kwargs)
        )
        result = db.execute(stmt)
        db.commit()

        if result.rowcount > 0:
            return f"Event {event_id} updated"
        return f"Event {event_id} not found"


def get_event(event_id: str) -> Optional[dict]:
    """Get an event by ID."""
    with SessionLocal() as db:
        event = db.get(Event, event_id)
        return _to_dict(event) if event else None


def get_all_events() -> list[dict]:
    """Get all events."""
    with SessionLocal() as db:
        events = db.execute(select(Event)).scalars().all()
        return [_to_dict(e) for e in events]


# =============================================================================
# Plans Table (Planning DB)
# =============================================================================

def create_plan(
    category: str,
    description: str,
    target_season: Optional[str] = None,
    target_year: Optional[int] = None,
    field_id: Optional[str] = None,
    resources_needed: Optional[str] = None,
    estimated_cost: Optional[float] = None,
    currency: Optional[str] = None,
    status: str = "intended",
    notes: Optional[str] = None
) -> str:
    """
    Create a new plan record.

    Args:
        category: Category ('planting', 'expansion', 'investment', etc.)
        description: What the farmer plans to do
        target_season: Target season description
        target_year: Target year
        field_id: Optional related field
        resources_needed: What they need to execute
        estimated_cost: Budget if mentioned
        currency: Currency code
        status: 'intended', 'in_progress', 'completed', 'abandoned'
        notes: Additional notes

    Returns:
        UUID of the created plan
    """
    with SessionLocal() as db:
        plan = Plan(
            category=category,
            description=description,
            target_season=target_season,
            target_year=target_year,
            field_id=field_id if field_id else None,
            resources_needed=resources_needed,
            estimated_cost=Decimal(str(estimated_cost)) if estimated_cost else None,
            currency=currency,
            status=status,
            notes=notes
        )
        db.add(plan)
        db.commit()
        db.refresh(plan)
        return str(plan.id)


def update_plan(plan_id: str, **kwargs) -> str:
    """Update an existing plan."""
    with SessionLocal() as db:
        # field_id is already a string, no conversion needed
        if "estimated_cost" in kwargs and kwargs["estimated_cost"] is not None:
            kwargs["estimated_cost"] = Decimal(str(kwargs["estimated_cost"]))

        stmt = (
            update(Plan)
            .where(Plan.id == plan_id)
            .values(**kwargs)
        )
        result = db.execute(stmt)
        db.commit()

        if result.rowcount > 0:
            return f"Plan {plan_id} updated"
        return f"Plan {plan_id} not found"


def get_plan(plan_id: str) -> Optional[dict]:
    """Get a plan by ID."""
    with SessionLocal() as db:
        plan = db.get(Plan, plan_id)
        return _to_dict(plan) if plan else None


def get_all_plans() -> list[dict]:
    """Get all plans."""
    with SessionLocal() as db:
        plans = db.execute(select(Plan)).scalars().all()
        return [_to_dict(p) for p in plans]


# =============================================================================
# Database Summary (Gap Analysis)
# =============================================================================

def get_database_summary() -> dict:
    """
    Get a summary of all Form Databases for gap analysis.

    Returns a summary including:
    - Record counts for each table
    - Records with NULL values in key fields

    Used by the Data Agent to identify what information is missing.
    """
    with SessionLocal() as db:
        summary = {
            "fields": {
                "count": db.execute(select(func.count(Field.id))).scalar(),
                "missing_size": [],
                "missing_soil_type": [],
                "missing_irrigation": []
            },
            "crops": {
                "count": db.execute(select(func.count(Crop.id))).scalar(),
                "missing_planting_date": [],
                "missing_status": [],
                "missing_variety": []
            },
            "inputs": {
                "count": db.execute(select(func.count(Input.id))).scalar(),
                "missing_quantity": [],
                "missing_date_applied": []
            },
            "yields": {
                "count": db.execute(select(func.count(Yield.id))).scalar(),
                "missing_quantity": [],
                "missing_harvest_date": []
            },
            "weather_observations": {
                "count": db.execute(select(func.count(WeatherObservation.id))).scalar()
            },
            "events": {
                "count": db.execute(select(func.count(Event.id))).scalar(),
                "missing_date": [],
                "missing_description": []
            },
            "plans": {
                "count": db.execute(select(func.count(Plan.id))).scalar(),
                "missing_target_season": [],
                "missing_resources_needed": []
            }
        }

        # Find fields with missing data
        for field in db.execute(select(Field)).scalars().all():
            field_info = {"id": str(field.id), "name": field.name}
            if not field.size_hectares:
                summary["fields"]["missing_size"].append(field_info)
            if not field.soil_type:
                summary["fields"]["missing_soil_type"].append(field_info)
            if not field.irrigation_method:
                summary["fields"]["missing_irrigation"].append(field_info)

        # Find crops with missing data
        for crop in db.execute(select(Crop)).scalars().all():
            crop_info = {"id": str(crop.id), "crop_type": crop.crop_type, "field_id": str(crop.field_id)}
            if not crop.planting_date:
                summary["crops"]["missing_planting_date"].append(crop_info)
            if not crop.status:
                summary["crops"]["missing_status"].append(crop_info)
            if not crop.variety:
                summary["crops"]["missing_variety"].append(crop_info)

        # Find inputs with missing data
        for input_rec in db.execute(select(Input)).scalars().all():
            input_info = {"id": str(input_rec.id), "input_type": input_rec.input_type}
            if not input_rec.quantity:
                summary["inputs"]["missing_quantity"].append(input_info)
            if not input_rec.date_applied:
                summary["inputs"]["missing_date_applied"].append(input_info)

        # Find yields with missing data
        for yield_rec in db.execute(select(Yield)).scalars().all():
            yield_info = {"id": str(yield_rec.id), "crop_id": str(yield_rec.crop_id)}
            if not yield_rec.quantity:
                summary["yields"]["missing_quantity"].append(yield_info)
            if not yield_rec.harvest_date:
                summary["yields"]["missing_harvest_date"].append(yield_info)

        # Find events with missing data
        for event in db.execute(select(Event)).scalars().all():
            event_info = {"id": str(event.id), "event_type": event.event_type}
            if not event.date:
                summary["events"]["missing_date"].append(event_info)
            if not event.description:
                summary["events"]["missing_description"].append(event_info)

        # Find plans with missing data
        for plan in db.execute(select(Plan)).scalars().all():
            plan_info = {"id": str(plan.id), "category": plan.category}
            if not plan.target_season:
                summary["plans"]["missing_target_season"].append(plan_info)
            if not plan.resources_needed:
                summary["plans"]["missing_resources_needed"].append(plan_info)

        return summary

"""
Seed test data for development and testing.

Creates sample records in the Form Databases for testing purposes.

Run with: python -m scripts.seed_test_data
"""
from datetime import date, timedelta

from tools.form_db_tools import (
    create_field, create_crop, create_input, create_event, create_plan,
    get_all_fields, get_all_crops
)
from tools.questions_tools import write_question, generate_embedding


def seed_fields():
    """Create sample field records."""
    fields = [
        {
            "name": "North Field",
            "size_hectares": 2.5,
            "location_description": "Near the main road, north of the farmhouse",
            "soil_type": "black clay",
            "irrigation_method": "canal"
        },
        {
            "name": "South Field",
            "size_hectares": 1.5,
            "location_description": "Behind the storage shed",
            "soil_type": "sandy loam",
            "irrigation_method": "rainfed"
        },
        {
            "name": "River Plot",
            "size_hectares": None,  # Missing size for testing gaps
            "location_description": "Along the riverbank",
            "soil_type": None,
            "irrigation_method": "flood"
        }
    ]

    created_ids = []
    for field in fields:
        field_id = create_field(**field)
        created_ids.append(field_id)
        print(f"Created field: {field['name']} ({field_id})")

    return created_ids


def seed_crops(field_ids: list):
    """Create sample crop records."""
    today = date.today()

    crops = [
        {
            "field_id": field_ids[0],
            "crop_type": "maize",
            "variety": "hybrid 614",
            "planting_date": (today - timedelta(days=30)).isoformat(),
            "expected_harvest_date": (today + timedelta(days=60)).isoformat(),
            "status": "growing"
        },
        {
            "field_id": field_ids[1],
            "crop_type": "beans",
            "variety": None,  # Missing variety for testing gaps
            "planting_date": None,  # Missing planting date
            "status": "planted"
        }
    ]

    created_ids = []
    for crop in crops:
        crop_id = create_crop(**crop)
        created_ids.append(crop_id)
        print(f"Created crop: {crop['crop_type']} ({crop_id})")

    return created_ids


def seed_inputs(field_ids: list, crop_ids: list):
    """Create sample input records."""
    today = date.today()

    inputs = [
        {
            "field_id": field_ids[0],
            "crop_id": crop_ids[0],
            "input_type": "fertilizer",
            "product_name": "NPK 20-20-20",
            "quantity": 50,
            "unit": "kg",
            "date_applied": (today - timedelta(days=7)).isoformat()
        },
        {
            "field_id": field_ids[0],
            "input_type": "pesticide",
            "product_name": None,  # Missing product name
            "quantity": None,
            "unit": "liters",
            "date_applied": None
        }
    ]

    for inp in inputs:
        input_id = create_input(**inp)
        print(f"Created input: {inp['input_type']} ({input_id})")


def seed_events():
    """Create sample event records."""
    today = date.today()

    events = [
        {
            "event_type": "delivery",
            "description": "Seed delivery from cooperative",
            "date": (today + timedelta(days=3)).isoformat(),
            "time": "09:00:00",
            "location": "Farm gate",
            "status": "planned"
        },
        {
            "event_type": "market",
            "description": "Weekly market day",
            "date": (today + timedelta(days=5)).isoformat(),
            "location": "Town center",
            "is_recurring": True,
            "recurrence_frequency": "weekly"
        },
        {
            "event_type": "meeting",
            "description": None,  # Missing description
            "date": None,  # Missing date
            "status": "planned"
        }
    ]

    for event in events:
        event_id = create_event(**event)
        print(f"Created event: {event['event_type']} ({event_id})")


def seed_plans(field_ids: list):
    """Create sample plan records."""
    plans = [
        {
            "category": "planting",
            "description": "Plant beans in south field next season",
            "target_season": "next rainy season",
            "target_year": 2026,
            "field_id": field_ids[1]
        },
        {
            "category": "expansion",
            "description": "Expand river plot cultivation",
            "target_season": None,  # Missing target season
            "resources_needed": None,  # Missing resources
            "field_id": field_ids[2]
        }
    ]

    for plan in plans:
        plan_id = create_plan(**plan)
        print(f"Created plan: {plan['category']} ({plan_id})")


def seed_questions(session_id: str = "test_session"):
    """Create sample questions in the vector DB."""
    questions = [
        {
            "question_text": "How large is the river plot, roughly?",
            "source_database": "agricultural",
            "source_table": "fields",
            "source_field": "size_hectares",
            "priority": "high"
        },
        {
            "question_text": "What type of soil does the river plot have?",
            "source_database": "agricultural",
            "source_table": "fields",
            "source_field": "soil_type",
            "priority": "medium"
        },
        {
            "question_text": "When did you plant the beans?",
            "source_database": "agricultural",
            "source_table": "crops",
            "source_field": "planting_date",
            "priority": "high"
        },
        {
            "question_text": "What variety of beans are you growing?",
            "source_database": "agricultural",
            "source_table": "crops",
            "source_field": "variety",
            "priority": "low"
        }
    ]

    for q in questions:
        embedding = generate_embedding(q["question_text"])
        question_id = write_question(
            session_id=session_id,
            embedding=embedding,
            **q
        )
        print(f"Created question: {q['question_text'][:40]}... ({question_id})")


def run_seed():
    """Run all seed functions."""
    print("\n" + "="*60)
    print("  Seeding Test Data")
    print("="*60 + "\n")

    # Check if data already exists
    existing_fields = get_all_fields()
    if existing_fields:
        print(f"Warning: {len(existing_fields)} fields already exist.")
        response = input("Continue and add more data? (y/n): ")
        if response.lower() != 'y':
            print("Aborted.")
            return

    print("\n1. Seeding fields...")
    field_ids = seed_fields()

    print("\n2. Seeding crops...")
    crop_ids = seed_crops(field_ids)

    print("\n3. Seeding inputs...")
    seed_inputs(field_ids, crop_ids)

    print("\n4. Seeding events...")
    seed_events()

    print("\n5. Seeding plans...")
    seed_plans(field_ids)

    print("\n6. Seeding sample questions...")
    seed_questions()

    print("\n" + "="*60)
    print("  Seed Data Complete")
    print("="*60)
    print("\nYou can now run the validation script:")
    print("  python -m scripts.validate_data_flow test_session")


if __name__ == "__main__":
    run_seed()

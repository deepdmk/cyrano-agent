"""
Data flow validation script.

Verifies that the data pipeline is working correctly:
- All extracted facts have been routed
- Form Database records exist
- Questions reference real gaps

Run with: python -m scripts.validate_data_flow [session_id]
"""
import sys
from uuid import UUID

from tools.main_db_tools import get_facts_by_session
from tools.form_db_tools import (
    get_all_fields, get_all_crops, get_all_inputs, get_all_yields,
    get_all_weather_observations, get_all_events, get_all_plans,
    get_database_summary
)
from tools.questions_tools import get_session_questions


def validate_facts_routed(session_id: str) -> dict:
    """Check that all facts have been routed."""
    facts = get_facts_by_session(session_id)

    routed = [f for f in facts if f["routed"]]
    unrouted = [f for f in facts if not f["routed"]]

    return {
        "total": len(facts),
        "routed": len(routed),
        "unrouted": len(unrouted),
        "unrouted_facts": unrouted,
        "pass": len(unrouted) == 0
    }


def validate_form_databases() -> dict:
    """Check Form Database record counts and consistency."""
    fields = get_all_fields()
    crops = get_all_crops()
    inputs = get_all_inputs()
    yields = get_all_yields()
    weather = get_all_weather_observations()
    events = get_all_events()
    plans = get_all_plans()

    # Check foreign key consistency
    field_ids = {f["id"] for f in fields}
    crop_ids = {c["id"] for c in crops}

    orphan_crops = [c for c in crops if c["field_id"] not in field_ids]
    orphan_inputs = [i for i in inputs if i["field_id"] not in field_ids]
    orphan_yields = [y for y in yields if y["field_id"] not in field_ids or y["crop_id"] not in crop_ids]

    return {
        "counts": {
            "fields": len(fields),
            "crops": len(crops),
            "inputs": len(inputs),
            "yields": len(yields),
            "weather_observations": len(weather),
            "events": len(events),
            "plans": len(plans)
        },
        "orphan_crops": len(orphan_crops),
        "orphan_inputs": len(orphan_inputs),
        "orphan_yields": len(orphan_yields),
        "pass": len(orphan_crops) == 0 and len(orphan_inputs) == 0 and len(orphan_yields) == 0
    }


def validate_questions(session_id: str) -> dict:
    """Check that questions reference real gaps."""
    questions = get_session_questions(session_id)
    summary = get_database_summary()

    # Check that questions reference actual tables
    valid_tables = {"fields", "crops", "inputs", "yields", "weather_observations", "events", "plans"}

    invalid_questions = []
    for q in questions:
        if q["source_table"] not in valid_tables:
            invalid_questions.append(q)

    # Check priority distribution
    priorities = {"high": 0, "medium": 0, "low": 0}
    for q in questions:
        if q["priority"] in priorities:
            priorities[q["priority"]] += 1

    return {
        "total": len(questions),
        "invalid_table_refs": len(invalid_questions),
        "priorities": priorities,
        "pass": len(invalid_questions) == 0
    }


def validate_no_duplicates() -> dict:
    """Check for duplicate records in Form Databases."""
    fields = get_all_fields()
    events = get_all_events()

    # Check for duplicate field names
    field_names = [f["name"].lower().strip() for f in fields]
    duplicate_fields = [name for name in field_names if field_names.count(name) > 1]

    # Check for duplicate events (same type, date, description)
    event_keys = []
    duplicate_events = []
    for e in events:
        key = (e["event_type"], str(e["date"]), (e["description"] or "")[:50])
        if key in event_keys:
            duplicate_events.append(e)
        event_keys.append(key)

    return {
        "duplicate_field_names": list(set(duplicate_fields)),
        "duplicate_events": len(duplicate_events),
        "pass": len(duplicate_fields) == 0 and len(duplicate_events) == 0
    }


def run_validation(session_id: str = None):
    """Run all validation checks."""
    print("\n" + "="*60)
    print("  Data Flow Validation")
    print("="*60 + "\n")

    results = {}

    # 1. Validate facts are routed
    if session_id:
        print("1. Validating extracted facts...")
        facts_result = validate_facts_routed(session_id)
        results["facts"] = facts_result
        status = "PASS" if facts_result["pass"] else "FAIL"
        print(f"   [{status}] {facts_result['routed']}/{facts_result['total']} facts routed")
        if facts_result["unrouted"]:
            print(f"   Unrouted facts: {len(facts_result['unrouted'])}")
    else:
        print("1. Skipping fact validation (no session_id provided)")

    # 2. Validate Form Databases
    print("\n2. Validating Form Database records...")
    db_result = validate_form_databases()
    results["databases"] = db_result
    status = "PASS" if db_result["pass"] else "FAIL"
    print(f"   [{status}] Record counts:")
    for table, count in db_result["counts"].items():
        print(f"       {table}: {count}")
    if not db_result["pass"]:
        print(f"   Orphan records found: crops={db_result['orphan_crops']}, "
              f"inputs={db_result['orphan_inputs']}, yields={db_result['orphan_yields']}")

    # 3. Validate questions
    if session_id:
        print("\n3. Validating questions...")
        questions_result = validate_questions(session_id)
        results["questions"] = questions_result
        status = "PASS" if questions_result["pass"] else "FAIL"
        print(f"   [{status}] {questions_result['total']} questions generated")
        print(f"   Priority distribution: {questions_result['priorities']}")
        if questions_result["invalid_table_refs"] > 0:
            print(f"   Invalid table references: {questions_result['invalid_table_refs']}")
    else:
        print("\n3. Skipping question validation (no session_id provided)")

    # 4. Check for duplicates
    print("\n4. Checking for duplicates...")
    dup_result = validate_no_duplicates()
    results["duplicates"] = dup_result
    status = "PASS" if dup_result["pass"] else "FAIL"
    print(f"   [{status}] Duplicate check")
    if dup_result["duplicate_field_names"]:
        print(f"   Duplicate field names: {dup_result['duplicate_field_names']}")
    if dup_result["duplicate_events"] > 0:
        print(f"   Duplicate events: {dup_result['duplicate_events']}")

    # Summary
    print("\n" + "="*60)
    all_pass = all(r.get("pass", True) for r in results.values())
    print(f"  Overall: {'ALL CHECKS PASSED' if all_pass else 'SOME CHECKS FAILED'}")
    print("="*60 + "\n")

    return results


if __name__ == "__main__":
    session_id = sys.argv[1] if len(sys.argv) > 1 else None

    if not session_id:
        print("Note: Running without session_id. Some checks will be skipped.")
        print("Usage: python -m scripts.validate_data_flow [session_id]")

    results = run_validation(session_id)

"""
Health check diagnostic script for the Cyrano Agent system.

Run with: python -m health_check

Checks:
1. Configuration (API key, database, data directory)
2. Dependencies (required packages)
3. Agent initialization (can each agent be created)
4. Optional: API connectivity test
"""
import sys
import os
from pathlib import Path

# Ensure we can import from the agno-server directory
sys.path.insert(0, str(Path(__file__).parent))


def print_header(title: str):
    print(f"\n{'='*60}")
    print(f"  {title}")
    print('='*60)


def print_check(name: str, passed: bool, details: str = ""):
    status = "✅" if passed else "❌"
    print(f"  {status} {name}")
    if details:
        for line in details.split("\n"):
            print(f"      {line}")


def check_configuration() -> bool:
    """Check that configuration is valid."""
    print_header("Configuration Check")
    all_passed = True

    # Check .env file exists
    env_path = Path(__file__).parent / ".env"
    if env_path.exists():
        print_check(".env file exists", True)
    else:
        print_check(".env file exists", False, "Create .env from .env.example")
        all_passed = False

    # Check API key
    from config.settings import ANTHROPIC_API_KEY
    if ANTHROPIC_API_KEY:
        masked_key = ANTHROPIC_API_KEY[:10] + "..." + ANTHROPIC_API_KEY[-4:]
        print_check("ANTHROPIC_API_KEY set", True, f"Key: {masked_key}")
    else:
        print_check("ANTHROPIC_API_KEY set", False,
                    "Add ANTHROPIC_API_KEY=sk-ant-... to .env")
        all_passed = False

    # Check database
    from config.settings import SQLITE_DB_FILE, AGNO_DB_FILE, DATA_DIR
    db_path = Path(SQLITE_DB_FILE)
    if db_path.exists() and db_path.stat().st_size > 0:
        print_check("Main database exists", True, f"Path: {SQLITE_DB_FILE}")
    else:
        print_check("Main database exists", False,
                    f"Run: python -m db.init_db\nExpected: {SQLITE_DB_FILE}")
        all_passed = False

    # Check data directory is writable
    try:
        test_file = Path(DATA_DIR) / ".health_check_test"
        test_file.touch()
        test_file.unlink()
        print_check("Data directory writable", True, f"Path: {DATA_DIR}")
    except Exception as e:
        print_check("Data directory writable", False, f"Error: {e}")
        all_passed = False

    return all_passed


def check_dependencies() -> bool:
    """Check that required packages are installed."""
    print_header("Dependencies Check")
    all_passed = True

    required_packages = [
        ("agno", "Agno framework"),
        ("anthropic", "Anthropic API client"),
        ("lancedb", "Vector database for questions"),
        ("sentence_transformers", "Embedding model"),
        ("sqlalchemy", "Database ORM"),
        ("dotenv", "Environment variable loading"),
    ]

    for package, description in required_packages:
        try:
            __import__(package)
            print_check(f"{package} ({description})", True)
        except ImportError as e:
            print_check(f"{package} ({description})", False, str(e))
            all_passed = False

    return all_passed


def check_agents() -> bool:
    """Check that each agent can be initialized."""
    print_header("Agent Initialization Check")
    all_passed = True

    # Initialize logging first
    from config.logging_config import setup_logging
    setup_logging()

    # Check Talk Agent
    try:
        from agents.talk_agent import create_talk_agent
        agent = create_talk_agent(session_id="health-check", user_id="health-check")
        print_check("Talk Agent (Cyrano)", True, f"Model: {agent.model.id}")
    except Exception as e:
        print_check("Talk Agent (Cyrano)", False, str(e))
        all_passed = False

    # Check Extract Agent
    try:
        from agents.extract_agent import create_extract_agent
        agent = create_extract_agent(session_id="health-check")
        print_check("Extract Agent", True, f"Model: {agent.model.id}")
    except Exception as e:
        print_check("Extract Agent", False, str(e))
        all_passed = False

    # Check Data Agent
    try:
        from agents.data_agent import create_data_agent
        agent = create_data_agent(session_id="health-check")
        print_check("Data Agent", True, f"Model: {agent.model.id}")
    except Exception as e:
        print_check("Data Agent", False, str(e))
        all_passed = False

    # Check Mood Agent
    try:
        from agents.mood_agent import create_mood_agent
        agent = create_mood_agent(user_id="health-check", talk_session_id="health-check")
        print_check("Mood Agent", True, f"Model: {agent.model.id}")
    except Exception as e:
        print_check("Mood Agent", False, str(e))
        all_passed = False

    return all_passed


def check_api_connectivity(run_test: bool = False) -> bool:
    """Test that we can actually call the Anthropic API."""
    print_header("API Connectivity Check")

    if not run_test:
        print("  (Skipped - use --test-api to run)")
        return True

    try:
        from anthropic import Anthropic
        from config.settings import ANTHROPIC_API_KEY

        client = Anthropic(api_key=ANTHROPIC_API_KEY)
        response = client.messages.create(
            model="claude-sonnet-4-5-20250929",
            max_tokens=10,
            messages=[{"role": "user", "content": "Say 'OK' and nothing else."}]
        )
        result = response.content[0].text.strip()
        print_check("Anthropic API call", True, f"Response: {result}")
        return True
    except Exception as e:
        print_check("Anthropic API call", False, str(e))
        return False


def check_extraction_pipeline(run_test: bool = False) -> bool:
    """Test the full extraction pipeline."""
    print_header("Extraction Pipeline Check")

    if not run_test:
        print("  (Skipped - use --test-extraction to run)")
        return True

    try:
        from agents.extract_agent import run_extraction

        # Run extraction with a simple test message
        test_history = [
            {"role": "user", "content": "I planted maize in my north field last week."}
        ]
        fact_ids = run_extraction("health-check-session", test_history)
        print_check("Extraction pipeline", True, f"Extracted {len(fact_ids)} facts")
        return True
    except Exception as e:
        print_check("Extraction pipeline", False, str(e))
        return False


def main():
    """Run all health checks."""
    print("\n" + "="*60)
    print("  Cyrano Agent System - Health Check")
    print("="*60)

    # Parse arguments
    test_api = "--test-api" in sys.argv
    test_extraction = "--test-extraction" in sys.argv

    results = []

    # Run checks
    results.append(("Configuration", check_configuration()))
    results.append(("Dependencies", check_dependencies()))
    results.append(("Agent Initialization", check_agents()))
    results.append(("API Connectivity", check_api_connectivity(test_api)))
    results.append(("Extraction Pipeline", check_extraction_pipeline(test_extraction)))

    # Summary
    print_header("Summary")
    all_passed = True
    for name, passed in results:
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"  {status}: {name}")
        if not passed:
            all_passed = False

    print()
    if all_passed:
        print("All checks passed! System is ready.")
    else:
        print("Some checks failed. Review the output above for details.")
        print("\nCommon fixes:")
        print("  - Missing API key: Add ANTHROPIC_API_KEY to .env")
        print("  - Missing database: Run python -m db.init_db")
        print("  - Missing packages: Run pip install -r requirements.txt")

    print("\nAdditional options:")
    print("  --test-api         Run a live API call test")
    print("  --test-extraction  Run the full extraction pipeline")

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())

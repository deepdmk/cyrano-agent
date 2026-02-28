"""
Test script that simulates a farmer conversation.

Feeds pre-written messages through the orchestrator to test the full pipeline.

Run with: python -m scripts.test_conversation
"""
import time
import uuid

from agents.orchestrator import Orchestrator
from tools.main_db_tools import get_facts_by_session
from tools.form_db_tools import get_database_summary
from tools.questions_tools import get_session_questions


# Test conversation messages covering various domains
TEST_MESSAGES = [
    # Greeting and small talk
    "Hello, good morning!",

    # Crop information
    "I planted maize in my north field last month. About two hectares of it.",

    # Field details
    "The north field is near the river, has good black soil. I use canal irrigation there.",

    # Weather observation
    "We had heavy rain last week. Some of the lower areas got flooded for a day.",

    # Input information
    "I applied fertilizer yesterday. Used two bags of NPK on the north field.",

    # Scheduling
    "I have a delivery of seeds coming next Tuesday. The supplier said morning.",

    # Planning
    "Next season I want to try growing beans in the south field. Maybe expand to three hectares.",

    # More crop details
    "The maize is looking good so far. I got the seeds from the cooperative.",

    # Emotional signal (for mood agent testing)
    "I'm getting tired of all this record keeping though. It's a lot of work.",

    # Follow up
    "The south field is smaller, maybe one hectare. Sandy soil, not as good.",
]


def run_test_conversation():
    """Run a simulated conversation and report results."""
    print("\n" + "="*60)
    print("  Test Conversation Simulation")
    print("="*60 + "\n")

    # Create orchestrator with test IDs
    user_id = f"test_farmer_{int(time.time())}"
    session_id = str(uuid.uuid4())

    orchestrator = Orchestrator(user_id=user_id, session_id=session_id)
    orchestrator.start_session()

    print(f"Session ID: {session_id}")
    print(f"User ID: {user_id}")
    print(f"Test messages: {len(TEST_MESSAGES)}")
    print("-" * 60 + "\n")

    # Run through test messages
    for i, message in enumerate(TEST_MESSAGES, 1):
        print(f"[Turn {i}]")
        print(f"Farmer: {message}")

        response = orchestrator.process_message(message)
        print(f"Assistant: {response[:200]}..." if len(response) > 200 else f"Assistant: {response}")
        print()

        # Small delay to allow background processing
        time.sleep(1)

    # Wait for all background tasks
    print("\nWaiting for background processing to complete...")
    orchestrator.wait_for_background_tasks(timeout=60)
    time.sleep(2)  # Extra time for any final processing

    # Report results
    print("\n" + "="*60)
    print("  Test Results")
    print("="*60 + "\n")

    # Facts extracted
    facts = get_facts_by_session(session_id)
    print(f"Extracted Facts: {len(facts)}")
    for fact in facts:
        print(f"  - [{fact['confidence']}] {fact['domain']}: {fact['raw_text'][:60]}...")

    print()

    # Database summary
    summary = get_database_summary()
    print("Form Database Records:")
    for table, info in summary.items():
        count = info.get('count', 0)
        if count > 0:
            print(f"  - {table}: {count} records")

    print()

    # Questions generated
    questions = get_session_questions(session_id)
    print(f"Questions Generated: {len(questions)}")
    for q in questions[:5]:  # Show first 5
        print(f"  - [{q['priority']}] {q['question_text']}")

    print()

    # Conversation summary
    conv_summary = orchestrator.get_conversation_summary()
    print("Conversation Summary:")
    print(f"  - Turns: {conv_summary['turn_count']}")
    print(f"  - Messages: {conv_summary['message_count']}")
    print(f"  - Mood instruction: {conv_summary['mood_instruction'] or 'None'}")

    orchestrator.shutdown()
    print("\nTest completed.")

    return {
        "session_id": session_id,
        "facts_extracted": len(facts),
        "questions_generated": len(questions),
        "database_summary": summary
    }


if __name__ == "__main__":
    results = run_test_conversation()
    print(f"\n\nFinal Results: {results}")

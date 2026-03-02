"""
Data Agent - Routes extracted facts to Form Databases and generates questions.

Part 1: Takes extracted facts from Main DB and routes them to the appropriate
Form Database tables (Agricultural, Scheduling, Planning).

Part 2: Analyzes Form Databases for gaps and generates natural-language questions
for the Talk Agent to weave into conversation.
"""
import sys
from typing import Optional

from agno.agent import Agent
from agno.models.anthropic import Claude
from agno.tools.decorator import tool

from agno.db.sqlite import SqliteDb

from config.settings import DEFAULT_MODEL_ID, AGNO_DB_FILE
from config.logging_config import get_logger
from tools.main_db_tools import get_unrouted_facts, mark_fact_routed

logger = get_logger("data_agent")
from tools.form_db_tools import (
    # Fields
    create_field, update_field, get_all_fields, get_field, get_field_by_name,
    # Crops
    create_crop, update_crop, get_all_crops, get_crop, get_crops_by_field,
    # Inputs
    create_input, update_input, get_all_inputs, get_input,
    # Yields
    create_yield, update_yield, get_all_yields, get_yield,
    # Weather
    create_weather_observation, update_weather_observation, get_all_weather_observations,
    # Events
    create_event, update_event, get_all_events, get_event,
    # Plans
    create_plan, update_plan, get_all_plans, get_plan,
    # Summary
    get_database_summary
)
from tools.questions_tools import (
    write_question, clear_session_questions, generate_embedding, get_question_count
)


# System instructions for the Data Agent
DATA_AGENT_INSTRUCTIONS = """You are a data routing and gap analysis specialist.

Your job has TWO parts:

## PART 1: Route Extracted Facts to Form Databases

1. Call get_unrouted_facts to get new extractions from the Main DB
2. For each fact, determine which Form Database table(s) it belongs in:
   - FIELDS: Information about plots/fields (name, size, location, soil, irrigation)
   - CROPS: Crops planted in fields (type, variety, planting date, harvest date, status)
   - INPUTS: Fertilizer, pesticide, herbicide applications
   - YIELDS: Harvest quantities, quality, sales
   - WEATHER_OBSERVATIONS: Weather events and their impacts
   - EVENTS: Scheduled meetings, deliveries, market days (Scheduling DB)
   - PLANS: Future intentions and plans (Planning DB)

3. Before creating a new record, CHECK if a record already exists:
   - Use get_field_by_name to check if a field exists before creating
   - Use get_all_crops, get_all_events, etc. to check for duplicates
   - UPDATE existing records rather than creating duplicates

4. After processing each fact, call mark_fact_routed to mark it done

## PART 2: Identify Gaps and Generate Questions

1. Call get_database_summary to see the current state of all Form Databases
2. Look for records with NULL values in important fields
3. Look for logical gaps:
   - A crop with no planting date
   - A field with no size
   - A plan with no timeline
   - An event with no date

4. For each gap, call write_question with:
   - question_text: A natural, conversational question (like a friend would ask)
     GOOD: "How large is the north field, roughly?"
     BAD: "Field size is NULL for record xyz"
   - source_database, source_table, source_field: Where the gap is
   - source_record_id: Which record (if applicable)
   - priority: "high" for critical data, "medium" for useful, "low" for nice-to-have
   - embedding: Generate using generate_embedding tool

IMPORTANT:
- Questions should sound like things a friend would ask, not form demands
- Be conversational and natural
- Prioritize important gaps over minor ones
- Don't generate more than 10-15 questions per run
"""


def create_data_agent(session_id: str) -> Agent:
    """
    Create a Data Agent instance.

    Args:
        session_id: The session ID for question generation

    Returns:
        Configured Data Agent
    """
    # Wrap tools that need session_id
    @tool
    def add_question(
        question_text: str,
        source_database: str,
        source_table: str,
        source_field: str,
        priority: str,
        source_record_id: Optional[str] = None
    ) -> str:
        """
        Write a question to the Questions Vector DB for the Talk Agent.

        Args:
            question_text: Natural-language question that sounds conversational
            source_database: Which database the gap is in ("agricultural", "scheduling", "planning")
            source_table: Which table (e.g., "fields", "crops", "events")
            source_field: Which field is missing (e.g., "size_hectares", "planting_date")
            priority: "high" for critical, "medium" for useful, "low" for nice-to-have
            source_record_id: Optional UUID of the specific record with the gap

        Returns:
            Confirmation message
        """
        embedding = generate_embedding(question_text)
        question_id = write_question(
            session_id=session_id,
            question_text=question_text,
            source_database=source_database,
            source_table=source_table,
            source_field=source_field,
            priority=priority,
            embedding=embedding,
            source_record_id=source_record_id
        )
        return f"Question recorded with ID: {question_id}"

    # Create tool wrapper for generate_embedding
    @tool
    def create_embedding(text: str) -> list[float]:
        """
        Generate an embedding for text (used internally for question similarity).

        Args:
            text: The text to embed

        Returns:
            768-dimensional embedding vector
        """
        return generate_embedding(text)

    agent = Agent(
        name="Data Agent",
        model=Claude(id=DEFAULT_MODEL_ID),
        db=SqliteDb(
            db_file=AGNO_DB_FILE
        ),
        session_id=f"data_{session_id}",
        instructions=[DATA_AGENT_INSTRUCTIONS],
        tools=[
            # Main DB tools
            get_unrouted_facts,
            mark_fact_routed,
            # Field tools
            create_field, update_field, get_all_fields, get_field, get_field_by_name,
            # Crop tools
            create_crop, update_crop, get_all_crops, get_crop, get_crops_by_field,
            # Input tools
            create_input, update_input, get_all_inputs, get_input,
            # Yield tools
            create_yield, update_yield, get_all_yields, get_yield,
            # Weather tools
            create_weather_observation, update_weather_observation, get_all_weather_observations,
            # Event tools
            create_event, update_event, get_all_events, get_event,
            # Plan tools
            create_plan, update_plan, get_all_plans, get_plan,
            # Summary tool
            get_database_summary,
            # Question tools
            add_question,
            create_embedding,
        ],
        add_history_to_context=True,
        num_history_runs=10,
        tool_call_limit=50,  # Prevent runaway tool calls with 30+ tools
        markdown=False,
    )

    return agent


def run_data_routing(session_id: str, agent: Optional[Agent] = None) -> dict:
    """
    Run the Data Agent to route facts and generate questions.

    Args:
        session_id: The session ID for question generation
        agent: Optional pre-created agent instance to reuse (for performance)

    Returns:
        Summary dict with facts_routed and questions_generated counts
    """
    logger.debug("Running data routing for session %s", session_id)

    # Clear existing questions for this session
    clear_result = clear_session_questions(session_id)
    logger.debug("%s", clear_result)

    # Get initial counts
    initial_unrouted = len(get_unrouted_facts())

    # Use provided agent or create a new one
    if agent is None:
        agent = create_data_agent(session_id)

    routing_prompt = """Execute both parts of your job:

PART 1 - ROUTE FACTS:
1. Call get_unrouted_facts to see what needs processing
2. For each fact, route it to the appropriate Form Database table(s)
3. Check for existing records before creating new ones
4. Mark each fact as routed after processing

PART 2 - GENERATE QUESTIONS:
1. Call get_database_summary to see gaps in the data
2. For each significant gap, generate a natural conversational question
3. Prioritize important gaps (field sizes, crop types, event dates)
4. Write each question using add_question

Be thorough but efficient. Process all unrouted facts and identify the most important gaps."""

    agent.run(routing_prompt)

    # Get final counts
    final_unrouted = len(get_unrouted_facts())
    questions_count = get_question_count(session_id)

    results = {
        "facts_routed": initial_unrouted - final_unrouted,
        "facts_remaining": final_unrouted,
        "questions_generated": questions_count
    }
    logger.info("Data routing complete: %d routed, %d questions", results['facts_routed'], results['questions_generated'])
    return results


def print_routing_results(results: dict, session_id: str):
    """Print the results of a data routing run."""
    print(f"\n=== Data Routing Results ===")
    print(f"Session ID: {session_id}")
    print(f"Facts routed: {results['facts_routed']}")
    print(f"Facts remaining: {results['facts_remaining']}")
    print(f"Questions generated: {results['questions_generated']}")

    # Print database summary
    summary = get_database_summary()
    print("\nDatabase Summary:")
    for table, info in summary.items():
        print(f"  {table}: {info['count']} records")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python -m agents.data_agent <session_id>")
        sys.exit(1)

    session_id = sys.argv[1]
    print(f"Running data routing for session: {session_id}")

    results = run_data_routing(session_id)
    print_routing_results(results, session_id)

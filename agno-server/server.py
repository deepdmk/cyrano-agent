"""
AgentOS server for monitoring and API access to all agents.

Provides a web dashboard and REST API for inspecting agent runs,
sessions, traces, and outputs.

Run with: python -m server
"""
from agno.os import AgentOS
from agno.agent import Agent
from agno.models.anthropic import Claude
from agno.db.sqlite import SqliteDb

from config.settings import DEFAULT_MODEL_ID, AGNO_DB_FILE
from agents.talk_agent import CYRANO_INSTRUCTIONS
from agents.extract_agent import EXTRACT_AGENT_INSTRUCTIONS
from agents.data_agent import DATA_AGENT_INSTRUCTIONS
from agents.mood_agent import MOOD_AGENT_INSTRUCTIONS, MoodAssessment

# Import tools so agents can be fully configured
from tools.questions_tools import generate_embedding, search_questions
from tools.main_db_tools import (
    write_extracted_fact, get_unrouted_facts, mark_fact_routed,
    get_facts_by_session, get_recent_fact_for_user
)
from tools.form_db_tools import (
    create_field, update_field, get_all_fields, get_field, get_field_by_name,
    create_crop, update_crop, get_all_crops, get_crop, get_crops_by_field,
    create_input, update_input, get_all_inputs, get_input,
    create_yield, update_yield, get_all_yields, get_yield,
    create_weather_observation, update_weather_observation, get_all_weather_observations,
    create_event, update_event, get_all_events, get_event,
    create_plan, update_plan, get_all_plans, get_plan,
    get_database_summary
)
from tools.questions_tools import (
    write_question, clear_session_questions, generate_embedding, get_question_count
)
from agno.tools.decorator import tool


# Shared database for session persistence
db = SqliteDb(db_file=AGNO_DB_FILE)


# ============================================================
# Agent Definitions for AgentOS
# ============================================================

# Note: These are "registration" instances for AgentOS visibility.
# The orchestrator creates its own working instances separately.
# These let AgentOS track runs and provide the monitoring dashboard.

# --- Cyrano (Talk Agent) ---

@tool
def find_relevant_questions(conversation_summary: str) -> str:
    """
    Search for questions that fit naturally into the current conversation.

    Args:
        conversation_summary: Brief summary of recent conversation context

    Returns:
        Relevant questions or a message that none are available
    """
    embedding = generate_embedding(conversation_summary)
    questions = search_questions(
        query_embedding=embedding,
        session_id="server",  # Placeholder for server-mode runs
        limit=3
    )
    if not questions:
        return "No relevant questions at this time."
    result = "Questions that might fit the conversation:\n\n"
    for q in questions:
        result += f"- {q['question_text']} (about: {q['source_table']}.{q['source_field']}, priority: {q['priority']})\n"
    return result


cyrano_agent = Agent(
    name="Cyrano",
    model=Claude(id=DEFAULT_MODEL_ID),
    db=db,
    instructions=[CYRANO_INSTRUCTIONS],
    tools=[find_relevant_questions],
    add_history_to_context=True,
    num_history_runs=10,
    add_datetime_to_context=True,
    markdown=False,
)


# --- Extract Agent ---

@tool
def extract_fact(
    raw_text: str,
    extracted_fact: dict,
    domain: list[str],
    confidence: str
) -> str:
    """
    Write an extracted fact to the Main DB.

    Args:
        raw_text: The farmer's actual words
        extracted_fact: Structured JSON object with relevant fields
        domain: List of: "agricultural", "scheduling", "planning"
        confidence: "high", "medium", or "low"

    Returns:
        Confirmation with created fact ID
    """
    fact_id = write_extracted_fact(
        session_id="server",
        raw_text=raw_text,
        extracted_fact=extracted_fact,
        domain=domain,
        confidence=confidence
    )
    return f"Fact recorded with ID: {fact_id}"


extract_agent = Agent(
    name="Extract Agent",
    model=Claude(id=DEFAULT_MODEL_ID),
    db=db,
    instructions=[EXTRACT_AGENT_INSTRUCTIONS],
    tools=[extract_fact],
    add_history_to_context=True,
    num_history_runs=20,
    markdown=False,
)


# --- Data Agent ---

@tool
def add_question(
    question_text: str,
    source_database: str,
    source_table: str,
    source_field: str,
    priority: str,
    source_record_id: str = None
) -> str:
    """
    Write a question to the Questions Vector DB.

    Args:
        question_text: Natural-language conversational question
        source_database: "agricultural", "scheduling", or "planning"
        source_table: Table name (e.g., "fields", "crops")
        source_field: Field name that is missing
        priority: "high", "medium", or "low"
        source_record_id: Optional UUID of the record with the gap

    Returns:
        Confirmation message
    """
    embedding = generate_embedding(question_text)
    question_id = write_question(
        session_id="server",
        question_text=question_text,
        source_database=source_database,
        source_table=source_table,
        source_field=source_field,
        priority=priority,
        embedding=embedding,
        source_record_id=source_record_id
    )
    return f"Question recorded with ID: {question_id}"


@tool
def create_embedding(text: str) -> list[float]:
    """Generate an embedding vector for text."""
    return generate_embedding(text)


data_agent = Agent(
    name="Data Agent",
    model=Claude(id=DEFAULT_MODEL_ID),
    db=db,
    instructions=[DATA_AGENT_INSTRUCTIONS],
    tools=[
        get_unrouted_facts, mark_fact_routed,
        create_field, update_field, get_all_fields, get_field, get_field_by_name,
        create_crop, update_crop, get_all_crops, get_crop, get_crops_by_field,
        create_input, update_input, get_all_inputs, get_input,
        create_yield, update_yield, get_all_yields, get_yield,
        create_weather_observation, update_weather_observation, get_all_weather_observations,
        create_event, update_event, get_all_events, get_event,
        create_plan, update_plan, get_all_plans, get_plan,
        get_database_summary,
        add_question, create_embedding,
    ],
    markdown=False,
)


# --- Mood Agent ---

mood_agent = Agent(
    name="Mood Agent",
    model=Claude(id=DEFAULT_MODEL_ID),
    db=db,
    instructions=[MOOD_AGENT_INSTRUCTIONS],
    output_schema=MoodAssessment,
    add_history_to_context=True,
    num_history_runs=5,
    markdown=False,
)


# ============================================================
# AgentOS Setup
# ============================================================

agent_os = AgentOS(
    id="cyrano-os",
    name="Cyrano Agent System",
    description="Conversational data capture for smallholder farmers. "
                "Four Claude agents: Cyrano (conversation), Extract (fact extraction), "
                "Data (routing and gap analysis), Mood (engagement monitoring).",
    agents=[cyrano_agent, extract_agent, data_agent, mood_agent],
    db=db,
    tracing=True,          # Enable execution traces
    auto_provision_dbs=True,
)

app = agent_os.get_app()


if __name__ == "__main__":
    agent_os.serve(
        app="server:app",
        host="0.0.0.0",
        port=7777,
        reload=True,
    )

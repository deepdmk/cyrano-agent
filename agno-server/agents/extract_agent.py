"""
Extract Agent - Extracts structured facts from farmer conversations.

Reads conversation history from a session and extracts agricultural information,
scheduling details, and planning intentions into the Main DB.
"""
import sys
from typing import Optional

from agno.agent import Agent
from agno.models.anthropic import Claude
from agno.db.sqlite import SqliteDb
from agno.tools.decorator import tool

from config.settings import EXTRACT_AGENT_MODEL_ID, AGNO_DB_FILE
from config.logging_config import get_logger
from tools.main_db_tools import write_extracted_fact, get_facts_by_session

logger = get_logger("extract_agent")


# System instructions for the Extract Agent
EXTRACT_AGENT_INSTRUCTIONS = """You are a data extraction specialist. You read conversations between a farmer and an AI assistant.

Your job is to identify any factual agricultural information in the conversation and record it as structured data.

You are looking for information relevant to three downstream databases:

1. AGRICULTURAL DATA:
   - Fields/plots (names, sizes, locations, soil types, irrigation)
   - Crops (types, varieties, planting dates, harvest dates, status)
   - Inputs (fertilizer, pesticide, herbicide applications)
   - Yields (harvest quantities, quality, sales)
   - Weather observations (rain, drought, frost, floods, impacts)

2. SCHEDULING:
   - Meetings and appointments
   - Deliveries (supplies arriving, products shipping)
   - Market days
   - Equipment bookings
   - Labor arrangements
   - Veterinary visits
   - Any calendar events

3. PLANNING:
   - Future planting intentions
   - Expansion plans
   - Investment intentions
   - Crop rotation plans
   - New techniques to try
   - Resource needs
   - Budget intentions
   - Timelines

For each piece of information you extract, call the write_extracted_fact tool with:
- raw_text: The farmer's actual words (quote or close paraphrase)
- extracted_fact: A structured JSON object with relevant fields
- domain: Which database(s) this relates to (list of: "agricultural", "scheduling", "planning")
- confidence: "high" if stated clearly, "medium" if somewhat ambiguous, "low" if inferred

CRITICAL RULES:
- Extract ONLY what the farmer actually said or clearly implied
- Do NOT invent or assume information
- If you've already extracted something in a previous run, do NOT duplicate it
- Process the ENTIRE conversation and extract EVERYTHING relevant
- Each distinct piece of information should be a separate extraction
"""


def create_extract_agent(session_id: str) -> Agent:
    """
    Create an Extract Agent instance for a conversation session.

    The Extract Agent shares the same session_id as the Talk Agent so it can
    read the conversation history.

    Args:
        session_id: The session ID of the conversation to extract from

    Returns:
        Configured Extract Agent
    """
    # Create tool that wraps write_extracted_fact with the session_id
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
            raw_text: The farmer's actual words that this fact was derived from
            extracted_fact: Structured JSON object with relevant fields like:
                {"crop_type": "maize", "action": "planted", "field": "north field", "date": "last week"}
            domain: Which database(s) this relates to. Must be a list containing
                one or more of: "agricultural", "scheduling", "planning"
            confidence: How clearly the farmer stated this: "high", "medium", or "low"

        Returns:
            Confirmation with the created fact ID
        """
        fact_id = write_extracted_fact(
            session_id=session_id,
            raw_text=raw_text,
            extracted_fact=extracted_fact,
            domain=domain,
            confidence=confidence
        )
        return f"Fact recorded with ID: {fact_id}"

    agent = Agent(
        name="Extract Agent",
        model=Claude(id=EXTRACT_AGENT_MODEL_ID),
        db=SqliteDb(
            db_file=AGNO_DB_FILE
        ),
        session_id=f"extract_{session_id}",  # Own session (conversation passed via prompt)
        instructions=[EXTRACT_AGENT_INSTRUCTIONS],
        tools=[extract_fact],
        add_history_to_context=True,
        num_history_runs=20,
        markdown=False,
    )

    return agent


def run_extraction(
    session_id: str,
    conversation_history: list[dict] | None = None,
    agent: Optional[Agent] = None
) -> list[str]:
    """
    Run extraction on a conversation session.

    Args:
        session_id: The session ID to extract from
        conversation_history: List of {"role": "user"|"assistant", "content": str} dicts
            from the orchestrator. If provided, the conversation is included directly
            in the prompt (required since Agno scopes history per agent).
        agent: Optional pre-created agent instance to reuse (for performance)

    Returns:
        List of fact IDs that were created
    """
    logger.info("Extract Agent STARTING for session %s (history: %d messages)",
                session_id, len(conversation_history) if conversation_history else 0)

    # Get facts that existed before this run
    existing_facts = get_facts_by_session(session_id)
    existing_ids = {f["id"] for f in existing_facts}

    # Use provided agent or create a new one
    if agent is None:
        agent = create_extract_agent(session_id)

    # Build the conversation transcript for the prompt
    conversation_block = ""
    if conversation_history:
        conversation_block = "Here is the conversation between the farmer and Cyrano:\n\n"
        for msg in conversation_history:
            speaker = "Farmer" if msg["role"] == "user" else "Cyrano"
            conversation_block += f"{speaker}: {msg['content']}\n\n"
        conversation_block += "---\n\n"

    extraction_prompt = f"""{conversation_block}Review the conversation above and extract all agricultural information.

For each piece of information found, use the extract_fact tool to record it.

Look for:
- Field/plot information (names, sizes, locations)
- Crop information (what was planted, when, where)
- Input applications (fertilizer, pesticides)
- Yield/harvest information
- Weather observations and their impacts
- Scheduled events (meetings, deliveries, market days)
- Future plans and intentions

Extract each distinct piece of information separately. Be thorough but do not duplicate information that has already been extracted."""

    try:
        logger.debug("Extract Agent: calling Claude API...")
        agent.run(extraction_prompt)
        logger.debug("Extract Agent: Claude API call completed")

        # Get facts after this run
        new_facts = get_facts_by_session(session_id)
        new_ids = [f["id"] for f in new_facts if f["id"] not in existing_ids]

        logger.info("Extract Agent COMPLETED for session %s: %d facts extracted",
                    session_id, len(new_ids))
        return new_ids
    except Exception as e:
        logger.error("Extract Agent FAILED for session %s: %s", session_id, e, exc_info=True)
        raise


def print_extraction_results(session_id: str, fact_ids: list[str]):
    """Print the results of an extraction run."""
    facts = get_facts_by_session(session_id)

    print(f"\n=== Extraction Results for Session {session_id} ===")
    print(f"New facts extracted: {len(fact_ids)}")
    print(f"Total facts in session: {len(facts)}")

    if fact_ids:
        print("\nNewly extracted facts:")
        for fact in facts:
            if fact["id"] in fact_ids:
                print(f"\n  ID: {fact['id']}")
                print(f"  Raw text: {fact['raw_text'][:100]}...")
                print(f"  Domain: {fact['domain']}")
                print(f"  Confidence: {fact['confidence']}")
                print(f"  Data: {fact['extracted_fact']}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python -m agents.extract_agent <session_id>")
        sys.exit(1)

    session_id = sys.argv[1]
    print(f"Running extraction for session: {session_id}")

    fact_ids = run_extraction(session_id)
    print_extraction_results(session_id, fact_ids)

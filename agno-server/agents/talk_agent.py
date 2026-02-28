"""
Talk Agent - Front-of-house conversational agent for farmers.

Holds natural, fluid conversations with farmers, periodically weaving in
questions from the Questions Vector DB to gather missing information.
"""
import sys
import uuid
from typing import Optional

from agno.agent import Agent
from agno.models.anthropic import Claude
from agno.db.postgres import PostgresDb
from agno.tools.decorator import tool

from config.settings import DEFAULT_MODEL_ID, AGNO_DATABASE_URL
from tools.questions_tools import generate_embedding, search_questions


# System instructions for the Talk Agent
TALK_AGENT_INSTRUCTIONS = """You are having a natural conversation with a smallholder farmer.

Your core behaviors:
- Be warm, patient, and genuinely interested in their work and life
- Never interrogate. Never ask rapid-fire questions
- Follow the farmer's lead. If they want to talk about weather, talk about weather
- Keep responses conversational, short to medium length, not formal
- If the farmer seems done talking, let them go. Do not push for more information

About gathering information:
- You have access to a tool that searches for questions the system needs answers to
- Use this tool periodically (roughly every 3-4 exchanges), NOT on every turn
- When you find a relevant question, weave it into the conversation naturally
- Never say "the system needs to know" or "I have a question from the database"
- Just ask questions as part of normal, friendly dialogue
- If the conversation is flowing well on a topic, do not interrupt with unrelated questions
- Wait for natural pauses or transitions before introducing new topics

Remember: You are a helpful friend who happens to be interested in farming. The farmer should enjoy talking to you.
"""


def create_talk_agent(
    session_id: str,
    user_id: str,
    mood_instruction: Optional[str] = None
) -> Agent:
    """
    Create a Talk Agent instance for a conversation session.

    Args:
        session_id: Unique identifier for this conversation session
        user_id: Identifier for the farmer (persistent across sessions)
        mood_instruction: Optional instruction from the Mood Agent to adjust behavior

    Returns:
        Configured Talk Agent
    """
    # Build instructions with optional mood injection
    instructions = [TALK_AGENT_INSTRUCTIONS]
    if mood_instruction:
        instructions.append(f"\n[Current guidance: {mood_instruction}]")

    # Create the custom tool for searching questions
    @tool
    def find_relevant_questions(conversation_summary: str) -> str:
        """
        Search for questions that would fit naturally into the current conversation.

        Call this tool every few turns to check if there are relevant questions
        to weave into the conversation. Do not call it on every turn.

        Args:
            conversation_summary: A brief summary of the recent conversation context
                (what topics have been discussed, what the farmer seems interested in)

        Returns:
            A list of relevant questions that could be asked naturally, or
            "No relevant questions at this time" if none are suitable
        """
        embedding = generate_embedding(conversation_summary)
        questions = search_questions(
            query_embedding=embedding,
            session_id=session_id,
            limit=3
        )

        if not questions:
            return "No relevant questions at this time. Continue the natural conversation."

        # Format questions for the agent
        result = "Here are some questions that might fit naturally into the conversation:\n\n"
        for q in questions:
            result += f"- {q['question_text']} (about: {q['source_table']}.{q['source_field']}, priority: {q['priority']})\n"
        result += "\nChoose one that fits the current topic, or skip if none fit naturally."
        return result

    # Create the agent
    agent = Agent(
        name="Talk Agent",
        model=Claude(id=DEFAULT_MODEL_ID),
        db=PostgresDb(
            db_url=AGNO_DATABASE_URL
        ),
        session_id=session_id,
        user_id=user_id,
        instructions=instructions,
        tools=[find_relevant_questions],
        add_history_to_context=True,
        num_history_runs=10,
        add_datetime_to_context=True,
        markdown=False,  # Keep responses plain for farmer interface
    )

    return agent


def run_interactive_session(user_id: str = "test_farmer", session_id: Optional[str] = None):
    """
    Run an interactive terminal session with the Talk Agent.

    Args:
        user_id: Identifier for the farmer
        session_id: Optional session ID (generates new one if not provided)
    """
    session_id = session_id or str(uuid.uuid4())
    print(f"\n=== Talk Agent Interactive Session ===")
    print(f"Session ID: {session_id}")
    print(f"User ID: {user_id}")
    print("Type 'quit' or 'exit' to end the conversation.\n")

    agent = create_talk_agent(session_id=session_id, user_id=user_id)

    # Initial greeting
    agent.print_response(
        "Hello! The farmer just arrived for a conversation. Greet them warmly.",
        stream=True
    )
    print()

    while True:
        try:
            user_input = input("Farmer: ").strip()
            if not user_input:
                continue
            if user_input.lower() in ("quit", "exit"):
                print("\nEnding conversation. Goodbye!")
                break

            print("\nAssistant: ", end="")
            agent.print_response(user_input, stream=True)
            print("\n")

        except KeyboardInterrupt:
            print("\n\nConversation interrupted. Goodbye!")
            break
        except Exception as e:
            print(f"\nError: {e}")
            continue


if __name__ == "__main__":
    # Parse command line arguments
    user_id = sys.argv[1] if len(sys.argv) > 1 else "test_farmer"
    session_id = sys.argv[2] if len(sys.argv) > 2 else None

    run_interactive_session(user_id=user_id, session_id=session_id)

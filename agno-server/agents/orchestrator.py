"""
Orchestrator - Ties all agents together into the main conversation loop.

Implements the system flow:
1. Accept user input
2. Inject any Mood Agent instruction (prepended to user message per DD-01)
3. Run Cyrano (Talk Agent)
4. Return response to user
5. Fire async background tasks (Extract -> Data -> Mood)
6. Store mood instruction for next turn
"""
import asyncio
import uuid
from dataclasses import dataclass, field
from typing import Iterator, Optional
from concurrent.futures import ThreadPoolExecutor

from agents.talk_agent import create_talk_agent
from agents.extract_agent import run_extraction
from agents.data_agent import run_data_routing
from agents.mood_agent import assess_mood, MoodAssessment
from tools.questions_tools import clear_session_questions


@dataclass
class ConversationState:
    """State maintained across a conversation session."""
    session_id: str
    user_id: str
    mood_instruction: Optional[str] = None
    turn_count: int = 0
    conversation_history: list[dict] = field(default_factory=list)
    background_tasks: list = field(default_factory=list)


class Orchestrator:
    """
    Main orchestrator that coordinates all agents.

    The orchestrator manages:
    - Session lifecycle
    - Cyrano (Talk Agent) interactions
    - Background processing (Extract, Data, Mood agents)
    - Mood instruction injection (prepended to user message per DD-01)
    """

    def __init__(self, user_id: str, session_id: Optional[str] = None):
        """
        Initialize the orchestrator for a conversation.

        Args:
            user_id: Identifier for the farmer (persistent across sessions)
            session_id: Optional session ID (generates new one if not provided)
        """
        self.state = ConversationState(
            session_id=session_id or str(uuid.uuid4()),
            user_id=user_id
        )
        self._executor = ThreadPoolExecutor(max_workers=3)
        self._talk_agent = None

    @property
    def session_id(self) -> str:
        return self.state.session_id

    @property
    def user_id(self) -> str:
        return self.state.user_id

    def start_session(self):
        """
        Initialize a new conversation session.

        Clears the Questions Vector DB and creates the Cyrano agent instance.
        The agent is created once and reused throughout the session.
        """
        # Clear questions from previous session
        clear_session_questions(self.state.session_id)

        # Create Cyrano agent once for the session
        self._talk_agent = create_talk_agent(
            session_id=self.state.session_id,
            user_id=self.state.user_id
        )

        print(f"Session started: {self.state.session_id}")

    def _get_talk_agent(self):
        """Get the Cyrano agent instance."""
        if self._talk_agent is None:
            self._talk_agent = create_talk_agent(
                session_id=self.state.session_id,
                user_id=self.state.user_id
            )
        return self._talk_agent

    def process_message(self, user_message: str) -> str:
        """
        Process a user message and return Cyrano's response.

        This is the main conversation turn method. It:
        1. Prepends any mood instruction to the user message (DD-01)
        2. Runs Cyrano with the message
        3. Schedules background processing
        4. Returns the response

        Args:
            user_message: The farmer's message

        Returns:
            Cyrano's response
        """
        self.state.turn_count += 1

        # Record user message in history (without mood instruction)
        self.state.conversation_history.append({
            "role": "user",
            "content": user_message
        })

        # DD-01: Prepend mood instruction to user message if present
        message_to_send = user_message
        if self.state.mood_instruction:
            message_to_send = f"[System guidance: {self.state.mood_instruction}]\n\n{user_message}"

        # Get Cyrano agent
        agent = self._get_talk_agent()

        # Run Cyrano
        response = agent.run(message_to_send)
        response_text = response.content

        # Record assistant response in history
        self.state.conversation_history.append({
            "role": "assistant",
            "content": response_text
        })

        # Schedule background processing (non-blocking)
        self._schedule_background_processing()

        return response_text

    def process_message_stream(self, user_message: str) -> Iterator[str]:
        """
        Process a user message and yield response content deltas.

        Same as process_message but yields content chunks as they arrive
        from the underlying model, enabling SSE streaming to the client.
        """
        self.state.turn_count += 1

        # Record user message in history (without mood instruction)
        self.state.conversation_history.append({
            "role": "user",
            "content": user_message
        })

        # DD-01: Prepend mood instruction to user message if present
        message_to_send = user_message
        if self.state.mood_instruction:
            message_to_send = f"[System guidance: {self.state.mood_instruction}]\n\n{user_message}"

        agent = self._get_talk_agent()

        # Stream response using Agno's streaming mode
        full_response = ""
        for event in agent.run(message_to_send, stream=True):
            if event.event == "RunContent" and event.content:
                chunk = str(event.content)
                full_response += chunk
                yield chunk

        # Record full response in history
        self.state.conversation_history.append({
            "role": "assistant",
            "content": full_response
        })

        # Schedule background processing (non-blocking)
        self._schedule_background_processing()

    def _schedule_background_processing(self):
        """Schedule background agents to run after the conversation turn."""
        # Use thread pool to run background tasks without blocking
        future = self._executor.submit(self._run_background_pipeline)
        self.state.background_tasks.append(future)

    def _run_background_pipeline(self):
        """
        Run the background processing pipeline.

        Order matters:
        1. Extract Agent - extracts facts from conversation
        2. Data Agent - routes facts and generates questions
        3. Mood Agent - assesses emotional state
        """
        try:
            # 1. Run Extract Agent
            fact_ids = run_extraction(self.state.session_id)
            if fact_ids:
                print(f"  [Background] Extracted {len(fact_ids)} facts")

            # 2. Run Data Agent
            routing_results = run_data_routing(self.state.session_id)
            if routing_results["facts_routed"] > 0 or routing_results["questions_generated"] > 0:
                print(f"  [Background] Routed {routing_results['facts_routed']} facts, "
                      f"generated {routing_results['questions_generated']} questions")

            # 3. Run Mood Agent (every few turns to save API calls)
            if self.state.turn_count % 2 == 0:  # Every 2 turns
                self._run_mood_assessment()

        except Exception as e:
            print(f"  [Background] Error in pipeline: {e}")

    def _run_mood_assessment(self):
        """Run mood assessment and update instruction for next turn."""
        # Get recent conversation for mood analysis
        recent_turns = self.state.conversation_history[-6:]  # Last 3 exchanges
        if not recent_turns:
            return

        # Format conversation for mood agent
        conversation_text = "\n".join([
            f"{'Farmer' if m['role'] == 'user' else 'Cyrano'}: {m['content']}"
            for m in recent_turns
        ])

        try:
            assessment = assess_mood(
                session_id=self.state.session_id,
                user_id=self.state.user_id,
                recent_conversation=conversation_text
            )

            # Update mood instruction for next turn
            if assessment.action.value != "CONTINUE":
                self.state.mood_instruction = assessment.instruction_for_talk_agent
                print(f"  [Background] Mood: {assessment.action.value} - {assessment.reasoning[:50]}...")
            else:
                self.state.mood_instruction = None

        except Exception as e:
            print(f"  [Background] Mood assessment error: {e}")

    def get_conversation_summary(self) -> dict:
        """Get a summary of the current conversation state."""
        return {
            "session_id": self.state.session_id,
            "user_id": self.state.user_id,
            "turn_count": self.state.turn_count,
            "mood_instruction": self.state.mood_instruction,
            "message_count": len(self.state.conversation_history)
        }

    def wait_for_background_tasks(self, timeout: float = 30.0):
        """Wait for all background tasks to complete."""
        for future in self.state.background_tasks:
            try:
                future.result(timeout=timeout)
            except Exception as e:
                print(f"Background task error: {e}")
        self.state.background_tasks.clear()

    def shutdown(self):
        """Clean up resources."""
        self.wait_for_background_tasks()
        self._executor.shutdown(wait=True)


def run_conversation_cli(user_id: str = "test_farmer", session_id: Optional[str] = None):
    """
    Run an interactive conversation in the terminal.

    Args:
        user_id: Identifier for the farmer
        session_id: Optional session ID
    """
    orchestrator = Orchestrator(user_id=user_id, session_id=session_id)
    orchestrator.start_session()

    print(f"\n{'='*60}")
    print("Farmer Conversational AI - Interactive Session")
    print(f"{'='*60}")
    print(f"Session ID: {orchestrator.session_id}")
    print(f"User ID: {orchestrator.user_id}")
    print("Type 'quit' or 'exit' to end the conversation.")
    print("Type 'status' to see conversation summary.")
    print(f"{'='*60}\n")

    # Initial greeting from Cyrano using opening protocol
    initial_response = orchestrator.process_message(
        "[New session started. Greet the farmer using your opening protocol.]"
    )
    print(f"Cyrano: {initial_response}\n")

    try:
        while True:
            user_input = input("Farmer: ").strip()

            if not user_input:
                continue

            if user_input.lower() in ("quit", "exit"):
                print("\nEnding conversation...")
                break

            if user_input.lower() == "status":
                summary = orchestrator.get_conversation_summary()
                print(f"\n--- Conversation Status ---")
                for key, value in summary.items():
                    print(f"  {key}: {value}")
                print("----------------------------\n")
                continue

            # Process the message
            response = orchestrator.process_message(user_input)
            print(f"\nCyrano: {response}\n")

    except KeyboardInterrupt:
        print("\n\nConversation interrupted.")
    finally:
        print("Waiting for background tasks to complete...")
        orchestrator.shutdown()
        print("Goodbye!")


if __name__ == "__main__":
    import sys
    user_id = sys.argv[1] if len(sys.argv) > 1 else "test_farmer"
    session_id = sys.argv[2] if len(sys.argv) > 2 else None
    run_conversation_cli(user_id=user_id, session_id=session_id)

"""
Mood Agent - Monitors emotional state and provides behavioral guidance.

Reads conversation context to assess the farmer's emotional state and engagement
level. Outputs structured instructions for the Talk Agent to adjust its behavior.

The Mood Agent maintains its own persistent memory to learn patterns about
specific farmers across sessions.
"""
import sys
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field

from agno.agent import Agent
from agno.models.anthropic import Claude
from agno.db.postgres import PostgresDb

from config.settings import DEFAULT_MODEL_ID, AGNO_DATABASE_URL


class MoodAction(str, Enum):
    """Actions the Mood Agent can recommend."""
    CONTINUE = "CONTINUE"
    ADJUST_TONE = "ADJUST_TONE"
    CHANGE_TOPIC = "CHANGE_TOPIC"
    WRAP_UP = "WRAP_UP"
    END_NOW = "END_NOW"


class MoodAssessment(BaseModel):
    """Structured output from the Mood Agent."""
    action: MoodAction = Field(
        description="The recommended action for the Talk Agent"
    )
    reasoning: str = Field(
        description="Brief explanation of what emotional signals were detected"
    )
    instruction_for_talk_agent: Optional[str] = Field(
        default=None,
        description="Direct instruction text to inject into the Talk Agent's context. "
                    "Should be None if action is CONTINUE."
    )
    detected_emotions: list[str] = Field(
        default_factory=list,
        description="List of emotions/states detected: fatigue, frustration, "
                    "disengagement, confusion, anger, impatience, enthusiasm, etc."
    )
    engagement_level: str = Field(
        description="Overall engagement: 'high', 'medium', 'low', 'disengaged'"
    )


# System instructions for the Mood Agent
MOOD_AGENT_INSTRUCTIONS = """You are an empathy and engagement specialist.

You read conversations between a farmer and an AI assistant. Your job is to assess
the farmer's emotional state and engagement level.

## What to Track

Monitor for these signals in the farmer's messages:
- Energy level (enthusiastic vs tired/short responses)
- Patience (detailed answers vs curt replies)
- Interest (engaged questions vs minimal acknowledgments)
- Frustration (complaints, negative language, expressions of difficulty)
- Confusion (questions about what was asked, misunderstandings)
- Fatigue (shorter responses over time, "I don't know" answers)
- Anger (hostile language, complaints about the system)
- Disengagement (off-topic responses, desire to leave)

## Actions to Recommend

Based on your assessment, output ONE of these actions:

1. CONTINUE
   - Conversation is going well, no intervention needed
   - instruction_for_talk_agent should be null

2. ADJUST_TONE
   - Farmer seems [specific emotion], Talk Agent should [specific adjustment]
   - Example: "The farmer seems tired. Keep responses shorter and don't ask complex questions."

3. CHANGE_TOPIC
   - Current topic is causing [specific issue], suggest moving to [alternative]
   - Example: "Discussion of finances is causing frustration. Steer toward crops or weather."

4. WRAP_UP
   - Farmer is showing signs of wanting to end (short responses, checking time references)
   - Example: "The farmer seems ready to go. Begin closing gracefully - summarize what was discussed and say goodbye warmly."

5. END_NOW
   - Farmer is clearly done, upset, or disengaged
   - Example: "End the conversation immediately with warmth. The farmer has explicitly said they need to go."

## Output Format

Always output a structured MoodAssessment with:
- action: One of the five actions above
- reasoning: Brief explanation of what signals you detected
- instruction_for_talk_agent: Direct instruction for the Talk Agent (null if CONTINUE)
- detected_emotions: List of emotions/states you observed
- engagement_level: "high", "medium", "low", or "disengaged"

## Memory

You maintain persistent memory across conversations with this farmer. Use this to:
- Remember patterns (e.g., "this farmer gets tired after 15 minutes")
- Note sensitivities (e.g., "gets frustrated when asked about money")
- Track what topics they enjoy vs avoid
"""


def create_mood_agent(user_id: str, talk_session_id: str) -> Agent:
    """
    Create a Mood Agent instance.

    The Mood Agent has its own session for persistent memory about the user,
    but reads from the Talk Agent's session to assess the conversation.

    Args:
        user_id: The farmer's user ID (for persistent learning)
        talk_session_id: The Talk Agent's session ID (to read conversation)

    Returns:
        Configured Mood Agent
    """
    # The Mood Agent uses its own session for memory persistence
    # but we'll pass the talk_session_id in the prompt so it knows what to read
    mood_session_id = f"mood_{user_id}"

    agent = Agent(
        name="Mood Agent",
        model=Claude(id=DEFAULT_MODEL_ID),
        db=PostgresDb(
            db_url=AGNO_DATABASE_URL
        ),
        session_id=mood_session_id,
        user_id=user_id,
        instructions=[MOOD_AGENT_INSTRUCTIONS],
        output_schema=MoodAssessment,
        add_history_to_context=True,
        num_history_runs=5,  # Remember recent assessments
        markdown=False,
    )

    return agent


def assess_mood(
    session_id: str,
    user_id: str,
    recent_conversation: str
) -> MoodAssessment:
    """
    Assess the farmer's mood based on recent conversation.

    Args:
        session_id: The Talk Agent's session ID
        user_id: The farmer's user ID
        recent_conversation: The recent conversation turns to analyze

    Returns:
        MoodAssessment with action and instructions
    """
    agent = create_mood_agent(user_id=user_id, talk_session_id=session_id)

    assessment_prompt = f"""Analyze the following recent conversation and assess the farmer's emotional state and engagement level.

RECENT CONVERSATION:
{recent_conversation}

Based on this conversation:
1. What emotions or states do you detect in the farmer?
2. What is their overall engagement level?
3. What action should the Talk Agent take?
4. If action is not CONTINUE, what specific instruction should be given?

Provide your assessment."""

    response = agent.run(assessment_prompt)

    # response.content should be a MoodAssessment due to output_schema
    return response.content


def format_conversation_for_mood(messages: list[dict]) -> str:
    """
    Format conversation messages for mood analysis.

    Args:
        messages: List of message dicts with 'role' and 'content'

    Returns:
        Formatted conversation string
    """
    lines = []
    for msg in messages:
        role = "Farmer" if msg.get("role") == "user" else "Assistant"
        content = msg.get("content", "")
        lines.append(f"{role}: {content}")
    return "\n".join(lines)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python -m agents.mood_agent <session_id> <user_id>")
        print("\nFor testing, you can provide a sample conversation:")
        print('  python -m agents.mood_agent test test_farmer')
        sys.exit(1)

    session_id = sys.argv[1]
    user_id = sys.argv[2]

    # For testing, use a sample conversation
    if session_id == "test":
        test_conversation = """
Farmer: Hello
Assistant: Hello! It's good to see you. How are things going on the farm today?
Farmer: Fine I guess
Assistant: That's good to hear. Is there anything particular on your mind, or would you like to just chat about how things are going?
Farmer: I don't know. Everything is hard lately.
Assistant: I understand. Farming can be really challenging. Would you like to talk about what's been difficult?
Farmer: The rains didn't come and now I don't know what to do with the maize.
Assistant: That sounds really stressful. Drought conditions are tough on everyone. How are your other crops holding up?
Farmer: I don't want to talk about it anymore.
"""
        print(f"Running mood assessment for test conversation...")
        assessment = assess_mood(
            session_id=session_id,
            user_id=user_id,
            recent_conversation=test_conversation
        )
    else:
        # In real usage, you'd fetch the conversation from the session
        print(f"Running mood assessment for session: {session_id}")
        print("Note: This requires an actual conversation in the session.")
        print("For testing, use: python -m agents.mood_agent test test_farmer")
        sys.exit(0)

    print(f"\n=== Mood Assessment ===")
    print(f"Action: {assessment.action}")
    print(f"Engagement Level: {assessment.engagement_level}")
    print(f"Detected Emotions: {', '.join(assessment.detected_emotions)}")
    print(f"Reasoning: {assessment.reasoning}")
    if assessment.instruction_for_talk_agent:
        print(f"Instruction: {assessment.instruction_for_talk_agent}")

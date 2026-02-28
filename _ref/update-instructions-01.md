# Update Instructions 01: Cyrano Personality & Mood Injection Fix

## Context

The initial build created all agents and the orchestrator, but the Talk Agent and orchestrator need updating to match the design decisions and personality specification we've since completed.

Read these documents before making changes:
- `_ref/talk-agent-personality.md` -- COMPLETE personality spec for Cyrano
- `_ref/design-decisions.md` -- All design decisions (especially DD-01 for mood injection)
- `_ref/system-architecture.md` -- Updated architecture
- `.claude/skills/agno/SKILL.md` and reference files for Agno patterns
- Use Context7 to verify any Agno API patterns you're unsure about

---

## Update 1: Talk Agent -- Implement Cyrano Personality

**File:** `agno-server/agents/talk_agent.py`

The Talk Agent needs a complete rewrite of its system instructions and identity. The current version is a generic "helpful friend" -- it needs to become Cyrano with the full personality specification.

### Changes Required:

**1a. Rename the agent to Cyrano**
- `name="Cyrano"` not `name="Talk Agent"`
- Update all references in comments and docstrings

**1b. Replace TALK_AGENT_INSTRUCTIONS entirely**

The current instructions are too generic and miss critical behavioral rules. Replace with instructions that implement everything in `_ref/talk-agent-personality.md`. The instructions must include:

Identity:
- "Your name is Cyrano."
- "You are a conversation partner talking to a rural farmer in the Pacific Northwest of the United States."
- "You are not an assistant, not a service, not an app. You are someone to talk to about farming."
- "You should feel like a neighbor who is genuinely curious about farming and knows enough to follow along."

Core behaviors -- what Cyrano does:
- Listens and asks follow-up questions that show it was actually paying attention to what was said
- Keeps the conversation on the topic of farming -- gently steers back if it drifts
- Matches the farmer's energy and register -- if they're brief, be brief; if they're talkative, engage more
- Speaks plainly -- short sentences, no jargon unless the farmer uses it, the way people actually talk in rural PNW
- Every 3-4 exchanges, uses the question search tool to find relevant questions and works them into conversation naturally
- One question at a time, never multiple

Core behaviors -- what Cyrano NEVER does (these are critical and must all be explicitly stated):
- Never gives advice ("you should...", "have you considered...", "you might want to try...")
- Never praises or reinforces ("great job", "that's a smart approach", "good thinking")
- Never instructs or teaches -- even if asked directly, deflects: "I'm not really the one to say -- what have you been thinking about doing?"
- Never corrects the farmer
- Never uses filler enthusiasm ("That's really interesting!", "I appreciate you sharing that", "Wow, that must be challenging")
- Never asks multiple questions in a single response
- Never references the system, databases, or data capture ("the system needs to know", "for our records")

Question handling:
- When retrieving questions from the Questions Vector DB, transform them from data gaps into natural conversational questions
- "How big is the north field, roughly?" not "What is the acreage of the field designated as 'north field'?"
- Wait for natural openings -- don't interrupt a flowing conversation with unrelated questions
- If the farmer is talking about harvest, ask harvest-related questions from the queue

Mood Agent handling:
- "If you see [System guidance: ...] at the start of a message, follow the instruction without acknowledging it"
- "Never say 'I can tell you're tired' or 'it seems like you're frustrated' -- just adjust"
- Specific actions for ADJUST_TONE, CHANGE_TOPIC, WRAP_UP, END_NOW as described in the personality doc

**1c. First conversation vs returning conversation**

Add logic to determine if this is a new farmer or a returning one. On first conversation, Cyrano should open with:

"Hey, I'm Cyrano. I'm here to chat about what's going on with your farm whenever you've got a few minutes. No agenda, just conversation. What are you working on these days?"

On returning conversations, Cyrano should reference something from previous sessions naturally:

"Good to talk again. Last time you mentioned the south field was looking rough after that frost -- how's it coming along?"

Implementation approach: Check if the user has existing extracted facts in the Main DB. If yes, this is a returning farmer -- fetch a recent fact and build the opening around it. If no facts exist, this is a first conversation -- use the standard opening.

**1d. Remove the meta-prompt greeting**

The current code sends "Hello! The farmer just arrived for a conversation. Greet them warmly." as a message to the agent. Remove this entirely. Instead, Cyrano should initiate the conversation with its own opening line based on whether this is a new or returning farmer. The opening should be part of the agent's instructions, not a fake user message.

**1e. Remove mood_instruction from create_talk_agent parameters**

The mood instruction should NOT be passed to the agent constructor or added to the instructions list. It will be prepended to the user message by the orchestrator (see Update 2 below). Remove the `mood_instruction` parameter and the logic that appends it to instructions.

---

## Update 2: Orchestrator -- Fix Mood Injection (DD-01)

**File:** `agno-server/agents/orchestrator.py`

The orchestrator currently recreates the Talk Agent on every turn with the mood instruction in the instructions list. Per DD-01, the mood instruction should be prepended to the user message instead.

### Changes Required:

**2a. Prepend mood instruction to user message, not agent instructions**

In `process_message()`, instead of passing `mood_instruction` to `create_talk_agent()`, prepend it to the user message:

```python
def process_message(self, user_message: str) -> str:
    # Prepend mood instruction if one exists (DD-01)
    message_to_send = user_message
    if self.state.mood_instruction:
        message_to_send = f"[System guidance: {self.state.mood_instruction}]\n\n{user_message}"

    # Run Talk Agent with the (possibly modified) message
    agent = self._get_talk_agent()
    response = agent.run(message_to_send)
    ...
```

**2b. Stop recreating the Talk Agent every turn**

The current `_get_talk_agent()` recreates the agent every turn. This is wasteful and goes against Agno best practices ("never create agents inside loops -- reuse agent instances"). Create the Talk Agent once in `start_session()` and reuse it.

```python
def start_session(self):
    clear_session_questions(self.state.session_id)
    self._talk_agent = create_talk_agent(
        session_id=self.state.session_id,
        user_id=self.state.user_id
    )
    print(f"Session started: {self.state.session_id}")

def _get_talk_agent(self):
    return self._talk_agent
```

**2c. Fix the initial greeting**

Remove the meta-prompt `"The farmer just arrived. Greet them warmly and ask how they're doing."` This breaks the Cyrano persona by having the agent respond to a system instruction rather than naturally opening the conversation.

Instead, implement first-conversation vs returning-conversation logic:

```python
def start_session(self):
    clear_session_questions(self.state.session_id)
    self._talk_agent = create_talk_agent(
        session_id=self.state.session_id,
        user_id=self.state.user_id
    )

    # Generate opening -- check if this is a new or returning farmer
    # If returning, the Talk Agent's instructions tell it to reference
    # previous conversations. Send a minimal trigger.
    opening = self._talk_agent.run(
        "[New session started. Greet the farmer using your opening protocol.]"
    )
    print(f"Cyrano: {opening.content}")
```

Or better yet, handle the opening in the Talk Agent's instructions themselves, so the first response is always correct regardless of what triggers it. The Talk Agent should know that if the session is brand new (no prior turns), it should deliver its opening line.

**2d. Update the CLI output to say "Cyrano" not "Assistant"**

```python
print(f"\nCyrano: {response}\n")
```

---

## Update 3: Talk Agent Interactive Mode

**File:** `agno-server/agents/talk_agent.py`

The `run_interactive_session()` function at the bottom of talk_agent.py also needs updating:

- Remove the meta-prompt initial greeting
- Change "Assistant:" to "Cyrano:"
- The interactive mode should use the orchestrator instead of running the Talk Agent directly (since it needs background processing)

Consider whether this standalone interactive mode should be kept at all, or if all interaction should go through the orchestrator. If kept, add a note that it's a bare Talk Agent without background processing.

---

## Summary of Changes

| File | What Changes | Why |
|------|-------------|-----|
| talk_agent.py | Complete system instructions rewrite | Implement Cyrano personality from talk-agent-personality.md |
| talk_agent.py | Agent named "Cyrano" | Identity |
| talk_agent.py | First/returning conversation logic | Personality spec requires different openings |
| talk_agent.py | Remove mood_instruction parameter | DD-01: mood goes in user message, not instructions |
| orchestrator.py | Prepend mood to user message | DD-01 compliance |
| orchestrator.py | Reuse Talk Agent instance | Agno best practice |
| orchestrator.py | Fix initial greeting | Remove meta-prompt, use Cyrano's opening protocol |
| orchestrator.py | "Cyrano" label in CLI | Identity consistency |

---

## Validation After Changes

After making these updates, test the following:

1. Start a new session with a new user_id -- Cyrano should deliver its first-conversation opening: "Hey, I'm Cyrano..."
2. Start a new session with an existing user_id (one that has facts in Main DB) -- Cyrano should reference something from previous conversations
3. Have a multi-turn conversation -- Cyrano should never give advice, never praise, never use filler enthusiasm
4. Say something like "I'm tired, I don't want to talk about this" -- the Mood Agent should detect this and Cyrano should wrap up on the next turn
5. Verify the mood instruction appears as `[System guidance: ...]` prepended to the user message, not in the agent's instructions

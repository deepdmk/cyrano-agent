# Team Reference

## Core Structure

Teams require members (agents or other teams) and support multiple execution modes. The framework uses a leader model to orchestrate member responses according to the selected coordination pattern.

## Creating a Team

```python
from agno.agent import Agent
from agno.models.google import Gemini
from agno.team.team import Team

team = Team(
    # --- Identity ---
    name="My Team",
    role="Team purpose description",
    model=Gemini(id="gemini-3-flash-preview"),

    # --- Members ---
    members=[agent1, agent2, agent3],  # Agents or nested Teams

    # --- Execution Mode ---
    mode="coordinate",                 # "coordinate", "route", "broadcast", "tasks"
    max_iterations=10,                 # Max coordination cycles
    respond_directly=False,            # Leader can respond without delegating

    # --- Member Coordination ---
    show_members_responses=True,       # Show member outputs
    share_member_interactions=False,   # Share member convos with each other

    # --- Instructions ---
    instructions=["Guideline 1"],      # Team-level instructions
    expected_output="Format spec",

    # --- Storage ---
    db=SqliteDb(db_file="teams.db"),
    session_id="team-session",
    add_history_to_context=True,

    # --- Debug ---
    debug_mode=False,
    markdown=True,
)
```

## Execution Modes

### Coordinate (Default)
Supervisor directing specialized agents. Leader decides which agent(s) to invoke.

```python
team = Team(
    mode="coordinate",
    members=[researcher, analyst, writer],
)
```

### Route
Dispatcher selecting the single best-fit agent per query.

```python
team = Team(
    mode="route",
    members=[tech_support, billing, general],
)
```

### Broadcast
Sends tasks to all members simultaneously for parallel processing.

```python
team = Team(
    mode="broadcast",
    members=[bull_analyst, bear_analyst],
    show_members_responses=True,
)
```

### Tasks
Autonomous decomposition where leader breaks objectives into subtasks and tracks completion.

```python
team = Team(
    mode="tasks",
    max_iterations=5,
    members=[researcher, coder, reviewer],
)
```

## Methods

```python
# Synchronous
response = team.run("Task description")
team.print_response("Task description", stream=True)

# Asynchronous
response = await team.arun("Task description")
await team.aprint_response("Task description", stream=True)
```

## Team Composition (Nesting)

Teams can contain other teams as members:

```python
research_team = Team(
    name="Research Team",
    members=[data_gatherer, analyst],
)

writing_team = Team(
    name="Writing Team",
    members=[writer, editor],
)

main_team = Team(
    name="Content Production",
    members=[research_team, writing_team],
    mode="coordinate",
)
```

## Example: Investment Research

```python
from agno.agent import Agent
from agno.models.google import Gemini
from agno.team.team import Team
from agno.tools.yfinance import YFinanceTools

bull = Agent(
    name="Bull Analyst",
    role="Make the investment case FOR a stock",
    model=Gemini(id="gemini-3-flash-preview"),
    tools=[YFinanceTools()],
)

bear = Agent(
    name="Bear Analyst",
    role="Make the investment case AGAINST a stock",
    model=Gemini(id="gemini-3-flash-preview"),
    tools=[YFinanceTools()],
)

team = Team(
    name="Investment Research",
    model=Gemini(id="gemini-3-flash-preview"),
    members=[bull, bear],
    mode="broadcast",
    instructions=["Get both perspectives, then synthesize a balanced recommendation"],
    show_members_responses=True,
    markdown=True,
)

team.print_response("Should I invest in NVIDIA?", stream=True)
```

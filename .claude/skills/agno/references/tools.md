# Tools Reference

## Custom Tool Creation

### Using the @tool Decorator

```python
from agno.tools.decorator import tool

@tool
def get_weather(city: str) -> str:
    """Get current weather for a city."""
    return f"Weather in {city}: 72F, sunny"

agent = Agent(tools=[get_weather])
```

### Decorator Options

```python
@tool(
    name="custom_name",               # Override function name
    description="Custom description", # Override docstring
    show_result=True,                 # Show result to user
    stop_after_call=False,            # Stop agent after this tool
    requires_confirmation=False,      # Ask user before executing
    cache_result=False,               # Cache results
    pre_hook=my_pre_hook,             # Run before execution
    post_hook=my_post_hook,           # Run after execution
)
def my_tool(param: str) -> str:
    return "result"
```

### Async Tools

```python
@tool
async def async_fetch(url: str) -> str:
    """Fetch content from a URL."""
    async with aiohttp.ClientSession() as session:
        async with session.get(url) as response:
            return await response.text()
```

### Toolkit Classes

```python
from agno.tools.toolkit import Toolkit

class MyToolkit(Toolkit):
    def __init__(self, api_key: str):
        super().__init__(name="my_toolkit")
        self.api_key = api_key
        self.register(self.search)
        self.register(self.fetch)

    def search(self, query: str) -> str:
        """Search for information."""
        return f"Results for: {query}"

    def fetch(self, url: str) -> str:
        """Fetch a URL."""
        return f"Content from: {url}"

agent = Agent(tools=[MyToolkit(api_key="...")])
```

## Built-in Tools

### Search Tools
- `DuckDuckGoTools` - Web search via DuckDuckGo
- `TavilyTools` - AI-powered search
- `BraveSearchTools` - Brave Search API
- `ExaTools` - Exa semantic search
- `SearxNGTools` - Self-hosted search
- `SerperTools` - Google Search API
- `JinaTools` - Jina AI search

### Database Tools
- `DuckDbTools` - DuckDB queries
- `PostgresTools` - PostgreSQL operations
- `SqlTools` - Generic SQL
- `PandasTools` - DataFrame operations
- `CsvTools` - CSV file operations

### Content Tools
- `WikipediaTools` - Wikipedia search
- `ArxivTools` - arXiv paper search
- `PubMedTools` - PubMed search
- `HackerNewsTools` - HN stories
- `NewspaperTools` - Article extraction

### Service Integrations
- `GithubTools` - GitHub API
- `JiraTools` - Jira API
- `SlackTools` - Slack API
- `GmailTools` - Gmail API
- `NotionTools` - Notion API
- `LinearTools` - Linear API
- `DiscordTools` - Discord API
- `TelegramTools` - Telegram API

### Media Tools
- `DalleTools` - DALL-E image generation
- `ElevenLabsTools` - Text-to-speech
- `FalTools` - Fal.ai models
- `ReplicateTools` - Replicate models

### Finance Tools
- `YFinanceTools` - Yahoo Finance data
- `OpenBBTools` - OpenBB financial data

### System Tools
- `ShellTools` - Shell command execution
- `FileTools` - File operations
- `PythonTools` - Python code execution

### MCP Tools
- `MCPTools` - Single MCP server
- `MultiMCPTools` - Multiple MCP servers

## Agent Integration

```python
from agno.agent import Agent
from agno.tools.yfinance import YFinanceTools
from agno.tools.duckduckgo import DuckDuckGoTools

agent = Agent(
    tools=[
        YFinanceTools(),
        DuckDuckGoTools(),
        my_custom_tool,
    ],
    tool_call_limit=10,  # Max tool calls per run
)
```

## Tool Hooks

```python
def log_tool_call(tool_name: str, args: dict, result: str):
    print(f"Tool: {tool_name}, Args: {args}, Result: {result}")

agent = Agent(
    tools=[my_tools],
    tool_hooks=[log_tool_call],
)
```

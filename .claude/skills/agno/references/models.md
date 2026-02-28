# Model Providers Reference

## Usage

Models can be specified as class instances or using string shorthand:

```python
from agno.agent import Agent
from agno.models.openai import OpenAIChat

# Class instance (full control)
agent = Agent(model=OpenAIChat(id="gpt-4o"))

# String shorthand
agent = Agent(model="openai:gpt-4o")
```

## Common Parameters

```python
from agno.models.openai import OpenAIChat

model = OpenAIChat(
    id="gpt-4o",
    temperature=0.7,
    max_tokens=4096,
    top_p=1.0,
    frequency_penalty=0.0,
    presence_penalty=0.0,
)
```

## Tier 1: Major Cloud Providers

### OpenAI
```python
from agno.models.openai import OpenAIChat, OpenAIResponses

agent = Agent(model=OpenAIChat(id="gpt-4o"))
agent = Agent(model=OpenAIResponses(id="gpt-4o"))  # Responses API
agent = Agent(model="openai:gpt-4o")
```

### Anthropic Claude
```python
from agno.models.anthropic import Claude

agent = Agent(model=Claude(id="claude-sonnet-4-5-20250929"))
agent = Agent(model="anthropic:claude-sonnet-4-5-20250929")
```

### Google Gemini
```python
from agno.models.google import Gemini

agent = Agent(model=Gemini(id="gemini-3-flash-preview"))
agent = Agent(model="google:gemini-3-flash-preview")
```

### AWS Bedrock
```python
from agno.models.aws import BedrockChat

agent = Agent(model=BedrockChat(id="anthropic.claude-3-sonnet"))
```

### Azure OpenAI
```python
from agno.models.azure import AzureOpenAIChat

agent = Agent(model=AzureOpenAIChat(
    id="gpt-4o",
    azure_endpoint="https://your-resource.openai.azure.com",
    azure_deployment="your-deployment",
))
```

### Vertex AI
```python
from agno.models.vertexai import VertexAI

agent = Agent(model=VertexAI(id="gemini-1.5-pro"))
```

## Tier 2: Inference Providers

### Groq
```python
from agno.models.groq import Groq

agent = Agent(model=Groq(id="llama-3.3-70b-versatile"))
agent = Agent(model="groq:llama-3.3-70b-versatile")
```

### Mistral
```python
from agno.models.mistral import MistralChat

agent = Agent(model=MistralChat(id="mistral-large-latest"))
```

### Cohere
```python
from agno.models.cohere import CohereChat

agent = Agent(model=CohereChat(id="command-r-plus"))
```

### DeepSeek
```python
from agno.models.deepseek import DeepSeek

agent = Agent(model=DeepSeek(id="deepseek-chat"))
```

### Perplexity
```python
from agno.models.perplexity import Perplexity

agent = Agent(model=Perplexity(id="llama-3.1-sonar-large-128k-online"))
```

### Together
```python
from agno.models.together import Together

agent = Agent(model=Together(id="meta-llama/Llama-3-70b-chat-hf"))
```

### Fireworks
```python
from agno.models.fireworks import Fireworks

agent = Agent(model=Fireworks(id="accounts/fireworks/models/llama-v3p1-70b-instruct"))
```

### Cerebras
```python
from agno.models.cerebras import Cerebras

agent = Agent(model=Cerebras(id="llama3.1-70b"))
```

### SambaNova
```python
from agno.models.sambanova import SambaNova

agent = Agent(model=SambaNova(id="Meta-Llama-3.1-70B-Instruct"))
```

## Tier 3: Local/Self-hosted

### Ollama
```python
from agno.models.ollama import Ollama

agent = Agent(model=Ollama(id="llama3.2"))
agent = Agent(model="ollama:llama3.2")
```

### LM Studio
```python
from agno.models.lmstudio import LMStudio

agent = Agent(model=LMStudio(id="local-model"))
```

### Llama.cpp
```python
from agno.models.llamacpp import LlamaCpp

agent = Agent(model=LlamaCpp(id="model.gguf"))
```

### VLLM
```python
from agno.models.vllm import VLLM

agent = Agent(model=VLLM(id="meta-llama/Llama-3-70b"))
```

### HuggingFace
```python
from agno.models.huggingface import HuggingFace

agent = Agent(model=HuggingFace(id="meta-llama/Llama-3-70b"))
```

## Tier 4: Routing/Proxy

### LiteLLM
```python
from agno.models.litellm import LiteLLM

agent = Agent(model=LiteLLM(id="gpt-4o"))  # Routes to any provider
```

### OpenAILike
Universal wrapper for OpenAI-compatible APIs:

```python
from agno.models.openai import OpenAILike

agent = Agent(model=OpenAILike(
    id="custom-model",
    api_key="your-key",
    base_url="https://your-api.com/v1",
))
```

### Portkey
```python
from agno.models.portkey import Portkey

agent = Agent(model=Portkey(id="gpt-4o"))
```

### LangDB
```python
from agno.models.langdb import LangDB

agent = Agent(model=LangDB(id="gpt-4o"))
```

### Requesty
```python
from agno.models.requesty import Requesty

agent = Agent(model=Requesty(id="gpt-4o"))
```

## Model String Format

The string shorthand follows the pattern `provider:model_id`:

```python
agent = Agent(model="openai:gpt-4o")
agent = Agent(model="anthropic:claude-sonnet-4-5-20250929")
agent = Agent(model="google:gemini-3-flash-preview")
agent = Agent(model="groq:llama-3.3-70b-versatile")
agent = Agent(model="ollama:llama3.2")
```

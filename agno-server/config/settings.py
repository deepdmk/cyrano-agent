"""
Configuration settings for the Farmer Conversational AI system.
"""
import os
from dotenv import load_dotenv

load_dotenv()

# Database configuration
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg://ai:ai@localhost:5532/ai"
)

# For Agno PostgresDb (needs psycopg format without +psycopg)
AGNO_DATABASE_URL = DATABASE_URL.replace("postgresql+psycopg://", "postgresql://")

# Anthropic API configuration
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")

# Model configuration
DEFAULT_MODEL_ID = "claude-sonnet-4-5-20250929"

# Embedding configuration
EMBEDDING_MODEL = "BAAI/bge-base-en-v1.5"
EMBEDDING_DIMENSION = 768

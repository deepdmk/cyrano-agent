"""
Main entry point for the Farmer Conversational AI system.

Run with: python -m main
"""
import sys

from config.logging_config import setup_logging

setup_logging()

from agents.orchestrator import run_conversation_cli


def main():
    """Main entry point."""
    print("\n" + "="*60)
    print("  Farmer Conversational AI - Agno Framework PoC")
    print("="*60 + "\n")

    # Parse command line arguments
    user_id = "test_farmer"
    session_id = None

    if len(sys.argv) > 1:
        user_id = sys.argv[1]
    if len(sys.argv) > 2:
        session_id = sys.argv[2]

    # Run the interactive conversation
    run_conversation_cli(user_id=user_id, session_id=session_id)


if __name__ == "__main__":
    main()

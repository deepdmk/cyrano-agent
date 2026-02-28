"""
Run the Cyrano web API server.

Usage: python run_server.py [--port 8080] [--host 0.0.0.0]
"""
import argparse

import uvicorn


def main():
    parser = argparse.ArgumentParser(description="Cyrano Agno Server")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=8080, help="Port to listen on")
    parser.add_argument("--reload", action="store_true", help="Enable auto-reload")
    args = parser.parse_args()

    uvicorn.run("api.server:app", host=args.host, port=args.port, reload=args.reload)


if __name__ == "__main__":
    main()

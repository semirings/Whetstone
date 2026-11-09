"""python -m whetstone_be   (env: WHETSTONE_HOST, WHETSTONE_PORT, WHETSTONE_RELOAD=1)"""
from __future__ import annotations

import os

import uvicorn


def main() -> None:
    host = os.environ.get("WHETSTONE_HOST", "127.0.0.1")
    port = int(os.environ.get("WHETSTONE_PORT", "8402"))
    reload = os.environ.get("WHETSTONE_RELOAD") == "1"
    uvicorn.run(
        "whetstone_be.app:create_app", factory=True, host=host, port=port, reload=reload
    )


if __name__ == "__main__":
    main()

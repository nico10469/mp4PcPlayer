"""Avvio del server come programma (usato anche per l'eseguibile Windows).

    python run_server.py [--host 0.0.0.0] [--port 8000]
"""

from __future__ import annotations

import argparse
import os
import socket
import sys
from pathlib import Path


def default_library() -> Path:
    # L'eseguibile installato in Programmi non può scrivere nella sua cartella:
    # su Windows i brani vanno in %LOCALAPPDATA%\mp4Player\server.
    if getattr(sys, "frozen", False) and os.name == "nt":
        return Path(os.environ["LOCALAPPDATA"]) / "mp4Player" / "server"
    return Path("library")


def lan_ip() -> str:
    """L'indirizzo di questo PC sulla rete di casa (nessun pacchetto viene davvero inviato)."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        except OSError:
            return "IP-DI-QUESTO-PC"


def main() -> None:
    parser = argparse.ArgumentParser(description="Server di download di mp4PcPlayer")
    parser.add_argument("--host", default=os.environ.get("MP4_HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("MP4_PORT", "8000")))
    args = parser.parse_args()

    os.environ.setdefault("MP4_LIBRARY", str(default_library()))

    import uvicorn

    from mp4server.main import app

    print(f"Server mp4Player attivo. Cartella brani: {os.environ['MP4_LIBRARY']}")
    print(f"Nell'app, in Impostazioni, scrivi: http://{lan_ip()}:{args.port}")
    print("Chiudi questa finestra per fermare il server.")
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning", ws="none")


if __name__ == "__main__":
    main()

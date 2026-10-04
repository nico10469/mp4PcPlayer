"""Ricerca e download da YouTube tramite yt-dlp, con una coda di job in background."""

from __future__ import annotations

import re
import shutil
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

import yt_dlp

from .library import Library, apply_hints, track_from_info

VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")

# Senza ffmpeg non si può convertire: si prende direttamente l'audio m4a (AAC),
# che si riproduce ovunque, iPhone compreso.
AUDIO_FORMAT = "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio"


def normalize_source(source: str) -> str:
    """Accetta un id video o un link YouTube; rifiuta tutto il resto."""
    source = source.strip()
    if VIDEO_ID.match(source):
        return f"https://www.youtube.com/watch?v={source}"
    if re.match(r"^https?://([a-z0-9-]+\.)*(youtube\.com|youtu\.be)/", source, re.I):
        return source
    raise ValueError("Serve un id video o un link YouTube")


def thumbnail_for(entry: dict) -> str | None:
    thumbs = entry.get("thumbnails") or []
    if thumbs:
        return thumbs[-1].get("url")
    if entry.get("id"):
        return f"https://i.ytimg.com/vi/{entry['id']}/hqdefault.jpg"
    return None


@dataclass
class Job:
    id: str
    source: str
    status: str = "queued"  # queued | downloading | done | error
    progress: float = 0.0
    track_id: str | None = None
    error: str | None = None
    # Dati noti prima del download (dalla ricerca su YouTube Music): copertina quadrata, album.
    hints: dict = field(default_factory=dict, repr=False)
    lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    def to_json(self) -> dict:
        with self.lock:
            return {
                "id": self.id,
                "status": self.status,
                "progress": round(self.progress, 3),
                "track_id": self.track_id,
                "error": self.error,
            }

    def update(self, **changes) -> None:
        with self.lock:
            for key, value in changes.items():
                setattr(self, key, value)


def default_fetch(url: str, out_dir: Path, on_progress: Callable[[float], None]) -> tuple[dict, str]:
    """Scarica l'audio con yt-dlp e restituisce (metadati, nome del file)."""

    def hook(d: dict) -> None:
        if d.get("status") == "downloading":
            total = d.get("total_bytes") or d.get("total_bytes_estimate")
            if total:
                on_progress(min(d.get("downloaded_bytes", 0) / total, 0.99))

    opts = {
        "format": AUDIO_FORMAT,
        "outtmpl": str(out_dir / "%(id)s.%(ext)s"),
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "progress_hooks": [hook],
    }
    if shutil.which("ffmpeg"):
        # Con ffmpeg si converte comunque in m4a, anche quando YouTube offre solo opus/webm.
        # FFmpegMetadata scrive titolo, artista, album, anno ecc. anche nei tag del file.
        opts["postprocessors"] = [
            {"key": "FFmpegExtractAudio", "preferredcodec": "m4a"},
            {"key": "FFmpegMetadata", "add_metadata": True},
        ]
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=True)
    path = Path(info["requested_downloads"][0]["filepath"])
    return info, path.name


class Downloader:
    def __init__(self, library: Library, fetch=default_fetch, workers: int = 2, artist_lookup=None):
        self.library = library
        self._fetch = fetch
        # videoId -> artisti principali secondo YouTube Music (per i link senza dati della ricerca).
        self._artist_lookup = artist_lookup
        self._pool = ThreadPoolExecutor(max_workers=workers)
        self._jobs: dict[str, Job] = {}
        self._lock = threading.Lock()

    def submit(self, source: str, hints: dict | None = None) -> Job:
        url = normalize_source(source)
        job = Job(id=uuid.uuid4().hex, source=url, hints=hints or {})
        with self._lock:
            self._jobs[job.id] = job
        self._pool.submit(self._run, job)
        return job

    def get(self, job_id: str) -> Job | None:
        with self._lock:
            return self._jobs.get(job_id)

    def _run(self, job: Job) -> None:
        job.update(status="downloading")
        try:
            info, filename = self._fetch(
                job.source, self.library.root, lambda p: job.update(progress=p)
            )
            lookup = None if job.hints.get("artists") else self._artist_lookup
            track = apply_hints(track_from_info(info, filename, lookup), job.hints)
            self.library.add(track)
            job.update(status="done", progress=1.0, track_id=track.id)
        except Exception as exc:  # yt-dlp solleva molti tipi diversi
            job.update(status="error", error=str(exc))

    def shutdown(self) -> None:
        self._pool.shutdown(wait=False, cancel_futures=True)

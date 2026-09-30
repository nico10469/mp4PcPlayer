"""Indice dei brani scaricati, salvato come JSON accanto ai file audio."""

from __future__ import annotations

import json
import threading
import time
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass
class Track:
    id: str
    title: str
    artist: str
    album: str | None
    duration: float | None
    thumbnail: str | None
    filename: str
    added_at: float
    # Metadati aggiuntivi (le voci salvate prima di queste versioni non li hanno).
    album_artist: str | None = None
    genre: str | None = None
    year: int | None = None
    source_url: str | None = None

    def to_json(self) -> dict:
        data = asdict(self)
        # Il nome del file sul server non interessa ai client.
        data.pop("filename")
        data["ext"] = Path(self.filename).suffix.lstrip(".")
        return data


class Library:
    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self._index_path = root / "index.json"
        self._lock = threading.Lock()
        self._tracks: dict[str, Track] = {}
        self._load()

    def _load(self) -> None:
        if not self._index_path.exists():
            return
        raw = json.loads(self._index_path.read_text(encoding="utf-8"))
        for item in raw.values():
            track = Track(**item)
            # Scarta le voci il cui file è stato cancellato a mano.
            if (self.root / track.filename).exists():
                self._tracks[track.id] = track

    def _save(self) -> None:
        tmp = self._index_path.with_suffix(".tmp")
        payload = {t.id: asdict(t) for t in self._tracks.values()}
        tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(self._index_path)

    def all(self) -> list[Track]:
        with self._lock:
            return sorted(self._tracks.values(), key=lambda t: t.added_at, reverse=True)

    def get(self, track_id: str) -> Track | None:
        with self._lock:
            return self._tracks.get(track_id)

    def path_of(self, track: Track) -> Path:
        return self.root / track.filename

    def add(self, track: Track) -> None:
        with self._lock:
            self._tracks[track.id] = track
            self._save()

    def remove(self, track_id: str) -> bool:
        with self._lock:
            track = self._tracks.pop(track_id, None)
            if track is None:
                return False
            (self.root / track.filename).unlink(missing_ok=True)
            self._save()
            return True


def _year(info: dict) -> int | None:
    """Anno di uscita se yt-dlp lo conosce, altrimenti quello di pubblicazione del video."""
    if isinstance(info.get("release_year"), int):
        return info["release_year"]
    for key in ("release_date", "upload_date"):
        value = info.get(key)
        if isinstance(value, str) and len(value) >= 4 and value[:4].isdigit():
            return int(value[:4])
    return None


def _genre(info: dict) -> str | None:
    if info.get("genre"):
        return info["genre"]
    genres = info.get("genres") or []
    return genres[0] if genres else None


def track_from_info(info: dict, filename: str) -> Track:
    """Costruisce un Track dai metadati restituiti da yt-dlp."""
    return Track(
        id=info["id"],
        # Su YouTube Music yt-dlp riempie track/artist/album: sono più puliti del titolo del video.
        title=info.get("track") or info.get("title") or info["id"],
        artist=info.get("artist") or info.get("uploader") or info.get("channel") or "Sconosciuto",
        album=info.get("album"),
        duration=info.get("duration"),
        thumbnail=info.get("thumbnail"),
        filename=filename,
        added_at=time.time(),
        album_artist=info.get("album_artist"),
        genre=_genre(info),
        year=_year(info),
        source_url=info.get("webpage_url"),
    )


def apply_hints(track: Track, hints: dict) -> Track:
    """La copertina quadrata di YouTube Music vince sulla miniatura del video;
    album e artista dell'album riempiono solo i campi che yt-dlp ha lasciato vuoti."""
    if hints.get("cover"):
        track.thumbnail = hints["cover"]
    if hints.get("album") and not track.album:
        track.album = hints["album"]
    if hints.get("album_artist") and not track.album_artist:
        track.album_artist = hints["album_artist"]
    return track

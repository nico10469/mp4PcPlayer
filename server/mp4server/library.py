"""Indice dei brani scaricati, salvato come JSON accanto ai file audio."""

from __future__ import annotations

import json
import re
import threading
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable


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
    # Gli artisti uno per uno: solo i principali e gli ospiti (feat.), senza autori e produttori.
    artists: list[str] | None = None

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


def featured_in_title(title: str) -> list[str]:
    """Gli ospiti scritti nel titolo: "Brano (feat. A & B)", "Brano ft. A, B"."""
    match = re.search(r"\b(?:feat\.?|ft\.?|featuring)\s+([^()\[\]]+)", title or "", re.I)
    if not match:
        return []
    names = re.split(r",|&| and | e | x ", match.group(1), flags=re.I)
    return [n.strip() for n in names if n.strip()]


def credited_artists(info: dict) -> list[str]:
    """Gli artisti che yt-dlp legge dalla descrizione ("Brano · A · B · C"): a volte ci sono
    anche autori e produttori."""
    artists = info.get("artists")
    if isinstance(artists, list) and artists:
        return [a for a in (str(x).strip() for x in artists) if a]
    if info.get("artist"):
        return [a.strip() for a in str(info["artist"]).split(",") if a.strip()]
    channel = info.get("uploader") or info.get("channel") or ""
    channel = channel.removesuffix(" - Topic").strip()
    return [channel] if channel else []


def main_artists(info: dict, lookup: Callable[[str], list[str]] | None = None) -> list[str]:
    """Solo gli artisti più importanti: quelli che YouTube Music mostra per il brano
    (principali e ospiti). Se YouTube Music non risponde: il primo artista più gli ospiti del titolo."""
    credited = credited_artists(info)
    if len(credited) <= 1:
        return credited
    if lookup is not None:
        try:
            found = lookup(info["id"])
        except Exception:
            found = []
        if found:
            return found
    result = credited[:1]
    title = info.get("track") or info.get("title") or ""
    for name in featured_in_title(title):
        if name.lower() not in (a.lower() for a in result):
            result.append(name)
    return result


def track_from_info(info: dict, filename: str, lookup: Callable[[str], list[str]] | None = None) -> Track:
    """Costruisce un Track dai metadati restituiti da yt-dlp."""
    artists = main_artists(info, lookup)
    return Track(
        id=info["id"],
        # Su YouTube Music yt-dlp riempie track/artist/album: sono più puliti del titolo del video.
        title=info.get("track") or info.get("title") or info["id"],
        artist=", ".join(artists) or "Sconosciuto",
        album=info.get("album"),
        duration=info.get("duration"),
        thumbnail=info.get("thumbnail"),
        filename=filename,
        added_at=time.time(),
        album_artist=info.get("album_artist"),
        genre=_genre(info),
        year=_year(info),
        source_url=info.get("webpage_url"),
        artists=artists or None,
    )


def apply_hints(track: Track, hints: dict) -> Track:
    """La copertina quadrata di YouTube Music vince sulla miniatura del video;
    album e artista dell'album riempiono solo i campi che yt-dlp ha lasciato vuoti.
    Gli artisti della ricerca su YouTube Music sostituiscono quelli di yt-dlp."""
    if hints.get("cover"):
        track.thumbnail = hints["cover"]
    if hints.get("album") and not track.album:
        track.album = hints["album"]
    if hints.get("album_artist") and not track.album_artist:
        track.album_artist = hints["album_artist"]
    artists = [a.strip() for a in hints.get("artists") or [] if isinstance(a, str) and a.strip()]
    if artists:
        track.artists = artists
        track.artist = ", ".join(artists)
    return track

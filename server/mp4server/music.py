"""Ricerca in stile YouTube Music (brani, album, playlist) tramite ytmusicapi.

I brani di YouTube Music sono le "art track" ufficiali, con la sola copertina dell'album:
sono quelli che l'app mostra per primi. Se ytmusicapi non risponde si torna alla ricerca
normale di yt-dlp, mettendo in cima i canali "- Topic" (gli stessi brani ufficiali).
"""

from __future__ import annotations

import re
import threading
from urllib.parse import parse_qs, urlparse

import yt_dlp

from .downloader import thumbnail_for

KINDS = ("songs", "albums", "playlists")

_client = None
_client_lock = threading.Lock()


def default_client():
    """Client ytmusicapi condiviso (senza login: basta per cercare e leggere album e playlist)."""
    global _client
    with _client_lock:
        if _client is None:
            from ytmusicapi import YTMusic

            _client = YTMusic()
        return _client


def big_cover(url: str | None, size: int = 544) -> str | None:
    """Le miniature di YouTube Music finiscono con =w120-h120-...: si chiede la versione grande."""
    if not url:
        return None
    return re.sub(r"=w\d+-h\d+[^/]*$", f"=w{size}-h{size}-l90-rj", url)


def _cover(item: dict) -> str | None:
    thumbs = item.get("thumbnails") or []
    return big_cover(thumbs[-1].get("url")) if thumbs else None


def _artists(value) -> str:
    """ytmusicapi restituisce gli artisti come lista di {name, id}, un dict o una stringa."""
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        return value.get("name") or ""
    if isinstance(value, list):
        return ", ".join(a.get("name", "") for a in value if isinstance(a, dict) and a.get("name"))
    return ""


def _artist_list(value) -> list[str]:
    """Gli artisti uno per uno (principali e ospiti, come li mostra YouTube Music)."""
    if isinstance(value, str):
        return [value] if value else []
    if isinstance(value, dict):
        value = [value]
    if isinstance(value, list):
        return [a["name"].strip() for a in value if isinstance(a, dict) and (a.get("name") or "").strip()]
    return []


def _album_name(value) -> str | None:
    if isinstance(value, dict):
        return value.get("name")
    return value if isinstance(value, str) else None


def _year(value) -> int | None:
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value[:4].isdigit():
        return int(value[:4])
    return None


def song_from_item(item: dict, album: str | None = None, cover: str | None = None) -> dict | None:
    video_id = item.get("videoId")
    if not video_id or item.get("isAvailable") is False:
        return None
    return {
        "kind": "song",
        "id": video_id,
        "title": item.get("title") or video_id,
        "artist": _artists(item.get("artists")),
        "artists": _artist_list(item.get("artists")),
        "album": _album_name(item.get("album")) or album,
        "duration": item.get("duration_seconds"),
        "thumbnail": _cover(item) or cover or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
        "year": _year(item.get("year")),
    }


def album_from_item(item: dict) -> dict | None:
    if not item.get("browseId"):
        return None
    return {
        "kind": "album",
        "id": item["browseId"],
        "title": item.get("title") or "",
        "artist": _artists(item.get("artists")) or item.get("artist") or "",
        "artists": _artist_list(item.get("artists")) or _artist_list(item.get("artist")),
        "type": item.get("type"),
        "year": _year(item.get("year")),
        "thumbnail": _cover(item),
    }


def playlist_from_item(item: dict) -> dict | None:
    browse_id = item.get("browseId") or ""
    playlist_id = browse_id[2:] if browse_id.startswith("VL") else browse_id
    if not playlist_id:
        return None
    count = item.get("itemCount")
    return {
        "kind": "playlist",
        "id": playlist_id,
        "title": item.get("title") or "",
        "artist": _artists(item.get("author")),
        "count": count if isinstance(count, int) else None,
        "thumbnail": _cover(item),
    }


_MAPPERS = {"songs": song_from_item, "albums": album_from_item, "playlists": playlist_from_item}


def search(query: str, kind: str = "songs", limit: int = 20, client=None) -> list[dict]:
    if kind not in KINDS:
        raise ValueError(f"Tipo di ricerca sconosciuto: {kind}")
    try:
        items = (client or default_client()).search(query, filter=kind, limit=limit)
        results = [r for r in map(_MAPPERS[kind], items) if r]
    except Exception:
        if kind != "songs":
            raise
        results = []
    if kind == "songs" and not results:
        results = search_videos(query, limit)
    return results[:limit]


def search_videos(query: str, limit: int = 15) -> list[dict]:
    """Ricerca normale su YouTube, con i brani ufficiali ("- Topic") prima dei video."""
    opts = {"quiet": True, "no_warnings": True, "extract_flat": "in_playlist", "skip_download": True}
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(f"ytsearch{limit}:{query}", download=False)
    results = []
    for entry in info.get("entries") or []:
        if not entry or not entry.get("id"):
            continue
        channel = entry.get("channel") or entry.get("uploader") or ""
        results.append(
            {
                "kind": "song",
                "id": entry["id"],
                "title": entry.get("title") or entry["id"],
                "artist": channel.removesuffix(" - Topic"),
                "album": None,
                "duration": entry.get("duration"),
                "thumbnail": thumbnail_for(entry),
                "year": None,
                "official": channel.endswith(" - Topic"),
            }
        )
    # sort è stabile: tra i brani ufficiali e tra i video resta l'ordine di YouTube.
    results.sort(key=lambda r: not r.pop("official"))
    return results


def collection_id(source: str) -> str:
    """Da un link (playlist, album, browse) o da un id restituisce l'id di album o playlist."""
    source = source.strip()
    if source.startswith("http"):
        url = urlparse(source)
        host = (url.hostname or "").lower()
        if not (host == "youtu.be" or host == "youtube.com" or host.endswith(".youtube.com")):
            raise ValueError("Serve un link YouTube")
        playlist = parse_qs(url.query).get("list")
        if playlist:
            return playlist[0]
        match = re.match(r"^/browse/([A-Za-z0-9_-]+)$", url.path)
        if match:
            return match.group(1)
        raise ValueError("Il link non contiene né una playlist né un album")
    if not re.match(r"^[A-Za-z0-9_-]{10,}$", source):
        raise ValueError("Id di album o playlist non valido")
    return source


def collection(source: str, client=None) -> dict:
    """I brani di un album (id MPREb_...) o di una playlist, con titolo, autore e copertina."""
    cid = collection_id(source)
    if cid.startswith("MPREb"):
        album = (client or default_client()).get_album(cid)
        cover = _cover(album)
        title = album.get("title") or ""
        tracks = [song_from_item(t, album=title, cover=cover) for t in album.get("tracks") or []]
        return {
            "kind": "album",
            "id": cid,
            "title": title,
            "artist": _artists(album.get("artists")),
            "year": _year(album.get("year")),
            "thumbnail": cover,
            "tracks": [t for t in tracks if t],
        }
    try:
        playlist = (client or default_client()).get_playlist(cid, limit=None)
    except Exception:
        return _collection_with_ytdlp(cid)
    cover = _cover(playlist)
    tracks = [song_from_item(t) for t in playlist.get("tracks") or []]
    # Le playlist "OLAK5uy_" sono gli album visti come playlist.
    return {
        "kind": "album" if cid.startswith("OLAK5uy_") else "playlist",
        "id": cid,
        "title": playlist.get("title") or "",
        "artist": _artists(playlist.get("author")),
        "year": _year(playlist.get("year")),
        "thumbnail": cover,
        "tracks": [t for t in tracks if t],
    }


def _collection_with_ytdlp(playlist_id: str) -> dict:
    opts = {"quiet": True, "no_warnings": True, "extract_flat": "in_playlist", "skip_download": True}
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(f"https://www.youtube.com/playlist?list={playlist_id}", download=False)
    tracks = []
    for entry in info.get("entries") or []:
        if entry and entry.get("id"):
            tracks.append(
                {
                    "kind": "song",
                    "id": entry["id"],
                    "title": entry.get("title") or entry["id"],
                    "artist": (entry.get("channel") or entry.get("uploader") or "").removesuffix(" - Topic"),
                    "album": None,
                    "duration": entry.get("duration"),
                    "thumbnail": thumbnail_for(entry),
                    "year": None,
                }
            )
    return {
        "kind": "playlist",
        "id": playlist_id,
        "title": info.get("title") or "",
        "artist": info.get("channel") or info.get("uploader") or "",
        "year": None,
        "thumbnail": thumbnail_for(info) if info.get("thumbnails") else (tracks[0]["thumbnail"] if tracks else None),
        "tracks": tracks,
    }


def song_artists(video_id: str, client=None) -> list[str]:
    """Gli artisti principali di un brano secondo YouTube Music (dalla coda "Prossimi")."""
    playlist = (client or default_client()).get_watch_playlist(videoId=video_id, limit=1)
    for track in playlist.get("tracks") or []:
        if track.get("videoId") == video_id:
            return _artist_list(track.get("artists"))
    return []


def _release(item: dict, artist: str, default_type: str) -> dict | None:
    if not item.get("browseId"):
        return None
    return {
        "kind": "album",
        "id": item["browseId"],
        "title": item.get("title") or "",
        "artist": artist,
        "artists": [artist] if artist else [],
        "type": item.get("type") or default_type,
        "year": _year(item.get("year")),
        "thumbnail": _cover(item),
    }


def discography(name: str, client=None) -> dict:
    """Album, singoli ed EP di un artista, cercato per nome su YouTube Music."""
    client = client or default_client()
    found = [a for a in client.search(name, filter="artists", limit=10) if a.get("browseId")]
    if not found:
        raise LookupError("Artista non trovato su YouTube Music")
    wanted = name.strip().lower()
    best = next((a for a in found if (a.get("artist") or "").strip().lower() == wanted), found[0])
    page = client.get_artist(best["browseId"])
    artist = page.get("name") or best.get("artist") or name

    def releases(key: str, default_type: str) -> list[dict]:
        shelf = page.get(key) or {}
        items = shelf.get("results") or []
        if shelf.get("browseId") and shelf.get("params"):
            try:
                items = client.get_artist_albums(shelf["browseId"], shelf["params"], limit=None) or items
            except Exception:
                pass
        return [r for r in (_release(i, artist, default_type) for i in items) if r]

    return {
        "id": best["browseId"],
        "name": artist,
        "thumbnail": _cover(page),
        "albums": releases("albums", "Album"),
        "singles": releases("singles", "Single"),
    }

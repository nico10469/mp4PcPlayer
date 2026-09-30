"""API HTTP del server di mp4PcPlayer.

Avvio:  uvicorn mp4server.main:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel

from . import downloader as dl
from . import music
from .library import Library

MEDIA_TYPES = {"m4a": "audio/mp4", "mp4": "audio/mp4", "webm": "audio/webm", "opus": "audio/ogg", "mp3": "audio/mpeg"}


class DownloadRequest(BaseModel):
    source: str
    # Facoltativi, dalla ricerca su YouTube Music: copertina quadrata e album.
    cover: str | None = None
    album: str | None = None
    album_artist: str | None = None

    def hints(self) -> dict:
        cover = self.cover if self.cover and self.cover.startswith("https://") else None
        return {"cover": cover, "album": self.album, "album_artist": self.album_artist}


def create_app(library_dir: Path | None = None, token: str | None = None, fetch=None, music_client=None) -> FastAPI:
    library = Library(library_dir or Path(os.environ.get("MP4_LIBRARY", "library")))
    downloader = dl.Downloader(library, fetch=fetch or dl.default_fetch)
    token = token if token is not None else os.environ.get("MP4_TOKEN")

    def check_token(authorization: str | None = Header(default=None)) -> None:
        if token and authorization != f"Bearer {token}":
            raise HTTPException(status_code=401, detail="Token mancante o errato")

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        yield
        downloader.shutdown()

    app = FastAPI(title="mp4PcPlayer server", dependencies=[Depends(check_token)], lifespan=lifespan)
    app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
    app.state.library = library
    app.state.downloader = downloader

    @app.get("/health")
    def health() -> dict:
        return {"ok": True, "yt_dlp": dl.yt_dlp.version.__version__}

    @app.get("/search")
    async def search(
        q: str = Query(min_length=1),
        kind: str = Query("songs", pattern="^(songs|albums|playlists)$"),
        limit: int = Query(20, ge=1, le=50),
    ) -> list[dict]:
        """Brani (le art track di YouTube Music, con la sola copertina), album o playlist."""
        try:
            return await run_in_threadpool(music.search, q, kind, limit, music_client)
        except Exception as exc:
            raise HTTPException(status_code=502, detail=f"Ricerca fallita: {exc}")

    @app.get("/collection")
    async def collection(source: str = Query(min_length=1)) -> dict:
        """I brani di un album o di una playlist (id, oppure link YouTube / YouTube Music)."""
        try:
            music.collection_id(source)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        try:
            return await run_in_threadpool(music.collection, source, music_client)
        except Exception as exc:
            raise HTTPException(status_code=502, detail=f"Album o playlist non disponibile: {exc}")

    @app.post("/downloads", status_code=202)
    def start_download(req: DownloadRequest) -> dict:
        try:
            job = downloader.submit(req.source, req.hints())
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        return job.to_json()

    @app.get("/downloads/{job_id}")
    def download_status(job_id: str) -> dict:
        job = downloader.get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail="Download non trovato")
        return job.to_json()

    @app.get("/tracks")
    def tracks() -> list[dict]:
        return [t.to_json() for t in library.all()]

    def find(track_id: str):
        track = library.get(track_id)
        if track is None:
            raise HTTPException(status_code=404, detail="Brano non trovato")
        return track

    @app.get("/tracks/{track_id}")
    def track(track_id: str) -> dict:
        return find(track_id).to_json()

    @app.get("/tracks/{track_id}/file")
    def track_file(track_id: str) -> FileResponse:
        t = find(track_id)
        ext = t.filename.rsplit(".", 1)[-1]
        # FileResponse gestisce le richieste Range, quindi si può anche fare streaming.
        return FileResponse(library.path_of(t), media_type=MEDIA_TYPES.get(ext, "application/octet-stream"), filename=t.filename)

    @app.delete("/tracks/{track_id}", status_code=204)
    def delete_track(track_id: str) -> None:
        if not library.remove(track_id):
            raise HTTPException(status_code=404, detail="Brano non trovato")

    return app


app = create_app()

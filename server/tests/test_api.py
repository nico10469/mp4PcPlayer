import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from mp4server import downloader as dl
from mp4server.main import create_app


def fake_fetch(url, out_dir: Path, on_progress):
    video_id = url.rsplit("=", 1)[-1]
    on_progress(0.5)
    (out_dir / f"{video_id}.m4a").write_bytes(b"0123456789")
    info = {"id": video_id, "title": "Video", "track": "Chandelier", "artist": "Sia", "duration": 216, "thumbnail": "https://x/y.jpg",
            "genres": ["Pop"], "release_date": "20140317", "webpage_url": f"https://www.youtube.com/watch?v={video_id}"}
    return info, f"{video_id}.m4a"


@pytest.fixture
def client(tmp_path):
    with TestClient(create_app(tmp_path, token="", fetch=fake_fetch)) as c:
        yield c


def wait_done(client, job_id):
    for _ in range(100):
        job = client.get(f"/downloads/{job_id}").json()
        if job["status"] in ("done", "error"):
            return job
        time.sleep(0.02)
    raise AssertionError("download bloccato")


def test_download_flow(client, tmp_path):
    r = client.post("/downloads", json={"source": "2vjPBrBU-TM"})
    assert r.status_code == 202
    job = wait_done(client, r.json()["id"])
    assert job["status"] == "done" and job["track_id"] == "2vjPBrBU-TM"

    tracks = client.get("/tracks").json()
    assert tracks == [
        {"id": "2vjPBrBU-TM", "title": "Chandelier", "artist": "Sia", "album": None, "duration": 216,
         "thumbnail": "https://x/y.jpg", "added_at": tracks[0]["added_at"], "ext": "m4a",
         "album_artist": None, "genre": "Pop", "year": 2014,
         "source_url": "https://www.youtube.com/watch?v=2vjPBrBU-TM"}
    ]

    f = client.get("/tracks/2vjPBrBU-TM/file", headers={"Range": "bytes=2-4"})
    assert f.status_code == 206 and f.content == b"234"
    assert f.headers["content-type"] == "audio/mp4"

    assert client.delete("/tracks/2vjPBrBU-TM").status_code == 204
    assert client.get("/tracks").json() == []
    assert not (tmp_path / "2vjPBrBU-TM.m4a").exists()


def test_library_survives_restart(tmp_path):
    with TestClient(create_app(tmp_path, token="", fetch=fake_fetch)) as c:
        wait_done(c, c.post("/downloads", json={"source": "https://youtu.be/?v=2vjPBrBU-TM"}).json()["id"])
    with TestClient(create_app(tmp_path, token="", fetch=fake_fetch)) as c:
        assert [t["id"] for t in c.get("/tracks").json()] == ["2vjPBrBU-TM"]


def test_rejects_non_youtube(client):
    assert client.post("/downloads", json={"source": "https://evil.example/x"}).status_code == 400
    assert client.post("/downloads", json={"source": "file:///etc/passwd"}).status_code == 400


def test_failed_download_reports_error(tmp_path):
    def boom(*_):
        raise RuntimeError("Video unavailable")

    with TestClient(create_app(tmp_path, token="", fetch=boom)) as c:
        job = wait_done(c, c.post("/downloads", json={"source": "2vjPBrBU-TM"}).json()["id"])
    assert job["status"] == "error" and "unavailable" in job["error"]


def test_token_required(tmp_path):
    with TestClient(create_app(tmp_path, token="segreto", fetch=fake_fetch)) as c:
        assert c.get("/tracks").status_code == 401
        assert c.get("/tracks", headers={"Authorization": "Bearer segreto"}).status_code == 200


def test_search_maps_entries(client, monkeypatch):
    class FakeYDL:
        def __init__(self, opts): pass
        def __enter__(self): return self
        def __exit__(self, *a): pass
        def extract_info(self, q, download):
            assert q == "ytsearch15:sia"
            return {"entries": [{"id": "2vjPBrBU-TM", "title": "Sia - Chandelier", "channel": "SiaVEVO", "duration": 240.0, "thumbnails": []}, None]}

    monkeypatch.setattr(dl.yt_dlp, "YoutubeDL", FakeYDL)
    assert client.get("/search", params={"q": "sia"}).json() == [
        {"id": "2vjPBrBU-TM", "title": "Sia - Chandelier", "artist": "SiaVEVO", "duration": 240.0,
         "thumbnail": "https://i.ytimg.com/vi/2vjPBrBU-TM/hqdefault.jpg"}
    ]


def test_old_index_without_new_fields_loads(tmp_path):
    (tmp_path / "abc.m4a").write_bytes(b"x")
    old = {"abc": {"id": "abc", "title": "T", "artist": "A", "album": None, "duration": 1.0,
                   "thumbnail": None, "filename": "abc.m4a", "added_at": 1.0}}
    (tmp_path / "index.json").write_text(__import__("json").dumps(old), encoding="utf-8")
    with TestClient(create_app(tmp_path, token="", fetch=fake_fetch)) as c:
        track = c.get("/tracks/abc").json()
    assert track["genre"] is None and track["year"] is None

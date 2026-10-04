import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from mp4server import music
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
         "source_url": "https://www.youtube.com/watch?v=2vjPBrBU-TM", "artists": ["Sia"]}
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


class FakeMusic:
    """Risposte ridotte di ytmusicapi, con la stessa forma di quelle vere."""

    def __init__(self, fail=False):
        self.fail = fail

    def search(self, query, filter, limit):
        if self.fail:
            raise RuntimeError("YouTube Music non risponde")
        thumbs = [{"url": "https://lh3.googleusercontent.com/abc=w60-h60-l90-rj"},
                  {"url": "https://lh3.googleusercontent.com/abc=w120-h120-l90-rj"}]
        return {
            "artists": [
                {"resultType": "artist", "artist": "Sia Furler Tribute", "browseId": "UCother"},
                {"resultType": "artist", "artist": "Sia", "browseId": "UCsia"},
            ],
            "songs": [
                {"resultType": "song", "title": "Chandelier", "videoId": "2vjPBrBU-TM", "artists": [{"name": "Sia", "id": "x"}],
                 "album": {"name": "1000 Forms of Fear", "id": "MPREb_1"}, "duration_seconds": 216, "thumbnails": thumbs,
                 "isAvailable": True},
                {"resultType": "song", "title": "Grigio", "videoId": "zzzzzzzzzzz", "artists": [], "isAvailable": False},
            ],
            "albums": [
                {"resultType": "album", "title": "1000 Forms of Fear", "type": "Album", "year": "2014",
                 "artists": [{"name": "Sia"}], "browseId": "MPREb_1", "thumbnails": thumbs},
            ],
            "playlists": [
                {"resultType": "playlist", "title": "Pop hits", "itemCount": 50, "author": "YouTube Music",
                 "browseId": "VLPL123456789", "thumbnails": thumbs},
            ],
        }[filter]

    def get_watch_playlist(self, videoId, limit):
        return {"tracks": [{"videoId": videoId, "title": "Get Lucky",
                            "artists": [{"name": "Daft Punk"}, {"name": "Pharrell Williams"}, {"name": "Nile Rodgers"}]}]}

    def get_artist(self, channel_id):
        assert channel_id == "UCsia"
        return {"name": "Sia", "thumbnails": [],
                "albums": {"browseId": "UCsia", "params": "albums",
                           "results": [{"title": "Solo il primo", "browseId": "MPREb_0", "year": "2010"}]},
                "singles": {"browseId": None,
                            "results": [{"title": "Snowman", "type": "Single", "year": "2017", "browseId": "MPREb_9"}]}}

    def get_artist_albums(self, channel_id, params, limit):
        assert (channel_id, params) == ("UCsia", "albums")
        return [{"title": "1000 Forms of Fear", "type": "Album", "year": "2014", "browseId": "MPREb_1",
                 "thumbnails": [{"url": "https://lh3.googleusercontent.com/a=w226-h226-l90-rj"}]},
                {"title": "This Is Acting", "type": "Album", "year": "2016", "browseId": "MPREb_2"}]

    def get_album(self, browse_id):
        assert browse_id == "MPREb_1"
        return {"title": "1000 Forms of Fear", "artists": [{"name": "Sia"}], "year": "2014",
                "thumbnails": [{"url": "https://lh3.googleusercontent.com/cov=w544-h544-l90-rj"}],
                "tracks": [{"videoId": "2vjPBrBU-TM", "title": "Chandelier", "artists": [{"name": "Sia"}],
                            "album": "1000 Forms of Fear", "duration_seconds": 216, "thumbnails": None}]}

    def get_playlist(self, playlist_id, limit):
        assert playlist_id == "PL123456789"
        return {"title": "Pop hits", "author": {"name": "YouTube Music", "id": None}, "thumbnails": [],
                "tracks": [{"videoId": "2vjPBrBU-TM", "title": "Chandelier", "artists": [{"name": "Sia"}],
                            "album": {"name": "1000 Forms of Fear"}, "duration_seconds": 216,
                            "thumbnails": [{"url": "https://i.ytimg.com/vi/2vjPBrBU-TM/sddefault.jpg"}]}]}


@pytest.fixture
def music_client(tmp_path):
    with TestClient(create_app(tmp_path, token="", fetch=fake_fetch, music_client=FakeMusic())) as c:
        yield c


def test_search_songs_from_youtube_music(music_client):
    assert music_client.get("/search", params={"q": "sia"}).json() == [
        {"kind": "song", "id": "2vjPBrBU-TM", "title": "Chandelier", "artist": "Sia", "artists": ["Sia"],
         "album": "1000 Forms of Fear",
         "duration": 216, "thumbnail": "https://lh3.googleusercontent.com/abc=w544-h544-l90-rj", "year": None}
    ]


def test_search_albums_and_playlists(music_client):
    albums = music_client.get("/search", params={"q": "sia", "kind": "albums"}).json()
    assert albums == [{"kind": "album", "id": "MPREb_1", "title": "1000 Forms of Fear", "artist": "Sia",
                       "artists": ["Sia"], "type": "Album",
                       "year": 2014, "thumbnail": "https://lh3.googleusercontent.com/abc=w544-h544-l90-rj"}]
    playlists = music_client.get("/search", params={"q": "pop", "kind": "playlists"}).json()
    assert playlists[0]["id"] == "PL123456789" and playlists[0]["count"] == 50
    assert music_client.get("/search", params={"q": "x", "kind": "videos"}).status_code == 422


def test_album_and_playlist_tracks(music_client):
    album = music_client.get("/collection", params={"source": "https://music.youtube.com/browse/MPREb_1"}).json()
    assert album["kind"] == "album" and album["title"] == "1000 Forms of Fear" and album["artist"] == "Sia"
    # Le tracce degli album non hanno una copertina propria: prendono quella dell'album.
    assert album["tracks"][0]["thumbnail"] == "https://lh3.googleusercontent.com/cov=w544-h544-l90-rj"

    playlist = music_client.get("/collection", params={"source": "https://www.youtube.com/watch?v=2vjPBrBU-TM&list=PL123456789"}).json()
    assert playlist["kind"] == "playlist" and playlist["artist"] == "YouTube Music"
    assert [t["id"] for t in playlist["tracks"]] == ["2vjPBrBU-TM"]

    assert music_client.get("/collection", params={"source": "https://evil.example/?list=PL1"}).status_code == 400


def test_download_uses_square_cover_and_album(music_client):
    r = music_client.post("/downloads", json={"source": "2vjPBrBU-TM", "cover": "https://lh3.googleusercontent.com/cov",
                                              "album": "1000 Forms of Fear", "album_artist": "Sia"})
    wait_done(music_client, r.json()["id"])
    track = music_client.get("/tracks/2vjPBrBU-TM").json()
    assert track["thumbnail"] == "https://lh3.googleusercontent.com/cov"
    assert track["album"] == "1000 Forms of Fear" and track["album_artist"] == "Sia"


def test_song_search_falls_back_to_youtube_with_topic_first(tmp_path, monkeypatch):
    class FakeYDL:
        def __init__(self, opts): pass
        def __enter__(self): return self
        def __exit__(self, *a): pass
        def extract_info(self, q, download):
            assert q == "ytsearch20:sia"
            return {"entries": [
                {"id": "video000001", "title": "Sia - Chandelier (Official Video)", "channel": "SiaVEVO", "duration": 240.0, "thumbnails": []},
                None,
                {"id": "2vjPBrBU-TM", "title": "Chandelier", "channel": "Sia - Topic", "duration": 216.0, "thumbnails": []},
            ]}

    monkeypatch.setattr(music.yt_dlp, "YoutubeDL", FakeYDL)
    with TestClient(create_app(tmp_path, token="", fetch=fake_fetch, music_client=FakeMusic(fail=True))) as c:
        results = c.get("/search", params={"q": "sia"}).json()
    assert [(r["id"], r["artist"]) for r in results] == [("2vjPBrBU-TM", "Sia"), ("video000001", "SiaVEVO")]


def test_old_index_without_new_fields_loads(tmp_path):
    (tmp_path / "abc.m4a").write_bytes(b"x")
    old = {"abc": {"id": "abc", "title": "T", "artist": "A", "album": None, "duration": 1.0,
                   "thumbnail": None, "filename": "abc.m4a", "added_at": 1.0}}
    (tmp_path / "index.json").write_text(__import__("json").dumps(old), encoding="utf-8")
    with TestClient(create_app(tmp_path, token="", fetch=fake_fetch)) as c:
        track = c.get("/tracks/abc").json()
    assert track["genre"] is None and track["year"] is None


def featuring_fetch(url, out_dir: Path, on_progress):
    """yt-dlp legge gli artisti dalla descrizione "Brano · A · B · C", autori e produttori compresi."""
    video_id = url.rsplit("=", 1)[-1]
    (out_dir / f"{video_id}.m4a").write_bytes(b"x")
    info = {"id": video_id, "title": "Get Lucky (feat. Pharrell Williams and Nile Rodgers)",
            "artists": ["Daft Punk", "Pharrell Williams", "Nile Rodgers", "Thomas Bangalter", "Guy-Manuel de Homem-Christo"],
            "artist": "Daft Punk, Pharrell Williams, Nile Rodgers, Thomas Bangalter, Guy-Manuel de Homem-Christo"}
    return info, f"{video_id}.m4a"


def test_download_keeps_only_main_artists(tmp_path):
    # Con i dati della ricerca vincono gli artisti di YouTube Music.
    with TestClient(create_app(tmp_path / "a", token="", fetch=featuring_fetch, music_client=FakeMusic(fail=True))) as c:
        wait_done(c, c.post("/downloads", json={"source": "5NV6Rdv1a3I", "artists": ["Daft Punk", "Pharrell Williams"]}).json()["id"])
        track = c.get("/tracks/5NV6Rdv1a3I").json()
    assert track["artists"] == ["Daft Punk", "Pharrell Williams"] and track["artist"] == "Daft Punk, Pharrell Williams"

    # Un link senza dati: si chiedono a YouTube Music.
    with TestClient(create_app(tmp_path / "b", token="", fetch=featuring_fetch, music_client=FakeMusic())) as c:
        wait_done(c, c.post("/downloads", json={"source": "5NV6Rdv1a3I"}).json()["id"])
        track = c.get("/tracks/5NV6Rdv1a3I").json()
    assert track["artists"] == ["Daft Punk", "Pharrell Williams", "Nile Rodgers"]

    # YouTube Music non risponde: il primo artista e gli ospiti scritti nel titolo.
    class NoWatch(FakeMusic):
        def get_watch_playlist(self, videoId, limit):
            raise RuntimeError("offline")

    with TestClient(create_app(tmp_path / "c", token="", fetch=featuring_fetch, music_client=NoWatch())) as c:
        wait_done(c, c.post("/downloads", json={"source": "5NV6Rdv1a3I"}).json()["id"])
        track = c.get("/tracks/5NV6Rdv1a3I").json()
    assert track["artists"] == ["Daft Punk", "Pharrell Williams", "Nile Rodgers"]


def test_artist_discography(music_client):
    d = music_client.get("/artist", params={"name": "sia"}).json()
    assert d["id"] == "UCsia" and d["name"] == "Sia"
    # L'elenco completo degli album sostituisce i pochi della pagina dell'artista.
    assert [(a["id"], a["title"], a["year"], a["type"]) for a in d["albums"]] == [
        ("MPREb_1", "1000 Forms of Fear", 2014, "Album"), ("MPREb_2", "This Is Acting", 2016, "Album")]
    assert d["albums"][0]["thumbnail"] == "https://lh3.googleusercontent.com/a=w544-h544-l90-rj"
    assert [(s["id"], s["type"]) for s in d["singles"]] == [("MPREb_9", "Single")]


def test_artist_not_found(tmp_path):
    class NoArtists(FakeMusic):
        def search(self, query, filter, limit):
            return [] if filter == "artists" else super().search(query, filter, limit)

    with TestClient(create_app(tmp_path, token="", fetch=fake_fetch, music_client=NoArtists())) as c:
        assert c.get("/artist", params={"name": "nessuno"}).status_code == 404

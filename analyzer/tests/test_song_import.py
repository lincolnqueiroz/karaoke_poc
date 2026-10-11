import json
from pathlib import Path

import pytest

from karaoke_analyzer import song_import


@pytest.fixture
def setup(tmp_path, monkeypatch):
    workspace = tmp_path / "workspace"
    monkeypatch.setattr(song_import, "WORKSPACE", workspace)
    monkeypatch.setattr(song_import.shutil, "which", lambda name: name)
    source = tmp_path / "Minha música & teste.mp3"
    source.write_bytes(b"original untouched")

    def fake_analyze(source, output, separate, device, progress):
        progress(0.6, "Pitch")
        (output / "original.mp3").write_bytes(source.read_bytes())
        manifest = output / "song.json"
        manifest.write_text('{"schema_version":"1.0"}', encoding="utf-8")
        return manifest

    monkeypatch.setattr(song_import, "analyze", fake_analyze)
    return source, workspace / "songs", workspace / "status.json"


def test_import_preserves_inputs_and_does_not_overwrite(setup, tmp_path):
    source, root, status = setup
    lyrics = tmp_path / "verses.lrc"
    lyrics.write_text("[00:01] Verso", encoding="utf-8")
    first = song_import.import_song(source, root, status, lyrics, separate=False)
    second = song_import.import_song(source, root, status, lyrics, separate=False)
    assert first != second and first.is_file() and second.is_file()
    assert source.read_bytes() == b"original untouched"
    assert next(first.parent.glob("lyrics/*.lrc")).read_text() == "[00:01] Verso"
    assert json.loads(status.read_text())["state"] == "complete"


def test_import_title_and_optional_artist_do_not_change_schema(setup):
    source, root, status = setup
    manifest = song_import.import_song(source, root, status, separate=False,
                                     title="  Título da música  ", artist="  Artista  ")
    data = json.loads(manifest.read_text(encoding="utf-8"))
    assert data["title"] == "Título da música"
    assert data["schema_version"] == "1.0" and "artist" not in data
    assert json.loads((manifest.parent / "metadata.json").read_text(encoding="utf-8")) == {"artist": "Artista"}
    assert source.read_bytes() == b"original untouched"


@pytest.mark.parametrize("title", ["", "  ", "x" * 201])
def test_rejects_invalid_explicit_title_before_analysis(setup, title):
    source, root, status = setup
    with pytest.raises(ValueError, match="título|Título"):
        song_import.import_song(source, root, status, separate=False, title=title)
    assert not root.exists()


def test_failure_never_publishes_partial_song(setup, monkeypatch):
    source, root, status = setup

    def fail(*args, **kwargs):
        raise RuntimeError("Demucs failed")

    monkeypatch.setattr(song_import, "analyze", fail)
    with pytest.raises(RuntimeError, match="Demucs failed"):
        song_import.import_song(source, root, status, separate=False)
    assert not root.exists()
    assert json.loads(status.read_text())["state"] == "error"


def test_rejects_missing_input_and_ffmpeg(setup, monkeypatch):
    source, root, status = setup
    with pytest.raises(ValueError, match="MP3"):
        song_import.import_song(Path("missing.mp3"), root, status, separate=False)
    monkeypatch.setattr(song_import.shutil, "which", lambda name: None)
    with pytest.raises(RuntimeError, match="FFmpeg"):
        song_import.import_song(source, root, status, separate=False)


def test_outputs_cannot_escape_workspace(setup, tmp_path):
    source, _root, status = setup
    with pytest.raises(ValueError, match="workspace"):
        song_import.import_song(source, tmp_path / "outside", status, separate=False)


def test_packaged_import_uses_user_data_and_bundled_dependencies(setup, tmp_path, monkeypatch):
    source, _, _ = setup
    installation = tmp_path / "installation"
    weights = installation / "models/torch/hub/checkpoints/model.th"
    weights.parent.mkdir(parents=True)
    weights.write_bytes(b"cached weights")
    (installation / "tools/ffmpeg").mkdir(parents=True)
    monkeypatch.setattr(song_import, "packaged", lambda: True)
    monkeypatch.setattr(song_import, "bundle_root", lambda: installation)
    monkeypatch.setenv("TORCH_HOME", "previous-cache")
    monkeypatch.setenv("HF_HOME", "previous-hf-cache")
    storage = tmp_path / "user data"
    manifest = song_import.import_song(source, storage / "songs", storage / "job.json",
                                     separate=False, storage_root=storage)
    assert manifest.is_relative_to(storage)
    assert (storage / "models/torch/hub/checkpoints/model.th").read_bytes() == b"cached weights"
    assert song_import.os.environ["TORCH_HOME"] == "previous-cache"
    assert song_import.os.environ["HF_HOME"] == "previous-hf-cache"


def test_status_cannot_overwrite_source(setup):
    _, root, status = setup
    source = status.parent / "input.mp3"
    source.parent.mkdir(parents=True, exist_ok=True)
    source.write_bytes(b"keep")
    with pytest.raises(ValueError, match="sobrescrever"):
        song_import.import_song(source, root, source, separate=False)
    assert source.read_bytes() == b"keep"


def test_status_retries_transient_windows_reader_lock(tmp_path, monkeypatch):
    replace = Path.replace
    calls = []

    def locked_twice(source, destination):
        calls.append(destination)
        if len(calls) < 3:
            raise PermissionError("Reader temporarily holds status file")
        return replace(source, destination)

    monkeypatch.setattr(Path, "replace", locked_twice)
    monkeypatch.setattr(song_import.time, "sleep", lambda seconds: None)
    status = tmp_path / "status.json"
    song_import.write_status(status, "running", 0.5, "Analyzing")
    assert len(calls) == 3 and json.loads(status.read_text())["progress"] == 0.5

import subprocess
from pathlib import Path

import pytest

from karaoke_analyzer import youtube


@pytest.fixture
def prepared(tmp_path, monkeypatch):
    monkeypatch.setattr(youtube, "WORKSPACE", tmp_path)
    monkeypatch.setattr(youtube.shutil, "which", lambda *a, **kw: "tool.exe")
    monkeypatch.setattr(youtube.importlib.util, "find_spec", lambda name: object())
    return tmp_path / "song.mp3"


def test_download(prepared, monkeypatch):
    def run(command, check):
        assert check
        assert "--no-playlist" in command
        template = command[command.index("-o") + 1]
        Path(template.replace("%(ext)s", "mp3")).write_bytes(b"fake audio")

    monkeypatch.setattr(youtube.subprocess, "run", run)
    assert youtube.download_audio("https://youtu.be/example", prepared) == prepared
    assert prepared.read_bytes() == b"fake audio"


def test_preserves_existing_file(prepared):
    prepared.write_bytes(b"original")
    with pytest.raises(FileExistsError):
        youtube.download_audio("https://youtu.be/example", prepared)
    assert prepared.read_bytes() == b"original"


@pytest.mark.parametrize("url", ["http://youtu.be/example", "https://youtube.com.evil/x"])
def test_rejects_other_urls(prepared, url):
    with pytest.raises(ValueError):
        youtube.download_audio(url, prepared)


def test_rejects_output_outside_workspace(prepared):
    with pytest.raises(ValueError):
        youtube.download_audio("https://youtu.be/example", prepared.parent.parent / "song.mp3")


def test_failed_download(prepared, monkeypatch):
    def run(command, check):
        raise subprocess.CalledProcessError(1, command)

    monkeypatch.setattr(youtube.subprocess, "run", run)
    with pytest.raises(RuntimeError, match="exit code 1"):
        youtube.download_audio("https://youtu.be/example", prepared)
    assert not prepared.exists()


def test_missing_ffmpeg(prepared, monkeypatch):
    monkeypatch.setattr(youtube.shutil, "which", lambda *a, **kw: None)
    with pytest.raises(RuntimeError, match="ffmpeg not found"):
        youtube.download_audio("https://youtu.be/example", prepared)


def test_missing_result(prepared, monkeypatch):
    monkeypatch.setattr(youtube.subprocess, "run", lambda *a, **kw: None)
    with pytest.raises(RuntimeError, match="nonempty MP3"):
        youtube.download_audio("https://youtu.be/example", prepared)

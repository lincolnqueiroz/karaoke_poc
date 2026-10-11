import sys
from pathlib import Path

import pytest

from karaoke_analyzer import runtime, song_import


def test_frozen_child_uses_executable_dispatch(monkeypatch):
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setattr(sys, "executable", "C:/Karaoke/analyzer/karaoke-analyzer.exe")
    assert runtime.demucs_command() == [sys.executable, "--demucs"]
    assert runtime.bundle_root() == Path(sys.executable).resolve().parent.parent


def test_source_child_preserves_offline_policy(monkeypatch):
    monkeypatch.setenv("KARAOKE_OFFLINE_MODELS", "1")
    assert runtime.demucs_command()[1:] == ["-m", "karaoke_analyzer.demucs_runner"]
    monkeypatch.setenv("KARAOKE_OFFLINE_MODELS", "0")
    assert runtime.demucs_command()[1:] == ["-m", "demucs"]


def test_production_data_not_relative_to_installation(monkeypatch, tmp_path):
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path))
    assert runtime.data_root() == tmp_path / "KaraokePoC"


def test_explicit_data_root_still_rejects_escaping_outputs(tmp_path):
    with pytest.raises(ValueError, match="workspace"):
        song_import.import_song(tmp_path / "source.mp3", tmp_path / "outside",
                              tmp_path / "data/status.json", storage_root=tmp_path / "data")

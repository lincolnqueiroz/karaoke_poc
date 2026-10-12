import json

import pytest

from karaoke_analyzer.exporter import export_song


def test_manifest(tmp_path):
    path = export_song(tmp_path / "song.json", "Test", 2.0, {"original": "original.mp3"},
                       [{"start": 0.1, "duration": 0.2, "midi": 60, "confidence": 1.0}])
    assert json.loads(path.read_text(encoding="utf-8"))["schema_version"] == "1.0"


def test_invalid_note(tmp_path):
    with pytest.raises(ValueError):
        export_song(tmp_path / "song.json", "Test", 1.0, {},
                    [{"start": 2.0, "duration": 0.5, "midi": 60, "confidence": 1.0}])

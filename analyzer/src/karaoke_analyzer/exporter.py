"""Versioned manifest export."""
import json
from pathlib import Path


def export_song(path: Path, title: str, duration: float, audio: dict, notes: list) -> Path:
    if duration <= 0:
        raise ValueError("Duration must be positive")
    for note in notes:
        if not (0 <= note["start"] and note["duration"] > 0 and
                note["start"] + note["duration"] <= duration + 0.05 and
                0 <= note["midi"] <= 127 and 0 <= note["confidence"] <= 1):
            raise ValueError(f"Invalid note: {note}")
    data = {"schema_version": "1.0", "title": title, "duration_seconds": round(duration, 4),
            "audio": audio, "notes": notes}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    return path

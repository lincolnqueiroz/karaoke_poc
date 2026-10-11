import csv
import json

import numpy as np
import pytest
import soundfile as sf

from karaoke_analyzer import pipeline


@pytest.fixture(autouse=True)
def isolated_secondary_pitch(monkeypatch):
    def secondary(path):
        times, f0, _, _ = pipeline.estimate_pitch(path)
        return times, np.full_like(f0, np.nan), np.zeros(len(f0), dtype=bool), np.zeros(len(f0))
    monkeypatch.setattr(pipeline, "estimate_secondary_pitch", secondary)


@pytest.mark.parametrize("amplitude, expected", [(0.1, [69]), (0.0001, [])])
def test_pipeline_uses_probability_and_exports_raw_diagnostics(
    tmp_path, monkeypatch, amplitude, expected,
):
    source = tmp_path / "input.mp3"
    source.write_bytes(b"fake mp3")

    def decode(source, destination):
        sf.write(str(destination), np.full(22050, amplitude), 22050)
        return destination

    monkeypatch.setattr(pipeline, "decode_to_wav", decode)
    monkeypatch.setattr(pipeline, "estimate_pitch", lambda path: (
        np.arange(100) * 0.01, np.array([440.] * 50 + [880.] * 50),
        np.ones(100, dtype=bool), np.array([0.9] * 50 + [0.01] * 50),
    ))
    output = tmp_path / "result"
    manifest = pipeline.analyze(source, output)
    data = json.loads(manifest.read_text(encoding="utf-8"))
    assert [n["midi"] for n in data["notes"]] == expected
    with (output / "pitch-debug.csv").open(encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == 100
    assert float(rows[-1]["f0_hz"]) == 880.0
    assert float(rows[-1]["voiced_probability"]) == 0.01
    assert (output / "activity-debug.csv").is_file()
    assert (output / "pitch-secondary-debug.csv").is_file()
    assert (output / "pitch-consensus-debug.csv").is_file()
    assert source.read_bytes() == b"fake mp3"


def test_separation_preserves_original_duration(tmp_path, monkeypatch):
    source = tmp_path / "input.mp3"
    source.write_bytes(b"fake")
    vocals = tmp_path / "vocals.wav"
    sf.write(str(vocals), np.zeros(11025), 22050)

    def decode(source, destination):
        sf.write(str(destination), np.zeros(44100), 22050)
        return destination

    monkeypatch.setattr(pipeline, "decode_to_wav", decode)
    monkeypatch.setattr(pipeline, "separate_vocals", lambda *args, **kwargs: vocals)
    monkeypatch.setattr(pipeline, "estimate_pitch", lambda path: (
        np.array([]), np.array([]), np.array([], dtype=bool), np.array([])))
    manifest = pipeline.analyze(source, tmp_path / "result", separate=True)
    assert json.loads(manifest.read_text())["duration_seconds"] == 2.0


def test_notes_are_clipped_to_original_audio_end(tmp_path, monkeypatch):
    source = tmp_path / "input.mp3"
    source.write_bytes(b"fake")

    def decode(source, destination):
        sf.write(str(destination), np.zeros(22050), 22050)
        return destination

    monkeypatch.setattr(pipeline, "decode_to_wav", decode)
    monkeypatch.setattr(pipeline, "estimate_pitch", lambda path: (
        np.array([]), np.array([]), np.array([], dtype=bool), np.array([])))
    monkeypatch.setattr(pipeline, "segment_notes", lambda *args, **kwargs: [
        {"start": 0.5, "duration": 0.52, "midi": 69, "confidence": 1.0},
        {"start": 1.01, "duration": 0.2, "midi": 69, "confidence": 1.0},
    ])
    manifest = pipeline.analyze(source, tmp_path / "output")
    notes = json.loads(manifest.read_text())["notes"]
    assert len(notes) == 1 and notes[0]["duration"] == 0.5


def test_pipeline_uses_consensus_without_rewriting_primary_probability(tmp_path, monkeypatch):
    source = tmp_path / "input.mp3"
    source.write_bytes(b"fake")

    def decode(source, destination):
        sf.write(str(destination), np.full(22050, 0.1), 22050)
        return destination

    def track(path):
        return (np.arange(100) * 0.01, np.full(100, 110.0),
                np.ones(100, dtype=bool), np.full(100, 0.02))

    monkeypatch.setattr(pipeline, "decode_to_wav", decode)
    monkeypatch.setattr(pipeline, "estimate_pitch", track)
    monkeypatch.setattr(pipeline, "estimate_secondary_pitch", track)
    manifest = pipeline.analyze(source, tmp_path / "output")
    assert json.loads(manifest.read_text())["notes"][0]["duration"] == 1.0
    with (manifest.parent / "pitch-debug.csv").open() as handle:
        rows = list(csv.DictReader(handle))
    assert all(float(row["voiced_probability"]) == 0.02 for row in rows)
    with (manifest.parent / "pitch-consensus-debug.csv").open() as handle:
        support = list(csv.DictReader(handle))
    assert all(row["supported_by_both_windows"] == "True" for row in support)

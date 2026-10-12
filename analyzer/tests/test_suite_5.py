import json
from types import SimpleNamespace

import numpy as np
import pytest
import soundfile as sf

from karaoke_analyzer import pipeline
from karaoke_analyzer.suites.suite_5 import pipeline as suite
from karaoke_analyzer.suites.suite_5.leakage import harmonic_leakage, sustained_leakage


@pytest.mark.parametrize("vocal_gain,backing_frequency,expected", [
    (0.04, 220, True), (0.8, 220, False), (0.04, 317, False),
])
def test_real_harmonic_veto_requires_dominant_matching_accompaniment(
        tmp_path, vocal_gain, backing_frequency, expected):
    rate = 22050
    t = np.arange(rate) / rate

    def tone(frequency, gain):
        return gain * sum(np.sin(2 * np.pi * frequency * h * t) / h for h in range(1, 6))

    vocal = tmp_path / "vocals.wav"
    backing = tmp_path / "no_vocals.wav"
    sf.write(vocal, tone(220, vocal_gain), rate, subtype="FLOAT")
    sf.write(backing, tone(backing_frequency, 0.8), rate, subtype="FLOAT")
    times = np.arange(0.2, 0.8, 0.01)
    rejected, ratios, votes = harmonic_leakage(vocal, backing, times, np.full(len(times), 220))
    assert rejected.all() if expected else not rejected.any()
    # A common gain change must not change the decisions.
    for path in (vocal, backing):
        audio, sr = sf.read(path)
        sf.write(path, audio * 0.01, sr, subtype="FLOAT")
    scaled = harmonic_leakage(vocal, backing, times, np.full(len(times), 220))
    assert np.array_equal(rejected, scaled[0])
    assert np.allclose(ratios, scaled[1], atol=1e-4, equal_nan=True)
    assert np.array_equal(votes, scaled[2])


def test_short_evidence_and_timestamp_gaps_do_not_trigger_veto():
    t = np.r_[np.arange(0, 0.08, 0.01), np.arange(0.3, 0.38, 0.01)]
    assert not sustained_leakage(t, np.full(len(t), -20.0), np.full(len(t), 5)).any()


def test_missing_stem_duration_mismatch_and_invalid_times_fail(tmp_path):
    vocal, backing = tmp_path / "v.wav", tmp_path / "b.wav"
    sf.write(vocal, np.zeros(22050), 22050)
    sf.write(backing, np.zeros(100), 22050)
    with pytest.raises(ValueError, match="equal duration"):
        harmonic_leakage(vocal, backing, [0.1], [220])
    with pytest.raises(ValueError, match="timestamps"):
        harmonic_leakage(vocal, backing, [0.2, 0.1], [220, 220])


def test_veto_cannot_be_reintroduced_by_recovery_or_support(tmp_path, monkeypatch):
    source = tmp_path / "song.mp3"
    source.write_bytes(b"original")
    output = tmp_path / "output"
    vocals = tmp_path / "vocals.wav"
    vocals.with_name("no_vocals.wav").write_bytes(b"backing")
    monkeypatch.setattr(suite, "decode_to_wav", lambda *args: tmp_path / "decoded.wav")
    monkeypatch.setattr(suite, "separate_vocals", lambda *args, **kwargs: vocals)
    monkeypatch.setattr(suite, "harmonic_reference", lambda audio, destination: destination)
    times = np.arange(0, 1, 0.01)
    track = lambda *args, **kwargs: (times, np.full(100, 220.0), np.ones(100, bool), np.ones(100))
    monkeypatch.setattr(suite, "estimate_pitch", track)
    monkeypatch.setattr(suite, "estimate_secondary_pitch", track)
    monkeypatch.setattr(suite, "frame_rms_db", lambda audio, t: np.full(len(t), -15.0))
    monkeypatch.setattr(suite.sf, "info", lambda *args: SimpleNamespace(duration=1.0))
    rejected = times < 0.4
    monkeypatch.setattr(suite, "harmonic_leakage", lambda *args:
                        (rejected, np.full(100, -20.0), np.full(100, 5)))
    manifest = pipeline.analyze(source, output, separate=True, suite="suite_5")
    notes = json.loads(manifest.read_text())["notes"]
    assert notes and all(note["start"] >= 0.4 for note in notes)
    assert (output / "harmonic-leakage-debug.csv").is_file()
    assert (output / "pitch-debug.csv").is_file()
    assert '"suite_5"' in (output / "analysis-suite.json").read_text()
    assert source.read_bytes() == b"original"


def test_requires_separation_before_touching_outputs(tmp_path):
    with pytest.raises(ValueError, match="requires Demucs"):
        pipeline.analyze(tmp_path / "missing.mp3", tmp_path / "output", suite="suite_5")
    assert not (tmp_path / "output").exists()

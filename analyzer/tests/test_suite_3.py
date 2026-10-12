import json
from types import SimpleNamespace

import numpy as np
import pytest

from karaoke_analyzer import pipeline
from karaoke_analyzer.suites.suite_3 import pipeline as relative
from karaoke_analyzer.suites.suite_3.energy import relative_energy_floor


def test_relative_floor_uses_all_finite_frames_without_absolute_preselection():
    values = np.array([-90.0, -80.0, -70.0, -60.0, -np.inf, np.nan])
    reference, floor = relative_energy_floor(values)
    assert reference == pytest.approx(-63.0)
    assert floor == pytest.approx(-63.0 + 20 * np.log10(0.40))
    shifted_reference, shifted_floor = relative_energy_floor(values - 20)
    assert shifted_reference == pytest.approx(reference - 20)
    assert shifted_floor == pytest.approx(floor - 20)


def test_pipeline_preserves_notes_and_gates_under_gain_changes(tmp_path, monkeypatch):
    source = tmp_path / "song.mp3"
    source.write_bytes(b"original")
    times = np.arange(0, 2, 0.01)
    # A strong segment, a weaker recoverable segment, and a quiet residual.
    original_energy = np.r_[np.full(80, -20.0), np.full(80, -26.0), np.full(40, -65.0)]
    probability = np.r_[np.ones(80), np.full(80, 0.02), np.ones(40)]
    offset = [0.0]
    monkeypatch.setattr(relative, "decode_to_wav", lambda source, path: path)
    monkeypatch.setattr(relative, "separate_vocals", lambda *args, **kwargs: tmp_path / "vocals.wav")
    monkeypatch.setattr(relative.sf, "info", lambda *args: SimpleNamespace(duration=2.0))
    monkeypatch.setattr(relative, "frame_rms_db",
                        lambda audio, t: original_energy + offset[0])

    def pitch(audio, **kwargs):
        return times, np.full(200, 220.0), np.ones(200, dtype=bool), probability

    monkeypatch.setattr(relative, "estimate_pitch", pitch)
    monkeypatch.setattr(relative, "estimate_secondary_pitch", pitch)
    runs = []
    for index, gain in enumerate([0.0, -40.0, 10.0]):
        offset[0] = gain
        output = tmp_path / f"run_{index}"
        manifest = pipeline.analyze(source, output, separate=True, suite="suite_3")
        notes = json.loads(manifest.read_text())["notes"]
        threshold = json.loads((output / "energy-threshold-debug.json").read_text())
        assert threshold["floor_dbfs"] == pytest.approx(-20.0 + 20 * np.log10(0.40) + gain)
        assert threshold["rms_fraction"] == 0.40
        assert threshold["reference_dbfs"] == pytest.approx(-20.0 + gain)
        assert notes and max(n["start"] + n["duration"] for n in notes) > 1.5
        assert max(n["start"] + n["duration"] for n in notes) <= 1.61
        runs.append((notes, (output / "reference-debug.csv").read_text().splitlines(),
                     (output / "pitch-consensus-debug.csv").read_text()))
        assert '"suite_3"' in (output / "analysis-suite.json").read_text()
    assert runs[0] == runs[1] == runs[2]
    assert source.read_bytes() == b"original"


@pytest.mark.parametrize("values", [[], [-np.inf, -np.inf], [np.nan]])
def test_silent_energy_has_no_reference(values):
    assert relative_energy_floor(values)[0] is None


def test_fraction_is_linear_rms_and_rejects_previous_borderline_frames():
    energy = np.r_[np.full(100, -20.0), [-26.0, -29.0, -35.0]]
    reference, floor = relative_energy_floor(energy)
    assert 10 ** (floor / 20) == pytest.approx(0.40 * 10 ** (reference / 20))
    assert energy[-3] >= floor
    assert np.all(energy[-2:] < floor)
    assert np.all(energy[-2:] >= reference - 30)  # Accepted by revision 1.


def test_silent_pipeline_exports_no_notes_and_null_threshold(tmp_path, monkeypatch):
    source = tmp_path / "silent.mp3"
    source.write_bytes(b"original")
    times = np.arange(0, 1, 0.01)
    monkeypatch.setattr(relative, "decode_to_wav", lambda source, path: path)
    monkeypatch.setattr(relative.sf, "info", lambda *args: SimpleNamespace(duration=1.0))
    monkeypatch.setattr(relative, "frame_rms_db", lambda audio, t: np.full(len(t), -np.inf))
    track = lambda *args, **kwargs: (times, np.full(100, 220.0), np.ones(100, bool), np.ones(100))
    monkeypatch.setattr(relative, "estimate_pitch", track)
    monkeypatch.setattr(relative, "estimate_secondary_pitch", track)
    manifest = pipeline.analyze(source, tmp_path / "output", suite="suite_3")
    assert json.loads(manifest.read_text())["notes"] == []
    diagnostics = json.loads((manifest.parent / "energy-threshold-debug.json").read_text())
    assert diagnostics["reference_dbfs"] is None and diagnostics["floor_dbfs"] is None

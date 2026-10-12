import json
from types import SimpleNamespace

import numpy as np
import pytest

from karaoke_analyzer import pipeline
from karaoke_analyzer.suites.suite_8 import pipeline as suite
from karaoke_analyzer.suites.suite_8.postprocessing import postprocess_notes


def note(start, duration, midi=57):
    return {"start": start, "duration": duration, "midi": midi, "confidence": 1.0}


def evidence():
    t = np.arange(0, 2, 0.01)
    return [t, np.full(200, 220.0), np.full(200, 220.0), np.ones(200),
            np.ones(200), np.full(200, -20.0), np.ones(200), np.zeros(200, bool)]


def test_bridge_uses_raw_candidates_below_original_energy_cut_without_mutating_inputs():
    arrays = evidence()
    gap = (arrays[0] >= 0.5) & (arrays[0] < 0.7)
    arrays[5][gap] = -30  # Below suite 7's -25 floor; allowed only for a bounded bridge.
    arrays[6][gap] = 0
    notes = [note(0.1, 0.4), note(0.7, 0.4)]
    result, changes = postprocess_notes(notes, *arrays)
    assert result == [note(0.1, 1.0)]
    assert notes == [note(0.1, 0.4), note(0.7, 0.4)]
    assert changes[0]["action"] == "bridge"


@pytest.mark.parametrize("failure", ["silence", "no_pitch", "disagreement", "low_probability",
                                     "weak_anchors", "backing_dominant", "timestamp_gap"])
def test_bridge_rejects_insufficient_or_conflicting_evidence(failure):
    arrays = evidence()
    gap = (arrays[0] >= 0.5) & (arrays[0] < 0.7)
    mix = np.full(200, -20.0)
    if failure == "silence":
        arrays[5][gap] = -np.inf
    elif failure == "no_pitch":
        arrays[1][gap] = np.nan
    elif failure == "disagreement":
        arrays[2][gap] = 440
    elif failure == "low_probability":
        arrays[3][gap] = 0.001
    elif failure == "weak_anchors":
        arrays[6][:] = 0.02
    elif failure == "backing_dominant":
        mix[gap] = 10
    elif failure == "timestamp_gap":
        arrays = [a[~((arrays[0] > 0.55) & (arrays[0] < 0.65))] for a in arrays]
        mix = np.full(len(arrays[0]), -20.0)
    notes = [note(0.1, 0.4), note(0.7, 0.4)]
    result, changes = postprocess_notes(notes, *arrays, mixture_energy=mix)
    assert result == notes and changes == []


def test_never_fills_long_gaps_or_changes_legitimate_pitch_jump():
    arrays = evidence()
    notes = [note(0.1, 0.4), note(1.0, 0.4)]
    assert postprocess_notes(notes, *arrays)[0] == notes
    notes = [note(0.1, 0.4), note(0.7, 0.4, 69)]
    assert postprocess_notes(notes, *arrays)[0] == notes


def test_clean_only_weak_short_isolated_notes_and_returning_jumps():
    arrays = evidence()
    arrays[6][:] = 0.02
    isolated = [note(0.3, 0.12)]
    assert postprocess_notes(isolated, *arrays)[0] == []
    arrays[7][:] = True
    assert postprocess_notes(isolated, *arrays)[0] == isolated
    arrays[7][:] = False
    notes = [note(0.1, 0.4), note(0.5, 0.12, 69), note(0.62, 0.4)]
    result, changes = postprocess_notes(notes, *arrays)
    assert len(result) == 2 and all(n["midi"] == 57 for n in result)
    assert changes[0]["reason"] == "weak_returning_jump"
    # A short step inside a phrase is preserved.
    notes[1]["midi"] = 59
    assert postprocess_notes(notes, *arrays)[0] == notes


def test_invalid_note_order_is_explicit_error():
    with pytest.raises(ValueError, match="ordered"):
        postprocess_notes([note(1, 0.4), note(0.1, 0.4)], *evidence())


def test_absorbs_short_note_after_strong_long_note_even_at_different_pitch():
    notes = [note(0.1, 0.6), note(0.7, 0.15, 69), note(0.85, 0.4, 60)]
    result, changes = postprocess_notes(notes, *evidence())
    assert result == [note(0.1, 0.75), note(0.85, 0.4, 60)]
    assert changes[0]["action"] == "absorb_short"
    assert notes[0]["duration"] == 0.6


def test_absorption_does_not_chain_or_cross_silence():
    notes = [note(0.1, 0.6), note(0.7, 0.1, 69), note(0.8, 0.1, 60)]
    result, _ = postprocess_notes(notes, *evidence())
    assert result == [note(0.1, 0.7), note(0.8, 0.1, 60)]
    arrays = evidence()
    arrays[5][(arrays[0] >= 0.7) & (arrays[0] < 0.74)] = -np.inf
    notes = [note(0.1, 0.6), note(0.74, 0.1, 69)]
    assert postprocess_notes(notes, *arrays)[0] == notes


@pytest.mark.parametrize("long_duration,short_duration", [(0.39, 0.15), (0.4, 0.19)])
def test_absorption_respects_duration_limits(long_duration, short_duration):
    notes = [note(0.1, long_duration), note(0.1 + long_duration, short_duration, 69)]
    assert postprocess_notes(notes, *evidence())[0] == notes


def test_pipeline_exports_before_after_and_keeps_raw_diagnostics(tmp_path, monkeypatch):
    source = tmp_path / "song.mp3"
    source.write_bytes(b"original")
    output = tmp_path / "analysis"
    t = np.arange(0, 1, 0.01)
    monkeypatch.setattr(suite, "decode_to_wav", lambda source, path: path)
    monkeypatch.setattr(suite, "harmonic_reference", lambda source, destination: destination)
    track = lambda *args, **kwargs: (t, np.full(100, 220.0), np.ones(100, bool), np.ones(100))
    monkeypatch.setattr(suite, "estimate_pitch", track)
    monkeypatch.setattr(suite, "estimate_secondary_pitch", track)
    monkeypatch.setattr(suite, "frame_rms_db", lambda audio, times: np.full(len(times), -20.0))
    monkeypatch.setattr(suite.sf, "info", lambda *args: SimpleNamespace(duration=1.0))
    manifest = pipeline.analyze(source, output, suite="suite_8")
    before = json.loads((output / "notes-before-postprocess.json").read_text())["notes"]
    assert before == json.loads(manifest.read_text())["notes"]
    assert json.loads((output / "postprocess-debug.json").read_text())["changes"] == []
    assert (output / "pitch-candidates-debug.csv").is_file()
    assert '"suite_8"' in (output / "analysis-suite.json").read_text()
    assert source.read_bytes() == b"original"

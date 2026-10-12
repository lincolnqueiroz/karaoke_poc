import json
from types import SimpleNamespace

import numpy as np
import pytest

from karaoke_analyzer import pipeline
from karaoke_analyzer.suites.suite_1 import segmentation as baseline_segment
from karaoke_analyzer.suites.suite_4 import pipeline as baseline
from karaoke_analyzer.suites.suite_7 import pipeline as aggressive
from karaoke_analyzer.suites.suite_7.pitch_consensus import pitch_consensus
from karaoke_analyzer.suites.suite_7.pitch_recovery import recover_pitch
from karaoke_analyzer.suites.suite_7.reference_track import vocal_activity
from karaoke_analyzer.suites.suite_7.segmentation import segment_notes


@pytest.mark.parametrize("db,expected", [(-30.0, False), (-25.01, False), (-25.0, True), (-24.99, True)])
def test_all_energy_stages_use_same_absolute_boundary(db, expected):
    t = np.arange(0, 1, 0.01)
    f, v = np.full(100, 220.0), np.ones(100, bool)
    energy, probability = np.full(100, db), np.full(100, 0.02)
    probability[:20] = 1.0
    active = vocal_activity(energy)
    support, _ = pitch_consensus(t, f, v, probability, f, v, probability, energy)
    recovery = recover_pitch(t, f, v, probability, energy)
    notes = segment_notes(t, f, v, probability=probability, rms_db=energy,
                          support_mask=support, activity_mask=active)
    assert bool(active.all()) == expected
    assert bool(support.any()) == expected
    assert bool(recovery.any()) == expected
    assert bool(notes) == expected
    assert baseline_segment.segment_notes(t, f, v, probability=np.ones(100), rms_db=energy)


@pytest.mark.parametrize("separate", [False, True])
@pytest.mark.parametrize("probability", [1.0, 0.02])
def test_hpss_routing_and_stronger_gate_compared_to_suite_4(
        tmp_path, monkeypatch, separate, probability):
    source = tmp_path / "song.mp3"
    source.write_bytes(b"original")
    t = np.arange(0, 2, 0.01)
    energy = np.where((t >= 0.6) & (t < 1.4), -25.0, -35.0)
    results = []
    for name, implementation in [("suite_4", baseline), ("suite_7", aggressive)]:
        output = tmp_path / name
        vocals = tmp_path / "vocals.wav"
        filtered = output / "hpss-harmonic.wav"
        pitch_inputs, hpss_inputs = [], []
        monkeypatch.setattr(implementation, "decode_to_wav", lambda source, path: path)
        monkeypatch.setattr(implementation, "separate_vocals",
                            lambda *args, result=vocals, **kwargs: result)

        def hpss(audio, destination, recorded=hpss_inputs):
            recorded.append(audio)
            return destination

        def pitch(audio, recorded=pitch_inputs, **kwargs):
            recorded.append(audio)
            return t, np.full(200, 220.0), np.ones(200, bool), np.full(200, probability)

        monkeypatch.setattr(implementation, "harmonic_reference", hpss)
        monkeypatch.setattr(implementation, "estimate_pitch", pitch)
        monkeypatch.setattr(implementation, "estimate_secondary_pitch", pitch)
        monkeypatch.setattr(implementation, "frame_rms_db", lambda audio, times: energy)
        monkeypatch.setattr(implementation.sf, "info", lambda *args: SimpleNamespace(duration=2.0))
        manifest = pipeline.analyze(source, output, separate=separate, suite=name)
        results.append(json.loads(manifest.read_text())["notes"])
        assert pitch_inputs == [filtered, filtered]
        assert hpss_inputs == [vocals if separate else output / "analysis.wav"]
        assert source.read_bytes() == b"original"
    assert results[0] and results[1]
    assert sum(n["duration"] for n in results[0]) > 1.9
    assert all(n["start"] >= 0.6 and n["start"] + n["duration"] <= 1.401 for n in results[1])
    diagnostics = json.loads((tmp_path / "suite_7" / "energy-threshold-debug.json").read_text())
    assert diagnostics["minimum_rms_dbfs"] == -25.0
    provenance = json.loads((tmp_path / "suite_7" / "analysis-suite.json").read_text())
    assert provenance["version"] == 2

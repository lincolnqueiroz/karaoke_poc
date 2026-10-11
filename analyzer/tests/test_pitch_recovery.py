import numpy as np
import pytest

from karaoke_analyzer.pitch_recovery import recover_pitch
from karaoke_analyzer.segmentation import segment_notes


def data(probability):
    p = np.asarray(probability, dtype=float)
    return [np.arange(len(p)) * 0.01, np.full(len(p), 110.0),
            np.ones(len(p), dtype=bool), p, np.full(len(p), -24.0)]


def test_low_probability_continuation_is_recovered_without_mutating_raw_data():
    arrays = data([0.9] * 30 + [0.02] * 20)
    copies = [a.copy() for a in arrays]
    mask = recover_pitch(*arrays)
    assert not mask[:30].any() and mask[30:].all()
    diagnostics = {}
    t, f, v, p, e = arrays
    notes = segment_notes(t, f, v, probability=p, rms_db=e,
                          recovery_diagnostics=diagnostics)
    assert notes[0]["duration"] == pytest.approx(0.5)
    assert notes[0]["midi"] == 45
    np.testing.assert_array_equal(diagnostics["recovered"], mask)
    for actual, original in zip(arrays, copies):
        np.testing.assert_array_equal(actual, original)


def test_recovery_is_bounded_and_does_not_create_new_anchors():
    arrays = data([0.9] * 10 + [0.02] * 100)
    mask = recover_pitch(*arrays)
    assert mask[10:35].all() and not mask[35:].any()


def test_isolated_weak_pitch_and_single_confident_frame_are_not_anchors():
    assert not recover_pitch(*data([0.02] * 100)).any()
    assert not recover_pitch(*data([0.02] * 30 + [0.9] + [0.02] * 30)).any()


@pytest.mark.parametrize("failure", ["silence", "unvoiced", "nan", "octave", "timestamp_gap"])
def test_recovery_cannot_cross_invalid_evidence(failure):
    arrays = data([0.9] * 30 + [0.02] * 30)
    t, f, v, _, e = arrays
    if failure == "silence":
        e[30:] = -80
    elif failure == "unvoiced":
        v[30:] = False
    elif failure == "nan":
        f[30:] = np.nan
    elif failure == "octave":
        f[30:] = 220
    else:
        t[30:] += 1
    assert not recover_pitch(*arrays).any()


def test_recovery_requires_energy_evidence_and_can_be_disabled():
    t, f, v, p, e = data([0.9] * 30 + [0.02] * 20)
    assert segment_notes(t, f, v, probability=p)[0]["duration"] == pytest.approx(0.3)
    assert segment_notes(t, f, v, probability=p, rms_db=e,
                         recovery=False)[0]["duration"] == pytest.approx(0.3)


@pytest.mark.parametrize("options", [{"max_distance": -1}, {"anchor_duration": np.nan},
                                      {"candidate_probability": 0.2}])
def test_invalid_recovery_parameters(options):
    with pytest.raises(ValueError):
        recover_pitch(*data([0.9] * 10), **options)

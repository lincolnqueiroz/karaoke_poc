import numpy as np
import pytest

from karaoke_analyzer.pitch_consensus import pitch_consensus
from karaoke_analyzer.segmentation import segment_notes


def tracks(count=30):
    return [np.arange(count) * 0.01, np.full(count, 110.0), np.ones(count, dtype=bool),
            np.full(count, 0.02), np.full(count, 110.0), np.ones(count, dtype=bool),
            np.full(count, 0.02), np.full(count, -24.0)]


def test_sustained_agreement_supports_weak_low_voice_and_preserves_raw_arrays():
    arrays = tracks()
    before = [a.copy() for a in arrays]
    supported, distance = pitch_consensus(*arrays)
    assert supported.all() and (distance == 0).all()
    t, f, v, p, _, _, _, energy = arrays
    notes = segment_notes(t, f, v, probability=p, rms_db=energy, support_mask=supported)
    assert notes[0]["midi"] == 45 and notes[0]["duration"] == pytest.approx(0.3)
    for original, current in zip(before, arrays):
        np.testing.assert_array_equal(current, original)


@pytest.mark.parametrize("change", ["octave", "detuning", "silence", "unvoiced", "nan", "low_probability"])
def test_unsupported_evidence_is_rejected(change):
    arrays = tracks()
    if change == "octave":
        arrays[4][:] = 220
    elif change == "detuning":
        arrays[4][:] *= 2 ** (0.6 / 12)
    elif change == "silence":
        arrays[7][:] = -80
    elif change == "unvoiced":
        arrays[5][:] = False
    elif change == "nan":
        arrays[4][:] = np.nan
    else:
        arrays[6][:] = 0.001
    assert not pitch_consensus(*arrays)[0].any()


def test_short_coincidences_and_timestamp_gaps_do_not_form_support():
    assert not pitch_consensus(*tracks(7))[0].any()
    arrays = tracks(14)
    arrays[0][7:] += 1
    assert not pitch_consensus(*arrays)[0].any()


def test_short_notes_require_sustained_cross_window_evidence():
    t, f, v, p, other, other_v, other_p, energy = tracks(10)
    supported, _ = pitch_consensus(t, f, v, p, other, other_v, other_p, energy)
    assert segment_notes(t, f, v, probability=p, rms_db=energy) == []
    notes = segment_notes(t, f, v, probability=p, rms_db=energy, support_mask=supported)
    assert notes[0]["duration"] == pytest.approx(0.1)


def test_short_trusted_notes_without_consensus_still_use_original_minimum():
    t, f, v, _, _, _, _, energy = tracks(10)
    assert segment_notes(t, f, v, probability=np.full(10, 0.9), rms_db=energy) == []


def test_support_never_bypasses_gate_or_missing_voicing():
    t, f, v, p, _, _, _, energy = tracks()
    assert segment_notes(t, f, v, probability=p, rms_db=np.full(30, -80),
                         support_mask=np.ones(30, bool)) == []
    assert segment_notes(t, f, np.zeros(30, bool), probability=p, rms_db=energy,
                         support_mask=np.ones(30, bool)) == []


def test_mismatched_shapes_are_rejected():
    arrays = tracks()
    arrays[4] = np.array([110])
    with pytest.raises(ValueError, match="shapes"):
        pitch_consensus(*arrays)

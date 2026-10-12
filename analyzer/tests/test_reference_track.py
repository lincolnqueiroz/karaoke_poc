import numpy as np
import pytest

from karaoke_analyzer.reference_track import select_reference, vocal_activity
from karaoke_analyzer.segmentation import segment_notes


def arrays(count=100):
    return [np.arange(count) * 0.01, np.full(count, 220.0), np.ones(count, bool),
            np.full(count, 0.9), np.full(count, 220.0), np.ones(count, bool),
            np.full(count, 0.02), np.ones(count, bool), np.zeros(count, bool)]


def test_secondary_recovers_missing_primary_without_changing_raw_tracks():
    values = arrays()
    values[1][:] = np.nan
    values[2][:] = False
    values[6][:] = 0.04
    copies = [a.copy() for a in values]
    f, v, p, support, source = select_reference(*values)
    notes = segment_notes(values[0], f, v, probability=p, rms_db=np.full(100, -20),
                          support_mask=support, activity_mask=values[7])
    assert len(notes) == 1 and notes[0]["duration"] == 1.0
    assert (source == 2).all()
    for original, current in zip(copies, values):
        np.testing.assert_array_equal(current, original)


def test_strong_primary_wins_harmony_disagreement():
    values = arrays()
    values[4][:] = 330
    values[6][:] = 0.99
    f, _, _, _, source = select_reference(*values)
    assert (f == 220).all() and (source == 1).all()


def test_secondary_weak_conflicting_harmony_does_not_replace_primary():
    values = arrays()
    values[3][:] = 0.02
    values[4][:] = 330
    assert (select_reference(*values)[4] == 1).all()


def test_short_secondary_coincidence_does_not_gain_support():
    values = arrays(7)
    values[2][:] = False
    _, _, _, supported, _ = select_reference(*values)
    assert not supported.any()


def test_weak_secondary_without_independent_candidate_agreement_is_rejected():
    values = arrays()
    values[1][:] = np.nan
    values[2][:] = False
    assert not select_reference(*values)[1].any()


def test_two_unvoiced_candidate_tracks_can_support_a_stable_chorus_but_not_boundaries():
    values = arrays()
    values[1][:] = values[4][:] = np.nan
    values[2][:] = values[5][:] = False
    values[3][:] = values[6][:] = 0.02
    candidate = np.full(100, 220.0)
    f, v, p, supported, source = select_reference(
        *values, primary_candidate=candidate, secondary_candidate=candidate)
    assert v.all() and supported.all() and (f == 220).all() and (source == 2).all()
    assert np.all(p == 0.02)
    for boundary in [65.406, 2093]:
        candidate[:] = boundary
        assert not select_reference(*values, primary_candidate=candidate,
                                    secondary_candidate=candidate)[1].any()


def test_interpolate_only_brief_same_pitch_active_dropouts():
    values = arrays()
    values[2][40:44] = False
    values[5][40:44] = False
    assert (select_reference(*values)[4][40:44] == 3).all()
    values[7][40:44] = False
    assert (select_reference(*values)[4][40:44] == 0).all()
    values[7][:] = True
    values[2][40:60] = False
    values[5][40:60] = False
    assert (select_reference(*values)[4][40:60] == 0).all()


def test_short_dropout_across_pitch_jump_is_not_interpolated():
    values = arrays()
    values[2][40:44] = values[5][40:44] = False
    values[1][44:] = 440
    assert (select_reference(*values)[4][40:44] == 0).all()


def test_activity_rejects_separated_leakage_without_blocking_quiet_normalized_song():
    energy = np.r_[np.full(100, -20), np.full(100, -43)]
    mixture = np.full(200, -10)
    assert vocal_activity(energy, mixture)[:100].all()
    assert not vocal_activity(energy, mixture)[100:].any()
    assert vocal_activity(np.full(100, -40), np.full(100, -35)).all()
    assert not vocal_activity(np.full(100, -80)).any()


def test_quiet_out_of_register_residual_is_rejected_but_loud_falsetto_is_kept():
    energy = np.r_[np.full(100, -20), np.full(20, -38), np.full(20, -20)]
    f0 = np.r_[np.full(100, 220), np.full(40, 1900)]
    active = vocal_activity(energy, np.full(140, -15), f0=f0,
                            probability=np.full(140, 0.9))
    assert active[:100].all() and active[120:].all()
    # The high loud segment enters the 95th percentile, so it legitimately
    # broadens the register. A quiet artifact alone must not do that.
    active = vocal_activity(energy[:120], np.full(120, -15), f0=f0[:120],
                            probability=np.full(120, 0.9))
    assert not active[100:].any()


def test_short_real_silence_is_not_merged_but_estimator_dropout_is():
    values = arrays()
    values[2][49:51] = False
    active = np.ones(100, bool)
    active[49:51] = False
    notes = segment_notes(values[0], values[1], values[2], activity_mask=active)
    assert len(notes) == 2
    assert len(segment_notes(values[0], values[1], values[2])) == 1


@pytest.mark.parametrize("change", ["shape", "times", "probability"])
def test_invalid_reference_inputs(change):
    values = arrays()
    if change == "shape":
        values[4] = values[4][:-1]
    elif change == "times":
        values[0][5] = values[0][4]
    else:
        values[3][5] = 1.1
    with pytest.raises(ValueError):
        select_reference(*values)

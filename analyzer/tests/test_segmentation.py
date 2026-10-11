import numpy as np
import pytest

from karaoke_analyzer.segmentation import hz_to_midi, segment_notes


def test_a4():
    assert hz_to_midi(440.0) == 69


def test_invalid_frequency():
    with pytest.raises(ValueError):
        hz_to_midi(0)


def test_notes_and_silence():
    t = np.arange(12) * 0.05
    f0 = np.array([440.0] * 5 + [np.nan] * 2 + [493.883] * 5)
    voiced = np.array([True] * 5 + [False] * 2 + [True] * 5)
    notes = segment_notes(t, f0, voiced)
    assert [n["midi"] for n in notes] == [69, 71]
    assert notes[0]["duration"] == pytest.approx(0.25)


def melody(pitches, **kwargs):
    pitches = np.asarray(pitches, dtype=float)
    return segment_notes(np.arange(len(pitches)) * 0.01,
                         440 * 2 ** ((pitches - 69) / 12),
                         np.isfinite(pitches), **kwargs)


def test_vibrato_crossing_rounding_boundary_stays_one_note():
    pitches = 69 + 0.65 * np.sin(np.arange(100) * 2 * np.pi / 20)
    notes = melody(pitches)
    assert len(notes) == 1
    assert notes[0]["midi"] == 69
    assert notes[0]["duration"] == pytest.approx(1.0)


def test_brief_pitch_excursion_does_not_split_note():
    notes = melody([69] * 30 + [71] * 4 + [69] * 30)
    assert [n["midi"] for n in notes] == [69]
    assert notes[0]["duration"] == pytest.approx(0.64)


def test_real_semitone_transition_keeps_onset():
    notes = melody([69] * 30 + [70] * 30)
    assert [n["midi"] for n in notes] == [69, 70]
    assert notes[1]["start"] == pytest.approx(0.3)
    assert notes[0]["duration"] == pytest.approx(0.3)


def test_short_octave_glitch_is_corrected_but_sustained_octave_is_preserved():
    assert [n["midi"] for n in melody([69] * 30 + [81] * 12 + [69] * 30)] == [69]
    assert [n["midi"] for n in melody([69] * 30 + [81] * 30 + [69] * 30)] == [69, 81, 69]


def test_brief_gap_merges_but_long_silence_does_not():
    short = melody([69] * 20 + [np.nan] * 4 + [69] * 20)
    assert len(short) == 1
    assert short[0]["duration"] == pytest.approx(0.44)
    long = melody([69] * 20 + [np.nan] * 20 + [69] * 20)
    assert len(long) == 2
    assert long[1]["start"] == pytest.approx(0.4)


def test_confidence_filters_noise_and_retains_raw_inputs():
    t = np.arange(60) * 0.01
    f = np.array([440.0] * 30 + [880.0] * 30)
    p = np.array([0.9] * 30 + [0.01] * 30)
    v = np.ones(60, dtype=bool)
    copies = [a.copy() for a in (t, f, v, p)]
    notes = segment_notes(t, f, v, probability=p)
    assert [n["midi"] for n in notes] == [69]
    assert notes[0]["duration"] == pytest.approx(0.3)
    for actual, original in zip((t, f, v, p), copies):
        np.testing.assert_array_equal(actual, original)


def test_missing_time_frames_do_not_create_sustained_note():
    times = np.r_[np.arange(20) * 0.01, 1 + np.arange(20) * 0.01]
    notes = segment_notes(times, np.full(40, 440), np.ones(40, dtype=bool))
    assert len(notes) == 2
    assert notes[0]["duration"] == pytest.approx(0.2)
    assert notes[1]["start"] == pytest.approx(1.0)


@pytest.mark.parametrize("times", [[0, np.nan], [0, 0], [-1, 0], [1, 0]])
def test_invalid_times(times):
    with pytest.raises(ValueError):
        segment_notes(times, [440, 440], [True, True])


@pytest.mark.parametrize("kwargs", [
    {"probability": [0.9]}, {"probability": [0.9, 2.0]},
    {"merge_gap": -1}, {"smoothing_window": np.nan}, {"hysteresis": 1.2},
])
def test_invalid_parameters(kwargs):
    with pytest.raises(ValueError):
        segment_notes([0, 0.01], [440, 440], [True, True], **kwargs)


def test_empty_and_invalid_frequency_frames():
    assert segment_notes([], [], [], probability=[]) == []
    assert segment_notes([0, 0.01, 0.02], [np.nan, np.inf, -1], [True] * 3) == []


def test_audible_lower_probability_voice_is_retained():
    notes = melody([69] * 100, probability=np.full(100, 0.2), rms_db=np.full(100, -24))
    assert len(notes) == 1
    assert notes[0]["duration"] == pytest.approx(1.0)


def test_quiet_periodic_residual_is_rejected_despite_high_probability():
    assert melody([74] * 100, probability=np.full(100, 0.99),
                  rms_db=np.full(100, -70)) == []


def test_energy_gate_does_not_bridge_long_silence():
    notes = melody([69] * 100, probability=np.full(100, 0.9),
                   rms_db=np.r_[np.full(30, -20), np.full(40, -80), np.full(30, -20)])
    assert len(notes) == 2
    assert notes[0]["duration"] == pytest.approx(0.3)
    assert notes[1]["start"] == pytest.approx(0.7)


@pytest.mark.parametrize("energy", [[-20], [[-20, -20]]])
def test_energy_shape(energy):
    with pytest.raises(ValueError):
        segment_notes([0, 0.01], [440, 440], [True, True], rms_db=energy)

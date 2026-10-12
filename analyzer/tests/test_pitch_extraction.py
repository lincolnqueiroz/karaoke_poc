"""Exercise the actual pYIN backend without GPU or downloaded models."""
import numpy as np
import pytest
import soundfile as sf

from karaoke_analyzer.pitch import estimate_pitch
from karaoke_analyzer.segmentation import segment_notes


@pytest.mark.parametrize("frequency,rate", [
    (65.4, 22050), (82.4, 44100), (110, 48000),
    (220, 22050), (440, 44100), (880, 48000), (1760, 22050),
])
def test_actual_pitch_registers(tmp_path, frequency, rate):
    time = np.arange(rate) / rate
    audio = 0.2 * np.sin(2 * np.pi * frequency * time)
    audio += 0.05 * np.sin(4 * np.pi * frequency * time)
    path = tmp_path / "tone.wav"
    sf.write(path, audio, rate, subtype="FLOAT")
    times, f0, voiced, probability = estimate_pitch(path)
    interior = (times >= 0.2) & (times <= 0.8)
    valid = interior & voiced & np.isfinite(f0)
    assert np.mean(voiced[interior]) >= 0.9
    assert np.median(np.abs(1200 * np.log2(f0[valid] / frequency))) < 35
    assert len(times) == len(probability) == len(f0)
    assert np.all(np.diff(times) > 0)


def test_actual_pitch_silence(tmp_path):
    path = tmp_path / "silence.wav"
    sf.write(path, np.zeros(22050), 22050)
    diagnostics = {}
    _, f0, voiced, _ = estimate_pitch(path, diagnostics=diagnostics)
    assert not np.any(voiced)
    assert not np.any(np.isfinite(f0))
    assert diagnostics["candidate_f0"].shape == f0.shape
    assert np.all(np.isfinite(diagnostics["candidate_f0"]))


def test_actual_pitch_unpitched_noise(tmp_path):
    path = tmp_path / "noise.wav"
    noise = np.random.default_rng(42).uniform(-0.1, 0.1, 22050)
    sf.write(path, noise, 22050)
    _, _, voiced, _ = estimate_pitch(path)
    assert np.mean(voiced) < 0.05


def test_actual_pitch_vibrato_with_noise(tmp_path):
    time = np.arange(22050) / 22050
    frequency = 110 * 2 ** (0.3 * np.sin(2 * np.pi * 5 * time) / 12)
    phase = 2 * np.pi * np.cumsum(frequency) / 22050
    audio = 0.2 * np.sin(phase) + 0.06 * np.sin(2 * phase)
    audio += np.random.default_rng(7).uniform(-0.025, 0.025, len(time))
    path = tmp_path / "vibrato.wav"
    sf.write(path, audio, 22050)
    times, f0, voiced, _ = estimate_pitch(path)
    interior = (times >= 0.2) & (times <= 0.8)
    target = np.interp(times, time, frequency)
    correct = voiced & np.isfinite(f0)
    correct[correct] &= np.abs(1200 * np.log2(f0[correct] / target[correct])) <= 50
    assert np.mean(correct[interior]) >= 0.9


@pytest.mark.xfail(strict=True, reason="Mono averaging cancels opposite-phase vocal channels")
def test_actual_pitch_opposite_phase_channels(tmp_path):
    time = np.arange(22050) / 22050
    tone = 0.2 * np.sin(2 * np.pi * 110 * time)
    path = tmp_path / "opposite_phase.wav"
    sf.write(path, np.column_stack((tone, -tone)), 22050, subtype="FLOAT")
    times, f0, voiced, _ = estimate_pitch(path)
    valid = (times > 0.2) & (times < 0.8) & voiced & np.isfinite(f0)
    assert np.count_nonzero(valid) >= 30


@pytest.mark.xfail(strict=True, reason="Segmentation merges same-pitch notes across short gaps")
def test_repeated_pitch_attacks_remain_separate():
    times = np.arange(100) * 0.01
    voiced = np.ones(100, dtype=bool)
    voiced[49:51] = False
    notes = segment_notes(times, np.full(100, 220.0), voiced)
    assert len(notes) == 2

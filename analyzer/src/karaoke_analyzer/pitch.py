"""Baseline monophonic fundamental-frequency tracking."""
from pathlib import Path

import numpy as np


def estimate_pitch(wav_path: Path, hop_length: int = 256, *, frame_length: int = 2048):
    import librosa
    audio, sample_rate = librosa.load(str(wav_path), sr=22050, mono=True)
    f0, voiced, probability = librosa.pyin(audio, sr=sample_rate, hop_length=hop_length,
                                           frame_length=frame_length,
                                           fmin=librosa.note_to_hz("C2"),
                                           fmax=librosa.note_to_hz("C7"))
    times = librosa.times_like(f0, sr=sample_rate, hop_length=hop_length)
    return np.asarray(times), np.asarray(f0), np.asarray(voiced), np.asarray(probability)


def estimate_secondary_pitch(wav_path: Path):
    return estimate_pitch(wav_path, frame_length=4096)

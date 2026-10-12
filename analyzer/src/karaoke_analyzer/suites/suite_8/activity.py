"""Audio energy diagnostics, independent of pitch inference and ML models."""

import math
from pathlib import Path

import numpy as np
import soundfile as sf


def frame_rms_db(wav_path: Path, times, window_seconds: float = 0.09):
    """Centered RMS in dBFS at each timestamp, averaging channel power.

    A quiet residual may still be periodic and receive high pYIN probability.
    Energy detects near-silence, not whether an audible source is a human voice.
    """
    t = np.asarray(times, dtype=float)
    if t.ndim != 1 or not np.all(np.isfinite(t)) or np.any(t < 0):
        raise ValueError("Energy timestamps must be finite and nonnegative")
    if not math.isfinite(window_seconds) or window_seconds <= 0:
        raise ValueError("Energy window must be finite and positive")
    audio, rate = sf.read(str(wav_path), dtype="float32", always_2d=True)
    if len(audio) == 0 or not np.all(np.isfinite(audio)):
        raise ValueError("Energy input must contain finite audio samples")
    if np.any(t > len(audio) / rate):
        raise ValueError("Energy timestamps exceed audio duration")
    power = np.mean(np.square(audio, dtype=np.float64), axis=1)
    cumulative = np.r_[0.0, np.cumsum(power)]
    centers = np.minimum(np.rint(t * rate).astype(np.int64), len(audio) - 1)
    half = max(1, round(window_seconds * rate / 2))
    left = np.maximum(0, centers - half)
    right = np.minimum(len(audio), centers + half + 1)
    mean_power = (cumulative[right] - cumulative[left]) / (right - left)
    with np.errstate(divide="ignore"):
        return 10 * np.log10(np.maximum(mean_power, 0))

"""Stabilize estimated pitch and group it into conservative note segments."""

import math
from itertools import pairwise

import numpy as np

from .pitch_recovery import recover_pitch


def hz_to_midi(hz: float) -> int:
    if not math.isfinite(hz) or hz <= 0:
        raise ValueError("Pitch must be a finite positive frequency")
    return round(69 + 12 * math.log2(hz / 440.0))


def _runs(values):
    start = 0
    for i in range(1, len(values) + 1):
        if i == len(values) or values[i] != values[start]:
            yield start, i, int(values[start])
            start = i


def _stable_pitches(times, midi, ends, smoothing_window, hysteresis, change_duration):
    half = smoothing_window / 2
    smooth = np.array([
        np.median(midi[np.searchsorted(times, t - half):
                       np.searchsorted(times, t + half, side="right")])
        for t in times
    ])
    current = round(float(smooth[0]))
    labels = np.full(len(times), current, dtype=int)
    candidate = None
    candidate_start = 0
    for i, value in enumerate(smooth):
        target = round(float(value))
        if target == current or abs(value - current) < hysteresis:
            candidate = None
        else:
            if target != candidate:
                candidate, candidate_start = target, i
            if ends[i] - times[candidate_start] >= change_duration - 1e-9:
                current = target
                # Backdate confirmed transitions to avoid adding playback latency.
                labels[candidate_start:i + 1] = current
                candidate = None
        labels[i] = current
    return labels


def segment_notes(
    times, f0, voiced, min_duration=0.12, *, probability=None,
    min_probability=0.1, smoothing_window=0.07, hysteresis=0.75,
    change_duration=0.08, merge_gap=0.06, octave_glitch_duration=0.15,
    rms_db=None, min_rms_db=None, recovery=True, recovery_diagnostics=None,
    support_mask=None, activity_mask=None,
):
    """Filter and stabilize pitch without modifying raw input arrays.

    Durations are seconds, hysteresis is semitones. Smooth each voiced island
    independently, confirm sustained changes, repair only short octave excursions
    bracketed by the same pitch, and join identical notes over brief gaps.
    Missing probability preserves voiced-only callers. Confidence remains the
    schema-v1 placeholder 1.0, not a calibrated probability.
    Optional RMS energy rejects quiet periodic residuals independently of pYIN.
    An explicit activity mask prevents recovery and merging across real silence.
    """
    t, f, v = (np.asarray(times, dtype=float), np.asarray(f0, dtype=float),
               np.asarray(voiced, dtype=bool))
    if any(a.ndim != 1 for a in (t, f, v)) or not (len(t) == len(f) == len(v)):
        raise ValueError("times, f0 and voiced must be equal-length one-dimensional arrays")
    if not np.all(np.isfinite(t)) or np.any(t < 0) or np.any(np.diff(t) <= 0):
        raise ValueError("Frame times must be finite, nonnegative and strictly increasing")
    durations = (min_duration, smoothing_window, change_duration, merge_gap,
                 octave_glitch_duration)
    if any(not math.isfinite(x) or x < 0 for x in durations):
        raise ValueError("Duration parameters must be finite and nonnegative")
    if not math.isfinite(hysteresis) or not 0.5 <= hysteresis < 1:
        raise ValueError("hysteresis must be in [0.5, 1) semitones")
    if not math.isfinite(min_probability) or not 0 <= min_probability <= 1:
        raise ValueError("min_probability must be in [0, 1]")
    if (min_rms_db is None or not math.isfinite(min_rms_db)):
        raise ValueError("min_rms_db must be finite")
    valid = v & np.isfinite(f) & (f > 0)
    active = np.ones(len(t), dtype=bool)
    if activity_mask is not None:
        active = np.asarray(activity_mask, dtype=bool)
        if active.ndim != 1 or active.shape != t.shape:
            raise ValueError("activity_mask must have the same shape as times")
        valid &= active
    if recovery_diagnostics is not None:
        recovery_diagnostics["recovered"] = np.zeros(len(t), dtype=bool)
    supported = np.zeros(len(t), dtype=bool)
    if support_mask is not None:
        supported = np.asarray(support_mask, dtype=bool)
        if supported.ndim != 1 or supported.shape != t.shape:
            raise ValueError("support_mask must have the same shape as times")
        if probability is None or rms_db is None:
            raise ValueError("Pitch support requires probability and energy evidence")
    if rms_db is not None:
        energy = np.asarray(rms_db, dtype=float)
        if energy.ndim != 1 or energy.shape != t.shape:
            raise ValueError("rms_db must have the same shape as times")
        valid &= np.isfinite(energy) & (energy >= min_rms_db)
    if probability is not None:
        p = np.asarray(probability, dtype=float)
        if p.ndim != 1 or p.shape != t.shape:
            raise ValueError("probability must have the same shape as times")
        if np.any(np.isfinite(p) & ((p < 0) | (p > 1))):
            raise ValueError("Finite probabilities must be in [0, 1]")
        accepted = np.isfinite(p) & (p >= min_probability)
        recovered = np.zeros(len(t), dtype=bool)
        if recovery and rms_db is not None:
            recovered = recover_pitch(t, f, v & active, p, energy,
                                      min_probability=min_probability, min_rms_db=min_rms_db,
                                      candidate_probability=min(0.01, min_probability))
        supported = supported & valid & np.isfinite(p) & (p >= 0.01)
        valid &= accepted | recovered | supported
        if recovery_diagnostics is not None:
            recovery_diagnostics["recovered"] = recovered.copy()
    if len(t) == 0:
        return []
    hop = float(np.median(np.diff(t))) if len(t) > 1 else 0.01
    ends = np.minimum(np.r_[t[1:], t[-1] + hop], t + hop)
    midi = np.full(len(t), np.nan)
    midi[valid] = 69 + 12 * np.log2(f[valid] / 440.0)
    valid &= (midi >= -0.5) & (midi < 127.5)
    labels = np.full(len(t), -1, dtype=int)
    start = 0
    while start < len(t):
        if not valid[start]:
            start += 1
            continue
        end = start + 1
        while end < len(t) and valid[end] and t[end] - t[end - 1] <= hop * 1.5:
            end += 1
        block = _stable_pitches(t[start:end], midi[start:end], ends[start:end],
                                smoothing_window, hysteresis, change_duration)
        runs = list(_runs(block))
        for index in range(1, len(runs) - 1):
            left, middle, right = runs[index - 1:index + 2]
            a, b, pitch = middle
            if (left[2] == right[2] and abs(pitch - left[2]) == 12
                    and ends[start + b - 1] - t[start + a] <= octave_glitch_duration):
                block[a:b] = left[2]
        labels[start:end] = block
        start = end
    segments = []
    for a, b, pitch in _runs(labels):
        if pitch < 0:
            continue
        cuts = [a, *(i for i in range(a + 1, b) if t[i] - t[i - 1] > hop * 1.5), b]
        for left, right in pairwise(cuts):
            begin, end = float(t[left]), float(ends[right - 1])
            if (segments and segments[-1][2] == pitch
                    and begin - segments[-1][1] <= merge_gap + 1e-9
                    and active[np.searchsorted(t, segments[-1][1] - 1e-9):left].all()):
                segments[-1] = (segments[-1][0], end, pitch)
            else:
                segments.append((begin, end, pitch))
    def keep_segment(start, end):
        if end - start >= min_duration - 1e-9:
            return True
        if end - start < 0.08 - 1e-9:
            return False
        left, right = np.searchsorted(t, [start - 0.00005, end - 0.00005])
        return right > left and np.mean(supported[left:right]) >= 0.8

    return [
        {"start": round(start, 4), "duration": round(end - start, 4),
         "midi": pitch, "confidence": 1.0}
        for start, end, pitch in segments
        if keep_segment(start, end) and round(end - start, 4) > 0
    ]

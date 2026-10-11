"""Recover low-probability F0 only near trustworthy, continuous voiced anchors."""
import math

import numpy as np


def recover_pitch(times, f0, voiced, probability, rms_db, *, min_probability=0.1,
                  min_rms_db=-50.0, candidate_probability=0.01,
                  max_distance=0.25, max_pitch_distance=1.5, anchor_duration=0.03):
    arrays = [np.asarray(a, dtype=float) for a in (times, f0, probability, rms_db)]
    t, f, p, energy = arrays
    v = np.asarray(voiced, dtype=bool)
    if any(a.ndim != 1 or a.shape != t.shape for a in [*arrays, v]):
        raise ValueError("Recovery arrays must be equal-length one-dimensional arrays")
    if not np.all(np.isfinite(t)) or np.any(t < 0) or np.any(np.diff(t) <= 0):
        raise ValueError("Recovery times must be finite, nonnegative and increasing")
    if not 0 <= candidate_probability <= min_probability <= 1:
        raise ValueError("Invalid recovery probabilities")
    if any(not math.isfinite(x) or x <= 0 for x in
           (max_distance, max_pitch_distance, anchor_duration)) or not math.isfinite(min_rms_db):
        raise ValueError("Invalid recovery parameters")
    if np.any(np.isfinite(p) & ((p < 0) | (p > 1))):
        raise ValueError("Probability must be within [0, 1]")
    audible = v & np.isfinite(f) & (f > 0) & np.isfinite(energy) & (energy >= min_rms_db)
    trusted = audible & np.isfinite(p) & (p >= min_probability)
    recovered = np.zeros(t.shape, dtype=bool)
    if len(t) == 0:
        return recovered
    hop = float(np.median(np.diff(t))) if len(t) > 1 else 0.01
    midi = np.full(t.shape, np.nan)
    midi[audible] = 69 + 12 * np.log2(f[audible] / 440)
    candidate = audible & np.isfinite(p) & (p >= candidate_probability)
    # Neither missing F0, silence, timestamp gaps nor octave jumps can be crossed.
    index = 0
    while index < len(t):
        if not candidate[index]:
            index += 1
            continue
        end = index + 1
        while (end < len(t) and candidate[end] and t[end] - t[end - 1] <= hop * 1.5
               and abs(midi[end] - midi[end - 1]) <= max_pitch_distance):
            end += 1
        anchors = np.zeros(end - index, dtype=bool)
        a = index
        while a < end:
            if not trusted[a]:
                a += 1
                continue
            b = a + 1
            while b < end and trusted[b]:
                b += 1
            if t[b - 1] - t[a] + hop >= anchor_duration - 1e-9:
                anchors[a - index:b - index] = True
            a = b
        locations = np.flatnonzero(anchors) + index
        if len(locations):
            for frame in range(index, end):
                if trusted[frame]:
                    continue
                position = int(np.searchsorted(locations, frame))
                near = locations[max(0, position - 1):min(len(locations), position + 1)]
                recovered[frame] = any(
                    abs(t[frame] - t[anchor]) <= max_distance + 1e-9
                    and abs(midi[frame] - midi[anchor]) <= max_pitch_distance
                    for anchor in near)
        index = end
    return recovered

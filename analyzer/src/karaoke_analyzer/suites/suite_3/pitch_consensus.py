"""Cross-window pitch support, keeping both raw estimator outputs unchanged."""
import numpy as np


def pitch_consensus(times, primary_f0, primary_voiced, primary_probability,
                    secondary_f0, secondary_voiced, secondary_probability, rms_db, *, min_rms_db):
    arrays = [np.asarray(a) for a in (times, primary_f0, primary_voiced,
              primary_probability, secondary_f0, secondary_voiced,
              secondary_probability, rms_db)]
    t, f, v, p, other, other_v, other_p, energy = arrays
    if any(a.ndim != 1 or a.shape != t.shape for a in arrays):
        raise ValueError("Consensus arrays must have matching one-dimensional shapes")
    if not np.all(np.isfinite(t)) or np.any(t < 0) or np.any(np.diff(t) <= 0):
        raise ValueError("Consensus times must be finite, nonnegative and increasing")
    for probabilities in (p, other_p):
        if np.any(np.isfinite(probabilities) & ((probabilities < 0) | (probabilities > 1))):
            raise ValueError("Consensus probabilities must be within [0, 1]")
    candidate = (v.astype(bool) & other_v.astype(bool) & np.isfinite(f) & (f > 0)
                 & np.isfinite(other) & (other > 0) & np.isfinite(p) & (p >= 0.01)
                 & np.isfinite(other_p) & (other_p >= 0.01)
                 & np.isfinite(energy) & (energy >= min_rms_db))
    distance = np.full(len(t), np.nan)
    distance[candidate] = np.abs(12 * np.log2(f[candidate] / other[candidate]))
    agrees = candidate & (distance <= 0.5)
    supported = np.zeros(len(t), dtype=bool)
    hop = float(np.median(np.diff(t))) if len(t) > 1 else 0.01
    index = 0
    while index < len(t):
        if not agrees[index]:
            index += 1
            continue
        end = index + 1
        while (end < len(t) and agrees[end] and t[end] - t[end - 1] <= hop * 1.5
               and abs(12 * np.log2(f[end] / f[end - 1])) <= 1.5):
            end += 1
        if t[end - 1] - t[index] + hop >= 0.08 - 1e-9:
            supported[index:end] = True
        index = end
    return supported, distance

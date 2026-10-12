"""Conservative two-window reference selection, separate from raw pYIN outputs."""
import numpy as np


def vocal_activity(energy, mixture_energy=None, *, min_rms_db, f0=None, probability=None):
    """Reject quiet separation leakage; this is not a learned voice detector."""
    energy = np.asarray(energy, dtype=float)
    if energy.ndim != 1:
        raise ValueError("Energy must be one-dimensional")
    active = np.isfinite(energy) & (energy >= min_rms_db)
    if mixture_energy is not None:
        mixture = np.asarray(mixture_energy, dtype=float)
        if mixture.shape != energy.shape:
            raise ValueError("Mixture energy must match vocal energy")
        active &= np.isfinite(mixture) & (energy - mixture >= -25)
        audible = energy[active]
        if f0 is not None and probability is not None:
            f = np.asarray(f0, dtype=float)
            p = np.asarray(probability, dtype=float)
            if f.shape != energy.shape or p.shape != energy.shape:
                raise ValueError("Register evidence must match energy")
            reference_level = float(np.percentile(audible, 70)) if len(audible) else min_rms_db
            pitched = np.isfinite(f) & (f > 0)
            anchors = active & pitched & (p >= 0.1) & (energy >= reference_level - 12)
            if np.count_nonzero(anchors) >= 40:
                midi = np.full(len(f), np.nan)
                midi[pitched] = 69 + 12 * np.log2(f[pitched] / 440)
                low, high = np.percentile(midi[anchors], [5, 95])
                # Only quiet, far-out-of-register residuals are excluded. Audible
                # octave/falsetto changes remain valid; no pitch is folded.
                outlier = pitched & ((midi < low - 12) | (midi > high + 12))
                active &= ~((energy < reference_level - 12) & outlier)
    return active


def select_reference(times, f0, voiced, probability, secondary_f0, secondary_voiced,
                     secondary_probability, active, support, *, primary_candidate=None,
                     secondary_candidate=None):
    """Use stable secondary evidence when primary fails, never invent long gaps.

    Source codes: 0 rejected, 1 primary, 2 secondary, 3 short interpolated dropout.
    Strong primary estimates win disagreements; weak conflicting voices do not
    get octave-folded or averaged into a fictitious melody.
    """
    arrays = [np.asarray(a) for a in (times, f0, voiced, probability, secondary_f0,
              secondary_voiced, secondary_probability, active, support)]
    t, f, v, p, other, ov, op, active, support = arrays
    if any(a.ndim != 1 or a.shape != t.shape for a in arrays):
        raise ValueError("Reference arrays must have matching one-dimensional shapes")
    if not np.all(np.isfinite(t)) or np.any(t < 0) or np.any(np.diff(t) <= 0):
        raise ValueError("Reference times must be finite, nonnegative and increasing")
    for probabilities in (p, op):
        if np.any(np.isfinite(probabilities) & ((probabilities < 0) | (probabilities > 1))):
            raise ValueError("Reference probabilities must be in [0, 1]")
    active = active.astype(bool)
    primary = active & v.astype(bool) & np.isfinite(f) & (f > 0) & np.isfinite(p)
    candidate_agreement = np.zeros(len(t), dtype=bool)
    candidate_other = other.astype(float).copy()
    if primary_candidate is not None and secondary_candidate is not None:
        pc, sc = (np.asarray(a, dtype=float) for a in
                  (primary_candidate, secondary_candidate))
        if pc.shape != t.shape or sc.shape != t.shape:
            raise ValueError("Candidate tracks must match timestamps")
        usable = (active & np.isfinite(pc) & np.isfinite(sc) & (pc > 67.3)
                  & (sc > 67.3) & (pc < 2033) & (sc < 2033)
                  & np.isfinite(p) & (p >= 0.01) & np.isfinite(op) & (op >= 0.01))
        distance = np.full(len(t), np.inf)
        distance[usable] = np.abs(12 * np.log2(pc[usable] / sc[usable]))
        candidate_agreement = usable & (distance <= 0.5)
        candidate_other[candidate_agreement] = sc[candidate_agreement]
    other = candidate_other
    secondary = (active & ov.astype(bool) & np.isfinite(other) & (other > 0)
                 & np.isfinite(op) & (op >= 0.01))
    # Viterbi can mark both frames unvoiced in a difficult chorus. Keep a
    # candidate only with agreement of both window estimates, away from search
    # boundaries. Unconstrained weak secondary-only guesses caused false notes.
    secondary = (secondary & (op >= 0.03)) | candidate_agreement
    # Weak secondary estimates need a sustained, locally continuous island.
    stable = np.zeros(len(t), dtype=bool)
    hop = float(np.median(np.diff(t))) if len(t) > 1 else 0.01
    i = 0
    while i < len(t):
        if not secondary[i]:
            i += 1
            continue
        end = i + 1
        while (end < len(t) and secondary[end] and t[end] - t[end - 1] <= hop * 1.5
               and abs(12 * np.log2(other[end] / other[end - 1])) <= 1.5):
            end += 1
        if t[end - 1] - t[i] + hop >= 0.12 - 1e-9:
            stable[i:end] = True
        i = end
    use_secondary = secondary & (~primary | (p < 0.1)) & (
        (op >= 0.1) | (stable & (~primary | ((op >= 0.05) & (op >= 2 * p)))))
    chosen = f.astype(float).copy()
    confidence = p.astype(float).copy()
    flags = primary.copy()
    supported = support.astype(bool).copy() & active
    source = np.where(primary, 1, 0).astype(np.uint8)
    chosen[use_secondary] = other[use_secondary]
    confidence[use_secondary] = op[use_secondary]
    flags[use_secondary] = True
    supported[use_secondary] = stable[use_secondary]
    source[use_secondary] = 2
    # Only fill brief, bounded, same-pitch dropouts inside active vocal audio.
    accepted = flags & ((confidence >= 0.1) | supported)
    i = 0
    while i < len(t):
        if accepted[i]:
            i += 1
            continue
        end = i + 1
        while end < len(t) and not accepted[end]:
            end += 1
        if (i > 0 and end < len(t) and active[i:end].all()
                and t[end] - t[i] <= 0.06 + 1e-9
                and np.all(np.diff(t[i - 1:end + 1]) <= hop * 1.5)
                and abs(12 * np.log2(chosen[end] / chosen[i - 1])) <= 0.5):
            chosen[i:end] = np.exp(np.interp(t[i:end], t[[i - 1, end]],
                                            np.log(chosen[[i - 1, end]])))
            confidence[i:end] = min(confidence[i - 1], confidence[end])
            flags[i:end] = True
            supported[i:end] = True
            source[i:end] = 3
        i = end
    flags &= active
    source[~flags] = 0
    return chosen, flags, confidence, supported, source

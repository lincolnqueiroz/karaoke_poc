"""Remove weak isolated notes and bridge only small, evidenced same-pitch gaps."""
import math

import numpy as np

PARAMETERS = {
    "short_note_seconds": 0.18, "isolation_seconds": 0.35,
    "long_anchor_seconds": 0.40, "absorption_maximum_gap_seconds": 0.06,
    "distant_semitones": 7, "strong_frame_fraction": 0.5,
    "maximum_gap_seconds": 0.25, "minimum_gap_evidence_fraction": 0.9,
    "maximum_missing_evidence_seconds": 0.03,
    "bridge_minimum_rms_dbfs": -35.0, "bridge_minimum_probability": 0.01,
    "pitch_tolerance_semitones": 0.5, "vocal_mix_minimum_db": -25.0,
}


def postprocess_notes(notes, times, primary_candidate, secondary_candidate,
                      primary_probability, secondary_probability, energy,
                      reference_probability, support, *, mixture_energy=None):
    arrays = [np.asarray(a) for a in (times, primary_candidate, secondary_candidate,
              primary_probability, secondary_probability, energy, reference_probability, support)]
    t, pc, sc, pp, sp, e, rp, supported = arrays
    if (t.ndim != 1 or any(a.shape != t.shape for a in arrays)
            or not np.all(np.isfinite(t)) or np.any(t < 0) or np.any(np.diff(t) <= 0)):
        raise ValueError("Postprocessing requires aligned arrays and increasing timestamps")
    mix = None if mixture_energy is None else np.asarray(mixture_energy)
    if mix is not None and mix.shape != t.shape:
        raise ValueError("Mixture energy must match postprocessing timestamps")
    for probability in (pp, sp, rp):
        if np.any(np.isfinite(probability) & ((probability < 0) | (probability > 1))):
            raise ValueError("Postprocessing probabilities must be in [0, 1]")
    original = [dict(n) for n in notes]
    last_end = 0.0
    for note in original:
        start, duration, midi = note["start"], note["duration"], note["midi"]
        if (not all(math.isfinite(x) for x in (start, duration, midi))
                or start < last_end - 0.0001 or duration <= 0
                or not 0 <= midi <= 127 or midi != round(midi)):
            raise ValueError("Postprocessing notes must be ordered, nonoverlapping and valid")
        last_end = start + duration
    if len(t) < 2:
        return original, []
    hop = float(np.median(np.diff(t)))
    changes = []

    def strong(note):
        frames = (t >= note["start"] - 0.00005) & (t < note["start"] + note["duration"] - 0.00005)
        return bool(frames.any() and np.mean(
            (np.isfinite(rp[frames]) & (rp[frames] >= 0.1)) | supported[frames].astype(bool)) >= 0.5)

    simplified = []
    for i, note in enumerate(original):
        left = original[i - 1] if i else None
        gap = note["start"] - left["start"] - left["duration"] if left else np.inf
        eligible = (left is not None and left["duration"] >= 0.40 - 1e-9
                    and note["duration"] <= 0.18 + 1e-9
                    and -0.0001 <= gap <= 0.06 + 1e-9 and strong(left))
        if eligible and gap > 0.0001:
            frames = (t >= left["start"] + left["duration"] - 0.00005) & (t < note["start"] - 0.00005)
            locations = t[frames]
            eligible = bool(len(locations) and np.isfinite(e[frames]).all()
                            and (e[frames] >= -25).all()
                            and locations[0] - left["start"] - left["duration"] <= 1.5 * hop
                            and note["start"] - locations[-1] <= 1.5 * hop
                            and np.all(np.diff(locations) <= 1.5 * hop))
            if mix is not None:
                eligible &= bool(np.isfinite(mix[frames]).all() and (e[frames] - mix[frames] >= -25).all())
        if eligible:
            changes.append({"action": "absorb_short", "note": note,
                            "anchor_midi": left["midi"], "anchor_start": left["start"]})
            simplified[-1]["duration"] = round(note["start"] + note["duration"] - left["start"], 4)
        else:
            simplified.append(dict(note))
    # Only the immediately preceding original long note is eligible. Absorbed
    # short notes do not become anchors for flattening an entire sequence.
    original = simplified

    clean = []
    for i, note in enumerate(original):
        left = original[i - 1] if i else None
        right = original[i + 1] if i + 1 < len(original) else None
        nearby = []
        if left and note["start"] - left["start"] - left["duration"] <= 0.35:
            nearby.append(left)
        if right and right["start"] - note["start"] - note["duration"] <= 0.35:
            nearby.append(right)
        isolated = not nearby
        excursion = (len(nearby) == 2 and left["midi"] == right["midi"]
                     and abs(note["midi"] - left["midi"]) >= 7)
        if note["duration"] <= 0.18 and not strong(note) and (isolated or excursion):
            changes.append({"action": "remove", "reason": "weak_isolated" if isolated
                            else "weak_returning_jump", "note": note})
        else:
            clean.append(note)

    valid = (np.isfinite(pc) & np.isfinite(sc) & (pc > 67.3) & (sc > 67.3)
             & (pc < 2033) & (sc < 2033) & np.isfinite(pp) & np.isfinite(sp)
             & (pp >= 0.01) & (sp >= 0.01) & np.isfinite(e) & (e >= -35))
    if mix is not None:
        valid &= np.isfinite(mix) & (e - mix >= -25)
    pm, sm = np.full(len(t), np.nan), np.full(len(t), np.nan)
    pm[valid], sm[valid] = 69 + 12 * np.log2(pc[valid] / 440), 69 + 12 * np.log2(sc[valid] / 440)
    valid &= abs(pm - sm) <= 0.5

    def can_bridge(left, right):
        begin, end = left["start"] + left["duration"], right["start"]
        if (left["midi"] != right["midi"] or not 0 < end - begin <= 0.25 + 1e-9
                or not strong(left) or not strong(right)):
            return False
        indices = np.flatnonzero((t >= begin - 0.00005) & (t < end - 0.00005))
        if not len(indices):
            return False
        if (t[indices[0]] - begin > 1.5 * hop or end - t[indices[-1]] > 1.5 * hop
                or np.any(np.diff(t[indices]) > 1.5 * hop)):
            return False
        # Weak pitch evidence may be missing briefly; energy may never be missing.
        if not (np.isfinite(e[indices]) & (e[indices] >= -35)).all():
            return False
        if mix is not None and not (np.isfinite(mix[indices]) & (e[indices] - mix[indices] >= -25)).all():
            return False
        good = valid[indices] & (abs(pm[indices] - left["midi"]) <= 0.5) & (abs(sm[indices] - left["midi"]) <= 0.5)
        if np.mean(good) < 0.9:
            return False
        missing = 0
        for present in good:
            missing = 0 if present else missing + 1
            if missing * hop > 0.03 + 1e-9:
                return False
        return True

    result = []
    for i, note in enumerate(clean):
        # Anchor tests use original retained notes, never newly extended evidence.
        if i and can_bridge(clean[i - 1], note):
            start = clean[i - 1]["start"] + clean[i - 1]["duration"]
            changes.append({"action": "bridge", "start": round(start, 4),
                            "end": note["start"], "midi": note["midi"]})
            result[-1]["duration"] = round(note["start"] + note["duration"] - result[-1]["start"], 4)
            result[-1]["confidence"] = min(result[-1]["confidence"], note["confidence"])
        else:
            result.append(dict(note))
    return result, changes

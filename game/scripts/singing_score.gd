extends RefCounted

## Fixed song-time bins prevent frame rate and duplicate callbacks inflating scores.
const STEP = 0.05
var notes: Array = []
var duration: float = 0.0
var reference_offset: float = 0.0
var started: bool = false
var next_bin: int = 0
var samples: Dictionary = {}
var total: int = 0
var voiced: int = 0
var earned: float = 0.0

func configure(reference: Array, song_duration: float, offset: float) -> void:
    notes = reference.duplicate(true)
    notes.sort_custom(func(a, b): return float(a.start) < float(b.start))
    duration = song_duration
    reference_offset = offset

func reset(time: float) -> void:
    started = true
    next_bin = maxi(0, int(ceil(time / STEP)))
    samples.clear()
    total = 0
    voiced = 0
    earned = 0.0

func target_at(time: float) -> float:
    var reference_time = time + reference_offset
    var low = 0
    var high = notes.size()
    while low < high:
        var middle = int((low + high) / 2.0)
        if float(notes[middle].start) <= reference_time:
            low = middle + 1
        else:
            high = middle
    if low == 0:
        return NAN
    var note: Dictionary = notes[low - 1]
    if reference_time >= float(note.start) + float(note.duration):
        return NAN
    return float(note.midi)

static func quality(error_semitones: float) -> float:
    # Full credit within 50 cents, fading to zero at 150 cents.
    return clampf((1.5 - absf(error_semitones)), 0.0, 1.0)

func record(time: float, midi: float, has_voice: bool) -> void:
    if not started or not is_finite(time) or time < 0 or time >= duration:
        return
    var index = int(floor(time / STEP))
    if index < next_bin:
        return
    # Hold at most 100 ms to bridge normal callback jitter, never a stalled stream.
    for bin_index in range(index, index + 3):
        var center = (bin_index + 0.5) * STEP
        var distance = absf(time - center)
        if distance > 0.1 or center >= duration:
            continue
        if not samples.has(bin_index) or distance < float(samples[bin_index].distance):
            samples[bin_index] = {"midi": midi, "voiced": has_voice and is_finite(midi),
                                  "distance": distance}

func advance(time: float) -> void:
    if not started:
        return
    var limit = clampf(time, 0.0, duration)
    while (next_bin + 1) * STEP <= limit + 0.000001:
        var target = target_at((next_bin + 0.5) * STEP)
        if is_finite(target):
            total += 1
            if samples.has(next_bin) and samples[next_bin].voiced:
                voiced += 1
                earned += quality(float(samples[next_bin].midi) - target)
        samples.erase(next_bin)
        next_bin += 1

func result() -> Dictionary:
    return {"points": int(round(10000 * earned / total)) if total > 0 else 0,
            "coverage": 100.0 * voiced / total if total > 0 else 0.0,
            "accuracy": 100.0 * earned / voiced if voiced > 0 else 0.0,
            "evaluated_seconds": total * STEP}

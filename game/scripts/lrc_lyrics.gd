extends RefCounted

static func _digits(value: String) -> bool:
    if value.is_empty():
        return false
    for character in value:
        if character not in "0123456789":
            return false
    return true

static func _timestamp(value: String) -> float:
    var parts = value.split(":")
    if parts.size() != 2 or not _digits(parts[0]):
        return -1.0
    var seconds = parts[1].split(".")
    if seconds.size() > 2 or not _digits(seconds[0]) or int(seconds[0]) >= 60:
        return -1.0
    if seconds.size() == 2 and (not _digits(seconds[1]) or seconds[1].length() > 3):
        return -1.0
    return float(parts[0]) * 60.0 + float(parts[1])

static func parse(content: String, duration: float) -> Dictionary:
    if duration <= 0.0 or not is_finite(duration):
        return {"cues": [], "error": "Invalid song duration"}
    var entries: Array = []
    var offset_ms: int = 0
    var line_number: int = 0
    var metadata = ["ar", "ti", "al", "by", "re", "ve", "length", "au", "tool"]
    for original in content.trim_prefix("\ufeff").split("\n"):
        line_number += 1
        var line: String = original.strip_edges()
        if line.is_empty():
            continue
        var times: Array = []
        while line.begins_with("["):
            var end = line.find("]")
            if end < 0:
                return {"cues": [], "error": "Unclosed tag on line %d" % line_number}
            var token = line.substr(1, end - 1)
            line = line.substr(end + 1).strip_edges()
            var colon = token.find(":")
            var key = token.substr(0, colon).to_lower() if colon >= 0 else ""
            if key == "offset":
                var value = token.substr(colon + 1).strip_edges()
                if not value.is_valid_int():
                    return {"cues": [], "error": "Invalid offset on line %d" % line_number}
                offset_ms = int(value)
                continue
            if key in metadata:
                continue
            var time = _timestamp(token)
            if time < 0.0:
                return {"cues": [], "error": "Invalid timestamp on line %d" % line_number}
            times.append(time)
        if times.is_empty():
            if not line.is_empty():
                return {"cues": [], "error": "Untimed text on line %d" % line_number}
            continue
        if line.contains("<") and line.contains(">"):
            return {"cues": [], "error": "Word-level LRC tags are unsupported (line %d)" % line_number}
        for time in times:
            entries.append({"start": time, "text": line})
    if entries.is_empty():
        return {"cues": [], "error": "No timed verses in LRC"}
    entries.sort_custom(func(a, b): return a.start < b.start)
    var cues: Array = []
    for entry in entries:
        var start = maxf(0.0, float(entry.start) - offset_ms / 1000.0)
        if start >= duration:
            return {"cues": [], "error": "Verse starts beyond song duration"}
        if not cues.is_empty() and is_equal_approx(float(cues[-1].start), start):
            if not entry.text.is_empty():
                var previous: String = cues[-1].text
                cues[-1].text = entry.text if previous.is_empty() else previous + "\n" + entry.text
        else:
            cues.append({"start": start, "end": duration, "text": entry.text})
    for index in range(cues.size() - 1):
        cues[index].end = cues[index + 1].start
    return {"cues": cues, "error": ""}

static func text_at(cues: Array, time: float) -> String:
    # Binary search also works when seeking backwards; no frame accumulation.
    var low = 0
    var high = cues.size()
    while low < high:
        var middle = int((low + high) / 2.0)
        if float(cues[middle].start) <= time:
            low = middle + 1
        else:
            high = middle
    if low == 0 or time >= float(cues[low - 1].end):
        return ""
    return str(cues[low - 1].text)

static func display_at(cues: Array, time: float, preview_seconds: float = 1.0) -> Dictionary:
    var current = text_at(cues, time)
    var upcoming: String = ""
    for cue in cues:
        var start = float(cue.start)
        if start <= time or str(cue.text).is_empty():
            continue
        if start - time <= maxf(preview_seconds, 0.0):
            upcoming = str(cue.text)
        break
    # Before the first verse or during an instrumental gap, preview on the main line.
    if current.is_empty():
        return {"current": upcoming, "next": "", "preview": not upcoming.is_empty()}
    return {"current": current, "next": upcoming, "preview": false}

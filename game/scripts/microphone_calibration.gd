extends RefCounted

## Calibration uses ungained measurements, never the song's reference notes.
static func percentile(values: Array, fraction: float) -> float:
    var sorted = values.duplicate()
    sorted.sort()
    return float(sorted[int((sorted.size() - 1) * fraction)])

static func evaluate(silence: Array, voice: Array) -> Dictionary:
    if silence.size() < 20 or voice.size() < 30:
        return {"error": "Entrada insuficiente. Confira o dispositivo e tente novamente."}
    var noise_levels: Array = []
    var voice_levels: Array = []
    var differences: Array = []
    var noise_voiced = 0
    for sample in silence:
        noise_levels.append(float(sample.rms_db))
        if sample.frequency > 0:
            noise_voiced += 1
    var noise = percentile(noise_levels, 0.9)
    for sample in voice:
        voice_levels.append(float(sample.rms_db))
        if sample.frequency > 0 and sample.rms_db > noise + 10:
            differences.append(1.0 - float(sample.confidence))
    var level = percentile(voice_levels, 0.5)
    if level < -65 or level - noise < 10:
        return {"error": "Voz baixa ou encoberta por ruído. Aproxime o microfone e tente novamente."}
    if noise_voiced > silence.size() * 0.2:
        return {"error": "Som tonal durante o silêncio. Use um ambiente silencioso e tente novamente."}
    if differences.size() < voice.size() * 0.6:
        return {"error": "Voz sem pitch suficiente. Sustente uma vogal no seu tom confortável; confira o microfone ou teste uma conexão com fio."}
    var gain = clampf(-20.0 - level, 0, 30)
    return {"gain_db": gain, "gate_db": clampf(noise + gain + 8, -70, -20),
            "threshold": clampf(percentile(differences, 0.9) + 0.03, 0.15, 0.30),
            "noise_db": noise, "voice_db": level}

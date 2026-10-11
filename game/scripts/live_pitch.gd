extends RefCounted

## Lightweight YIN-style estimator for a single voice; no ML or reference input.
static func estimate(samples: PackedFloat32Array, rate: float, gate_db: float = -45.0) -> Dictionary:
    var empty = {"frequency": 0.0, "midi": 0.0, "confidence": 0.0, "rms_db": -120.0}
    if rate <= 0 or samples.size() < 512:
        return empty
    var mean: float = 0.0
    for value in samples:
        if not is_finite(value):
            return empty
        mean += value
    mean /= samples.size()
    var centered = samples.duplicate()
    var power: float = 0.0
    for index in range(centered.size()):
        centered[index] -= mean
        power += centered[index] * centered[index]
    empty.rms_db = linear_to_db(maxf(sqrt(power / samples.size()), 0.000001))
    if empty.rms_db < gate_db:
        return empty
    var min_lag = maxi(2, int(floor(rate / 1000.0)))
    var max_lag = mini(int(ceil(rate / 65.0)), int(samples.size() / 2.0) - 1)
    if min_lag >= max_lag:
        return empty
    var count = samples.size() - max_lag
    var difference = PackedFloat32Array()
    difference.resize(max_lag + 1)
    difference[0] = 1.0
    var cumulative: float = 0.0
    for lag in range(1, max_lag + 1):
        var squared: float = 0.0
        for index in range(count):
            var delta = centered[index] - centered[index + lag]
            squared += delta * delta
        cumulative += squared
        difference[lag] = squared * lag / cumulative if cumulative > 0 else 1.0
    # The first good minimum avoids selecting a later multiple of the period.
    for lag in range(min_lag, max_lag):
        if difference[lag] < 0.15 and difference[lag] <= difference[lag + 1]:
            var period: float = lag
            var denominator = difference[lag - 1] - 2 * difference[lag] + difference[lag + 1]
            if absf(denominator) > 0.000001:
                period += clampf(0.5 * (difference[lag - 1] - difference[lag + 1]) / denominator,
                                 -0.5, 0.5)
            var frequency = rate / period
            if frequency < 65 or frequency > 1000:
                return empty
            return {"frequency": frequency, "midi": 69 + 12 * log(frequency / 440.0) / log(2.0),
                    "confidence": 1.0 - difference[lag], "rms_db": empty.rms_db}
    return empty

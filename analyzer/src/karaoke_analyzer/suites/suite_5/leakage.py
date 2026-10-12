"""Conservative, pitch-specific evidence of accompaniment leakage."""
from pathlib import Path

import numpy as np
import soundfile as sf

SAMPLE_RATE = 22050
FFT_SIZE = 4096
RATIO_DB = -12.0
MIN_HARMONICS = 3
MIN_DURATION = 0.12


def compare_harmonics(vocal_power, accompaniment_power, frequencies, f0):
    """Reject only when several actual accompaniment peaks dominate this F0."""
    if not np.isfinite(f0) or f0 <= 0:
        return np.nan, 0
    vocal_sum, accompaniment_sum, votes = 0.0, 0.0, 0
    for harmonic in range(1, 6):
        target = f0 * harmonic
        if target >= frequencies[-1]:
            break
        width = max(SAMPLE_RATE / FFT_SIZE, target * (2 ** (0.5 / 12) - 1))
        band = abs(frequencies - target) <= width
        neighborhood = (abs(frequencies - target) <= max(100, 4 * width)) & ~band
        if not band.any() or not neighborhood.any():
            continue
        vp = float(np.max(vocal_power[band]))
        ap = float(np.max(accompaniment_power[band]))
        background = float(np.median(accompaniment_power[neighborhood]))
        # Broadband accompaniment is not evidence of matching pitched content.
        if ap <= 0 or ap < 4 * background:
            continue
        vocal_sum += vp / harmonic
        accompaniment_sum += ap / harmonic
        if vp <= ap * 10 ** (RATIO_DB / 10):
            votes += 1
    if accompaniment_sum <= 0:
        return np.nan, 0
    ratio = 10 * np.log10(max(vocal_sum / accompaniment_sum, np.finfo(float).tiny))
    return float(ratio), votes


def sustained_leakage(times, ratios, votes):
    candidate = np.isfinite(ratios) & (ratios <= RATIO_DB) & (votes >= MIN_HARMONICS)
    rejected = np.zeros(len(times), bool)
    if len(times) < 2:
        return rejected
    hop = float(np.median(np.diff(times)))
    i = 0
    while i < len(times):
        if not candidate[i]:
            i += 1
            continue
        end = i + 1
        while end < len(times) and candidate[end] and times[end] - times[end - 1] <= 1.5 * hop:
            end += 1
        if times[end - 1] - times[i] + hop >= MIN_DURATION - 1e-9:
            rejected[i:end] = True
        i = end
    return rejected


def harmonic_leakage(vocals: Path, accompaniment: Path, times, f0):
    t, pitches = np.asarray(times, float), np.asarray(f0, float)
    if (t.ndim != 1 or pitches.shape != t.shape or not np.all(np.isfinite(t))
            or np.any(t < 0) or np.any(np.diff(t) <= 0)):
        raise ValueError("Harmonic comparison requires matching pitches and increasing timestamps")
    import librosa

    signals, lengths = [], []
    for path in (vocals, accompaniment):
        audio, rate = sf.read(str(path), dtype="float32", always_2d=True)
        if not len(audio) or not np.all(np.isfinite(audio)):
            raise ValueError("Harmonic comparison requires finite nonempty stems")
        audio = librosa.resample(audio, orig_sr=rate, target_sr=SAMPLE_RATE, axis=0)
        lengths.append(len(audio))
        signals.append(np.pad(audio, ((FFT_SIZE // 2, FFT_SIZE // 2), (0, 0))))
    if lengths[0] != lengths[1]:
        raise ValueError("Vocal and accompaniment stems must have equal duration")
    # Centered pYIN may emit one frame slightly beyond the final sample.
    if len(t) and t[-1] > lengths[0] / SAMPLE_RATE + 256 / SAMPLE_RATE:
        raise ValueError("Harmonic timestamps exceed stem duration")
    ratios, votes = np.full(len(t), np.nan), np.zeros(len(t), int)
    frequencies = np.fft.rfftfreq(FFT_SIZE, 1 / SAMPLE_RATE)
    window = np.hanning(FFT_SIZE)[:, None]
    for i in np.flatnonzero(np.isfinite(pitches) & (pitches > 0)):
        center = min(round(t[i] * SAMPLE_RATE), lengths[0] - 1)
        spectra = [np.mean(abs(np.fft.rfft(signal[center:center + FFT_SIZE] * window,
                                         axis=0)) ** 2, axis=1) for signal in signals]
        ratios[i], votes[i] = compare_harmonics(*spectra, frequencies, pitches[i])
    return sustained_leakage(t, ratios, votes), ratios, votes

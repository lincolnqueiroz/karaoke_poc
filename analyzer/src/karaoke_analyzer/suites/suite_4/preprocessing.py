"""HPSS harmonic preprocessing without modifying the reference input."""
import json
from pathlib import Path

import numpy as np
import soundfile as sf


def harmonic_reference(source: Path, destination: Path) -> Path:
    if source.resolve() == destination.resolve():
        raise ValueError("HPSS output must not overwrite its input")
    if not source.is_file():
        raise ValueError("HPSS input must be an existing audio file")
    audio, rate = sf.read(str(source), dtype="float32", always_2d=True)
    if not len(audio) or not np.all(np.isfinite(audio)):
        raise ValueError("HPSS input must contain finite audio samples")
    import librosa

    harmonic, _ = librosa.effects.hpss(
        audio.T, kernel_size=31, power=2.0, margin=1.0,
        n_fft=2048, hop_length=512, center=True)
    if harmonic.shape != audio.T.shape or not np.all(np.isfinite(harmonic)):
        raise RuntimeError("HPSS returned invalid or misaligned audio")
    destination.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(destination), harmonic.T, rate, subtype="FLOAT")
    destination.with_suffix(".json").write_text(
        json.dumps({"method": "HPSS", "component": "harmonic", "kernel_size": 31,
                    "power": 2.0, "margin": 1.0, "n_fft": 2048, "hop_length": 512,
                    "sample_rate": rate, "samples": len(audio),
                    "energy_reference": "unfiltered"}, indent=2), encoding="utf-8")
    return destination

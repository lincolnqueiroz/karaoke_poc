"""Explicit Demucs configuration, isolated from previous suites."""
import json
import subprocess
from pathlib import Path

from ...runtime import demucs_command, subprocess_options

MODEL = "htdemucs"
SHIFTS = 4
OVERLAP = 0.50


def separate_vocals(source: Path, output_dir: Path, device: str = "cpu") -> Path:
    if not source.is_file() or source.suffix.lower() != ".mp3":
        raise ValueError("Suite 6 separation requires an existing MP3")
    if device not in {"cpu", "cuda"}:
        raise ValueError("Demucs device must be cpu or cuda")
    output_dir.mkdir(parents=True, exist_ok=True)
    command = [*demucs_command(), "-n", MODEL, "--two-stems", "vocals",
               "--other-method", "add", "--shifts", str(SHIFTS),
               "--overlap", str(OVERLAP), "--float32", "--clip-mode", "none",
               "-d", device, "-o", str(output_dir), str(source)]
    try:
        subprocess.run(command, check=True, capture_output=True, text=True, **subprocess_options())
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"Demucs failed: {(exc.stderr or str(exc))[-3000:]}") from exc
    stem_dir = output_dir / MODEL / source.stem
    for name in ("vocals.wav", "no_vocals.wav"):
        if not (stem_dir / name).is_file():
            raise RuntimeError(f"Demucs did not create expected output: {stem_dir / name}")
    (output_dir.parent / "demucs-config-debug.json").write_text(
        json.dumps({"model": MODEL, "shifts": SHIFTS, "overlap": OVERLAP,
                    "float32": True, "clip_mode": "none", "other_method": "add",
                    "segment": "model_default", "device": device,
                    "random_shifts": True}, indent=2), encoding="utf-8")
    return stem_dir / "vocals.wav"

"""Optional Demucs vocal separation via its command-line interface."""
import subprocess
from pathlib import Path

from .runtime import demucs_command, subprocess_options


def separate_vocals(source: Path, output_dir: Path, device: str = "cpu") -> Path:
    """Return separated vocals path. Requires optional `demucs` dependency.

    Run on original stereo audio to preserve separation quality.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    cmd = [*demucs_command(), "--two-stems", "vocals", "-d", device,
           "-o", str(output_dir), str(source)]
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True, **subprocess_options())
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"Demucs failed: {exc.stderr[-3000:]}") from exc
    # Demucs default model output directory
    vocals = output_dir / "htdemucs" / source.stem / "vocals.wav"
    if not vocals.exists():
        raise RuntimeError(f"Demucs did not create expected output: {vocals}")
    return vocals

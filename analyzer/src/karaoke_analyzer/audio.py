"""Audio decoding through an explicit FFmpeg subprocess."""
import shutil
import subprocess
from pathlib import Path

from .runtime import subprocess_options


def decode_to_wav(source: Path, destination: Path, sample_rate: int = 22050) -> Path:
    if not source.is_file() or source.suffix.lower() != ".mp3":
        raise ValueError(f"Expected an existing MP3 file: {source}")
    if shutil.which("ffmpeg") is None:
        raise RuntimeError("FFmpeg not found on PATH. Install FFmpeg before analyzing MP3s.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    command = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i",
               str(source), "-vn", "-ac", "1", "-ar", str(sample_rate), str(destination)]
    try:
        subprocess.run(command, check=True, capture_output=True, text=True, **subprocess_options())
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"FFmpeg failed: {exc.stderr.strip()}") from exc
    return destination

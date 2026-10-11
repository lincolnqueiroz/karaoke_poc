"""Optional YouTube audio downloader, independent of analysis and ML dependencies."""

import argparse
import importlib.util
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

WORKSPACE = Path(__file__).resolve().parents[3] / "workspace"


def download_audio(url: str, output: Path, ffmpeg_location: Path | None = None) -> Path:
    """Download one video's audio to a new MP3 under the ignored workspace."""
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or parsed.hostname not in {
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"
    } or parsed.username or parsed.password or parsed.port not in (None, 443)):
        raise ValueError("Use an HTTPS YouTube video URL.")
    output = output.resolve()
    if output.suffix.lower() != ".mp3" or not output.is_relative_to(WORKSPACE.resolve()):
        raise ValueError(f"Output must be an MP3 inside {WORKSPACE}.")
    if output.exists():
        raise FileExistsError(f"Output already exists: {output}")
    tool_dir = ffmpeg_location.resolve() if ffmpeg_location else None
    for tool in ("ffmpeg", "ffprobe"):
        location = shutil.which(tool, path=str(tool_dir) if tool_dir else None)
        if location is None:
            raise RuntimeError(f"{tool} not found; use --ffmpeg-location with its bin directory.")
    if importlib.util.find_spec("yt_dlp") is None:
        raise RuntimeError("Install the optional downloader: python -m pip install -e '.[youtube]'")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Download and transcode in isolation; never overwrite an existing user file.
    with tempfile.TemporaryDirectory(prefix="youtube-", dir=output.parent) as temporary:
        command = [
            sys.executable, "-m", "yt_dlp", "--ignore-config", "--no-playlist",
            "--no-overwrites", "--no-cache-dir", "--socket-timeout", "30",
            "--retries", "3", "-f", "bestaudio/best", "--extract-audio",
            "--audio-format", "mp3", "--audio-quality", "0",
            "-o", str(Path(temporary) / "audio.%(ext)s"),
        ]
        if tool_dir:
            command.extend(["--ffmpeg-location", str(tool_dir)])
        command.extend(["--", url])
        try:
            subprocess.run(command, check=True)
        except subprocess.CalledProcessError as exc:
            raise RuntimeError(f"yt-dlp failed with exit code {exc.returncode}.") from exc
        except OSError as exc:
            raise RuntimeError(f"Could not start yt-dlp: {exc}") from exc
        audio = Path(temporary) / "audio.mp3"
        if not audio.is_file() or audio.stat().st_size == 0:
            raise RuntimeError("yt-dlp did not produce a nonempty MP3.")
        with audio.open("rb") as source, output.open("xb") as destination:
            shutil.copyfileobj(source, destination)
    return output


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Download authorized YouTube audio as MP3")
    parser.add_argument("url", help="HTTPS YouTube video URL")
    parser.add_argument("--output", type=Path, required=True, help="New MP3 path under workspace/")
    parser.add_argument("--ffmpeg-location", type=Path, help="Directory containing FFmpeg/FFprobe")
    args = parser.parse_args(argv)
    try:
        result = download_audio(args.url, args.output, args.ffmpeg_location)
    except (ValueError, OSError, RuntimeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    print(f"Downloaded: {result}")
    return 0

"""Paths and child-process commands shared by source and packaged execution."""
import os
import subprocess
import sys
from pathlib import Path


def packaged() -> bool:
    return bool(getattr(sys, "frozen", False))


def bundle_root() -> Path:
    return Path(sys.executable).resolve().parent.parent


def data_root() -> Path:
    if packaged():
        local = os.environ.get("LOCALAPPDATA")
        if not local:
            raise RuntimeError("LOCALAPPDATA indisponível")
        return Path(local) / "KaraokePoC"
    return Path(__file__).resolve().parents[3] / "workspace"


def demucs_command() -> list[str]:
    if packaged():
        return [sys.executable, "--demucs"]
    module = "karaoke_analyzer.demucs_runner" if os.environ.get("KARAOKE_OFFLINE_MODELS") == "1" else "demucs"
    return [sys.executable, "-m", module]


def subprocess_options() -> dict:
    return {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}

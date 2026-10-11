"""Publish a completed analysis to the local song library without overwriting songs."""
import argparse
import json
import os
import re
import shutil
import time
import uuid
from pathlib import Path

from .pipeline import analyze
from .runtime import bundle_root, data_root, packaged

WORKSPACE = data_root()


def write_status(path: Path, state: str, progress: float, message: str, **extra):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps({"state": state, "progress": progress,
                                    "message": message, **extra}, ensure_ascii=False),
                         encoding="utf-8")
    # Windows readers may briefly hold the current status file without delete sharing.
    for attempt in range(20):
        try:
            temporary.replace(path)
            break
        except PermissionError:
            if attempt == 19:
                raise
            time.sleep(0.01)


def import_song(source: Path, output_root: Path, status: Path, lyrics: Path | None = None,
                separate: bool = True, device: str = "cuda",
                allow_model_download: bool = False, ffmpeg_location: Path | None = None,
                storage_root: Path | None = None, title: str | None = None,
                artist: str = ""):
    source, output_root, status = source.resolve(), output_root.resolve(), status.resolve()
    workspace = (storage_root or WORKSPACE).resolve()
    for path in (output_root, status):
        if not path.is_relative_to(workspace.resolve()):
            raise ValueError("Saídas da importação devem ficar dentro de workspace")
    if status == source or (lyrics is not None and status == lyrics.resolve()):
        raise ValueError("O status da importação não pode sobrescrever arquivos de entrada")
    old_path = os.environ.get("PATH", "")
    old_offline = os.environ.get("KARAOKE_OFFLINE_MODELS")
    old_torch_home = os.environ.get("TORCH_HOME")
    old_hf_home = os.environ.get("HF_HOME")
    staging = workspace / "import-jobs" / uuid.uuid4().hex / "song"
    try:
        write_status(status, "running", 0.0, "Preparando importação")
        if title is not None and not title.strip():
            raise ValueError("Informe o título da música")
        if len(title or "") > 200 or len(artist) > 200:
            raise ValueError("Título e artista devem ter no máximo 200 caracteres")
        if packaged():
            ffmpeg_location = ffmpeg_location or bundle_root() / "tools" / "ffmpeg"
            cache = workspace / "models"
            bundled_cache = bundle_root() / "models"
            if bundled_cache.is_dir():
                shutil.copytree(bundled_cache, cache, dirs_exist_ok=True)
            os.environ["TORCH_HOME"] = str(cache / "torch")
            os.environ["HF_HOME"] = str(cache / "huggingface")
        if not source.is_file() or source.suffix.lower() != ".mp3":
            raise ValueError("Selecione um arquivo MP3 existente")
        if lyrics is not None:
            lyrics = lyrics.resolve()
            if not lyrics.is_file() or lyrics.suffix.lower() != ".lrc":
                raise ValueError("Selecione uma letra LRC existente")
            lyrics.read_text(encoding="utf-8-sig")
        if ffmpeg_location is not None:
            if not ffmpeg_location.is_dir():
                raise ValueError("A pasta do FFmpeg não existe")
            os.environ["PATH"] = str(ffmpeg_location.resolve()) + os.pathsep + old_path
        if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
            raise RuntimeError("FFmpeg e FFprobe precisam estar no PATH ou na pasta informada")
        if separate and device == "cuda":
            import torch
            if not torch.cuda.is_available():
                raise RuntimeError("CUDA indisponível. Selecione CPU ou confira o PyTorch CUDA")
        if separate:
            os.environ["KARAOKE_OFFLINE_MODELS"] = "0" if allow_model_download else "1"
        staging.mkdir(parents=True)
        manifest = analyze(source, staging, separate, device,
                           progress=lambda fraction, message: write_status(
                               status, "running", fraction, message))
        if not manifest.is_file():
            raise RuntimeError("A análise não produziu song.json")
        data = json.loads(manifest.read_text(encoding="utf-8"))
        if title is not None:
            data["title"] = title.strip()
            manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        (staging / "metadata.json").write_text(
            json.dumps({"artist": artist.strip()}, ensure_ascii=False, indent=2), encoding="utf-8")
        slug = re.sub(r"[^\w-]+", "_", source.stem, flags=re.UNICODE).strip("_-")[:80]
        slug = slug or "musica"
        if slug.upper() in {"CON", "PRN", "AUX", "NUL", *[f"COM{i}" for i in range(1, 10)],
                            *[f"LPT{i}" for i in range(1, 10)]}:
            slug = "musica_" + slug
        if lyrics is not None:
            lyric_dir = staging / "lyrics"
            lyric_dir.mkdir()
            shutil.copy2(lyrics, lyric_dir / (slug + ".lrc"))
        output_root.mkdir(parents=True, exist_ok=True)
        for index in range(1, 10000):
            destination = output_root / (slug if index == 1 else f"{slug}_{index}")
            if destination.exists():
                continue
            try:
                staging.rename(destination)
            except FileExistsError:
                continue
            break
        else:
            raise RuntimeError("Não foi possível reservar um diretório para a música")
        message = "Música importada e disponível para jogar."
        if not data.get("notes"):
            message = "Música importada, mas nenhuma nota foi detectada. Confira a referência antes de pontuar."
        write_status(status, "complete", 1.0, message, manifest=str(destination / "song.json"))
        return destination / "song.json"
    except Exception as exc:
        write_status(status, "error", 0.0, str(exc), diagnostics=str(staging.parent))
        raise
    finally:
        os.environ["PATH"] = old_path
        if old_offline is None:
            os.environ.pop("KARAOKE_OFFLINE_MODELS", None)
        else:
            os.environ["KARAOKE_OFFLINE_MODELS"] = old_offline
        if old_torch_home is None:
            os.environ.pop("TORCH_HOME", None)
        else:
            os.environ["TORCH_HOME"] = old_torch_home
        if old_hf_home is None:
            os.environ.pop("HF_HOME", None)
        else:
            os.environ["HF_HOME"] = old_hf_home


def main():
    parser = argparse.ArgumentParser(description="Import an MP3 into the local karaoke library")
    parser.add_argument("source", type=Path)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--status", type=Path, required=True)
    parser.add_argument("--lyrics", type=Path)
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cuda")
    parser.add_argument("--without-separation", action="store_true")
    parser.add_argument("--allow-model-download", action="store_true")
    parser.add_argument("--ffmpeg-location", type=Path)
    parser.add_argument("--data-root", type=Path)
    parser.add_argument("--title", help="Display title; defaults to the filename for older callers")
    parser.add_argument("--artist", default="")
    args = parser.parse_args()
    try:
        import_song(args.source, args.output_root, args.status, args.lyrics,
                    not args.without_separation, args.device,
                    args.allow_model_download, args.ffmpeg_location, args.data_root,
                    args.title, args.artist)
    except Exception as exc:  # noqa: BLE001 - CLI boundary reports errors to the UI.
        parser.exit(1, f"Importação falhou: {exc}\n")


if __name__ == "__main__":
    main()

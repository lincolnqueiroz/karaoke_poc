"""Collect locally available license texts into a Windows release package."""
import argparse
import shutil
import sys
from importlib import metadata
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("--ffmpeg-license", required=True, type=Path)
    args = parser.parse_args()
    package = args.package.resolve(strict=True)
    internal = package / "analyzer/_internal"
    if not internal.is_dir():
        parser.error("The package must contain analyzer/_internal")
    licenses = package / "licenses"
    licenses.mkdir(exist_ok=True)
    shutil.copy2(Path(sys.base_prefix) / "LICENSE.txt", licenses / "Python-LICENSE.txt")
    shutil.copy2(args.ffmpeg_license, licenses / "FFmpeg-GPLv3.txt")
    modules = {p.name.split(".")[0] for p in internal.iterdir()}
    mapping = metadata.packages_distributions()
    names = {name for module in modules for name in mapping.get(module, [])}
    names.update(("PyInstaller", "torch", "torchaudio", "demucs", "librosa", "numpy", "scipy", "soundfile"))
    rows = []
    for name in sorted(names, key=str.lower):
        dist = metadata.distribution(name)
        count = 0
        for item in dist.files or []:
            if not any(word in item.name.lower() for word in ("license", "copying", "notice")):
                continue
            source = Path(dist.locate_file(item))
            if not source.is_file():
                continue
            safe_parts = ["_parent_" if part == ".." else part for part in item.parts]
            destination = licenses / name / Path(*safe_parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            count += 1
        rows.append(f'{dist.metadata["Name"]}=={dist.version} | copied notice files: {count}')
    (licenses / "INVENTORY.txt").write_text("\n".join(rows) + "\n", encoding="utf-8")
    (package / "THIRD-PARTY-NOTICES.txt").write_text(
        "Karaoke PoC 0.1\n\n"
        "Godot Engine 4.7.2: https://godotengine.org/license/\n"
        "Python and analysis dependency license texts are provided in licenses/.\n"
        "FFmpeg GPLv3 license text is provided in licenses/FFmpeg-GPLv3.txt.\n"
        "Corresponding-source arrangements for the exact FFmpeg binary remain a publication check.\n"
        "Demucs weights: ade fossez / HTDemucs; verify weight redistribution terms.\n"
        "Menu music, effects and artwork were supplied locally by the user; record their provenance and redistribution terms.\n"
        "This inventory is not a complete redistribution compliance certification.\n",
        encoding="utf-8",
    )
    print(f"Collected notices for {len(rows)} distributions")


if __name__ == "__main__":
    main()

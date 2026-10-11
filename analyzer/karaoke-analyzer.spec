"""Windows onedir bundle including optional separation dependencies."""
from pathlib import Path
from PyInstaller.utils.hooks import collect_all, copy_metadata

root = Path(SPECPATH)
datas, binaries, hiddenimports = [], [], []
for package in ("karaoke_analyzer", "librosa", "soundfile", "demucs", "torch", "torchaudio", "julius", "huggingface_hub", "safetensors", "sphn", "lameenc"):
    package_data, package_binaries, package_imports = collect_all(package)
    datas += package_data
    binaries += package_binaries
    hiddenimports += package_imports
for distribution in ("demucs", "torch", "torchaudio", "librosa", "soundfile"):
    datas += copy_metadata(distribution)

a = Analysis([str(root / "packaged_entry.py")], pathex=[str(root / "src")],
             binaries=binaries, datas=datas, hiddenimports=hiddenimports,
             excludes=["pytest", "ruff", "yt_dlp"], noarchive=False,
             module_collection_mode={"librosa": "py"})
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name="karaoke-analyzer",
          debug=False, strip=False, upx=False, console=True)
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, name="karaoke-analyzer")

# AGENTS.md — Karaoke PoC

## Mission
Build a local-first karaoke proof of concept. Given a legally usable MP3 containing lead vocals, generate a time-aligned melody reference and render it in Godot 4. The initial scope excludes microphone input, scoring, lyrics transcription, multiplayer, cloud services and shipping copyrighted songs.

## Architecture and boundaries
- `analyzer/`: Python 3.11 CLI for offline music analysis. It owns decoding, separation, pitch tracking, note segmentation and JSON export.
- `game/`: Godot 4 GDScript app. It reads the exported JSON and audio. Do not embed Python or ML inference in Godot.
- `docs/song-schema-v1.md`: the integration contract. Any schema change must update documentation, tests and both consumers. Preserve backward compatibility when practical.
- `workspace/`: generated/user-provided audio and analysis outputs. Never commit its contents.
- The pipeline must be independently testable without a GPU or downloading ML models; isolate heavyweight dependencies and mock them in unit tests.

## Working practices
1. Inspect existing code, tests and docs before changing behavior.
2. Prefer small, reviewable changes with one responsibility per module.
3. Do not claim a command or GPU path works unless it was actually executed; state what remains unverified.
4. Keep Python dependency installation explicit; install a CUDA-enabled PyTorch wheel following the official PyTorch selector for the machine's driver/runtime. Never silently replace a CUDA build with CPU-only packages.
5. Never download untrusted executable binaries or arbitrary model weights without user approval. Model weights may be fetched through the chosen library after approval.
6. Preserve original MP3; do not overwrite input files. Never commit music, separated stems, caches or large weights.
7. Validate input paths, output directories, subprocess failures and schema constraints. Prefer explicit errors over silent fallbacks.
8. Treat pitch extraction as an estimate, not ground truth: retain raw diagnostic data, confidence/voicing and expose limitations (backing vocals, harmonies, pitch octave errors).
9. Use seconds for all song timings, MIDI note numbers for pitch, and UTF-8 JSON. Maintain synchronization using audio playback time, not wall-clock frame accumulation.
10. No scope creep: first deliver analysis and synchronized note visualization, then microphone input and scoring in separate phases.

## Commands (Windows PowerShell)
```powershell
cd analyzer
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
# Install torch/torchaudio from the matching CUDA command at https://pytorch.org/get-started/locally/
pip install -e '.[dev]'
pytest
ruff check .
python -m karaoke_analyzer --help
python -m karaoke_analyzer analyze '..\samples\example.mp3' --output '..\workspace\songs\example'
```
Requires `ffmpeg` and `ffprobe` on PATH for audio conversion. Godot project is `game/project.godot`.

## Acceptance criteria for the first milestone
- CLI can validate and decode an MP3 to a standardized WAV using FFmpeg.
- Audio analysis exports schema v1 with note start, duration, MIDI and confidence; produces useful diagnostics.
- Unit tests run without a GPU, FFmpeg, or downloading model weights (integration tests may require them).
- Godot can load an exported song manifest and visualize notes synchronized with playback.
- README explains Windows setup, CUDA verification, failure modes, and reproduction steps.

## Agent response format
After each implementation: summarize changes, commands actually run and their results, any remaining risks, and one suggested next step. Ask before adding substantial dependencies or changing the data contract.

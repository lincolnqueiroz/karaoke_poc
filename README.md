# Karaoke PoC — Windows + NVIDIA + Godot 4

Local-first proof of concept: analyze an MP3 offline into time-aligned note segments and preview them in Godot 4.

Windows packaging and production paths: [distribution guide](docs/windows-distribution.md).

## Prerequisites
- Windows 10/11, Python **3.11** (baseline) or **3.15** (experimental setup), Git, Godot **4.x**, NVIDIA driver, VS Code and Codex CLI.
- FFmpeg and FFprobe available on `PATH` (`ffmpeg -version`).
- NVIDIA CUDA-capable GPU recommended, not required. Verify driver with `nvidia-smi`.

## Python setup (PowerShell)
```powershell
cd analyzer
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
# For NVIDIA acceleration, install PyTorch and torchaudio using the *current*
# matching Windows/Pip/Python/CUDA command from https://pytorch.org/get-started/locally/
python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
python -m pip install -e '.[dev,separation]'
python -m pytest
python -m ruff check .
```

If you want to validate the lightweight baseline before installing Demucs, use `pip install -e '.[dev]'`. For CUDA, `torch.cuda.is_available()` should print `True`; otherwise check the installed torch wheel and NVIDIA driver. Demucs is optional and its PyTorch dependencies may require version compatibility adjustments. Do not blindly reinstall torch if pip proposes replacing your CUDA wheel.

### Experimental Python 3.15 setup

Python 3.15 is accepted alongside the original 3.11 baseline; other Python minor
versions remain outside the declared support range. Compatibility on 3.15 is
not yet validated. To create its environment, use `py -3.15 -m venv .venv`,
or the explicit path to the installed Python 3.15 executable if the launcher
does not detect it. Activate with `.\.venv\Scripts\Activate.ps1`, then install
the baseline with `python -m pip install -e '.[dev]'` and run the checks above.

The local 3.15 venv executes successfully, but dependency installation failed
because access to PyPI was denied (`WinError 10013`). A CUDA installation attempt
against `https://download.pytorch.org/whl/cu126` found no matching torch wheel.
The [PyTorch 2.13 release notes](https://pytorch.org/blog/pytorch-2-13-release-blog/)
specifically limit their Python 3.15 wheels to Linux; that release does not provide
Windows 3.15 wheels. Do not assume GPU support from a working Python environment.
Tests, CLI, Demucs and CUDA remain unvalidated on 3.15. See
`docs/environment-validation.md` for the commands and current results.

## Analyze a song

### Download authorized YouTube audio

From `analyzer/`, install the optional downloader in the same venv and run:

```powershell
python -m pip install -e '.[youtube]'
python download_youtube.py 'https://www.youtube.com/watch?v=VIDEO_ID' --output '..\workspace\downloads\song.mp3'
```

Use videos you own or have permission to download and use. The script downloads
one video, converts its audio to MP3 with FFmpeg, and refuses to overwrite an
existing output. Output must be under the ignored `workspace/` directory.
If FFmpeg is unavailable in the current terminal, supply its bin directory:

```powershell
python download_youtube.py 'https://youtu.be/VIDEO_ID' --output '..\workspace\downloads\song.mp3' --ffmpeg-location 'D:\Downloads\ffmpeg-master-latest-win64-gpl-shared\ffmpeg-master-latest-win64-gpl-shared\bin'
```

Both FFmpeg and FFprobe are required. YouTube extraction may additionally need
a supported JavaScript runtime (such as Deno) as described in the
[yt-dlp documentation](https://github.com/yt-dlp/yt-dlp#dependencies).
The script does not install runtimes or download models. Network failures,
unavailable videos and extraction errors are reported with a nonzero exit code.
MP3 conversion is lossy and does not improve the source audio quality.

### Run the analyzer
```powershell
python -m karaoke_analyzer analyze ..\samples\example.mp3 --output ..\workspace\songs\example
# After optional Demucs installation and CUDA verification:
python -m karaoke_analyzer analyze ..\samples\example.mp3 --output ..\workspace\songs\example --separate --device cuda
```

**Important:** Without `--separate`, pitch tracking runs on the entire mix and can be inaccurate. The first run of Demucs may download pretrained model weights. Demucs may require substantial VRAM/RAM. On CUDA errors, retry `--device cpu`.

Generated output: `original.mp3`, `analysis.wav`, `pitch-debug.csv`, `pitch-secondary-debug.csv`, `pitch-consensus-debug.csv`, `activity-debug.csv`, `recovery-debug.csv`, `song.json` and optionally `stems/`. No MP3s are distributed.

## Godot preview
1. Open `game/project.godot` with Godot 4 and run the main scene.
   The main menu offers **Jogar**, **Configurações** and **Sair**. **Jogar** opens
   a song selector; selecting a song opens its karaoke preparation screen.
   **Configurações** saves microphone device and gain locally, across restarts.
   **Sair** closes the game. **Menu principal** returns from karaoke.
2. The current scene is configured to open the local analyzed song at
   `game/demo/como_eu_quero/song.json`. Its manifest and original MP3 were copied
   locally and the folder is ignored by Git. Press **F6** for the open player
   scene or **F5** for the main menu. Playback waits on the preparation screen.
   On a fresh checkout, set the root node's `song_manifest` to
   `res://demo/song.json` to use the committed synthetic, silent demo.
3. To preview an analyzed song, copy the output folder under `game/demo/your-song/` and set the scene root's `song_manifest` export property to `res://demo/your-song/song.json`. This is an interim manual integration step.

The selector discovers `song.json` in `game/demo/<song>/` and, in this local
development workspace, `workspace/songs/<song>/`. A valid schema v1 manifest
and its original audio are required. Copies with the same folder name appear
once, preferring `game/demo`. LRC files in each song's `lyrics/` folder are
associated automatically, preferring the matching folder name. Invalid entries
are reported in the selector. Return to the selector to refresh imported songs.
The silent synthetic demo is excluded. Exported games should include songs
under `game/demo`; the workspace path is a development convenience.

### Import songs from the selector

Open **Jogar → Importar música**, choose a local MP3 and optionally its LRC,
then start the import. The screen uses the existing analyzer venv, offers
Demucs with CUDA/CPU, and shows processing stages without blocking gameplay UI.
Completed songs appear automatically in the selector. Existing files are
preserved. Model downloads are disabled unless explicitly enabled in the form.
See [import setup, files, failure handling and tests](docs/song-import.md).

The timeline shows an **8-second rolling window** with a fixed yellow cursor at
25% of its width: two seconds of history and six seconds ahead. Notes move left
using the audio playback position. The window keeps the same scale at the song's
start and end; empty space represents time outside the song. Adjust **Window
Seconds** and **Cursor Position** on the `KaraokePlayer` root node in the Inspector.
Notes crossing the window edges are clipped to the visible region.
The top readout shows the current **audio time** and total duration as
`mm:ss.mmm`. The bottom ruler labels absolute song times for the scrolling
notes. With a visual offset, ruler time at the cursor differs from audio time
by that offset; use the top audio readout when reporting problematic passages
(for example, `00:35.200–00:38.500: continuous vocals without notes`).

The playback clock includes time since the last audio mix and compensates for
output latency, following the [Godot audio synchronization guidance](https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html).
It ignores small backwards clock jitter. If notes still appear consistently
late, increase **Visual Offset Seconds** on the root node (start with **0.05**,
then try **0.10** seconds); positive values bring notes to the cursor earlier,
negative values delay them. The default is zero: no song-specific shift is
assumed. This display adjustment leaves audio and exported note timings intact.
It cannot fix varying onset errors from pitch estimation or confidence filtering.

For headless timeline checks, run Godot with
`--headless --path game --script res://tests/test_timeline.gd` from the project root.

### Timed lyrics (LRC)

The player displays the current verse below the notes using the audio clock,
independently of **Visual Offset Seconds**. The local song's LRC was copied from
`workspace/songs/como_eu_quero/lyrics/como_eu_quero.lrc` to the ignored
`game/demo/como_eu_quero/lyrics/` folder. To refresh edits, copy that file again.
For another song, set **Lyrics File** on the `KaraokePlayer` root node to its
LRC path (leave empty to disable lyrics). No manifest/schema changes are needed.

The first verse appears one second before its timestamp. During singing, the
next verse appears on a second line one second early, then moves to the main
line at its timestamp. The current verse stays until its original end. Empty
timed cues still clear instrumental gaps; previews use a softer color.

Save LRC as UTF-8, with timestamps such as `[00:12.34] Example verse`.
Whole seconds, hundredths and milliseconds, repeated timestamps per line,
common metadata and `[offset:100]` are supported. A positive LRC offset advances
lyrics by that many milliseconds. Each verse lasts until the next timestamp;
the last lasts until song end. Add an empty timed line (for example `[00:20.00]`)
to clear lyrics during instrumental gaps. This is verse-level highlighting;
enhanced word/syllable timestamps are rejected explicitly. Invalid or missing
lyrics are reported while audio/notes remain available.

Run `--headless --path game --script res://tests/test_lyrics.gd` for the parser
and audio-clock selection checks.

### Microphone capture

Choose device and gain in **Configurações**, then click **Ativar microfone** in
the karaoke preparation screen to see your estimated
pitch as a green trace alongside the reference notes. Use headphones. The
input is analyzed locally without recording files or playing the microphone
through the speakers. Click **Desativar microfone** to release capture.
See [microphone setup, calibration and tests](docs/microphone.md). Physical
microphone access was denied in the implementation session; real singing and
device latency still need validation in your Godot editor.

### Singing score

Set microphone and gain in the main menu settings; choose the voice octave on
the preparation screen. Click
**Começar a cantar** for a three-second countdown and a complete scored round.
The microphone can be activated beforehand to check your input. Opening
failures keep you on preparation with an error. Choose **Ouvir e acompanhar
sem pontuar** to run without microphone input.
The top display shows points out of 10,000, pitch accuracy and vocal coverage.
The selected voice octave applies to scoring. Silence during expected notes
earns zero; instrumental sections are excluded. The result screen shows all
three metrics. **Jogar novamente** and **Reiniciar rodada** return to preparation,
clearing the score and preserving voice settings. Octave is locked during a
round; device and gain are adjusted from the main menu. See [scoring rules and tests](docs/scoring.md).
Run flow checks with `godot --headless --path game --script res://tests/test_gameplay.gd`.

**Known limits:** this is a proof of concept, not a validated end-to-end music transcription system. Segmentation now filters voicing probability, smooths pitch, confirms sustained changes and repairs short octave excursions. Its thresholds can omit genuine vocals or fast ornaments; its confidence field remains a placeholder. See [segmentation parameters and local comparison](docs/segmentation.md). The Godot preview has no pause controls; scoring still needs calibration with real singing.

## Next milestones
1. Add reproducible GPU setup and verify Demucs on a short licensed MP3.
2. Add pitch diagnostic plots, voicing filtering, octave correction and robust note segmentation.
3. Improve the Godot timeline and automate local import.
4. Add mic input and scoring after the melody reference is trustworthy.
5. Validate synchronized-lyrics import from [LRCLIB](https://lrclib.net/),
   saving LRC locally and keeping Godot playback offline. See the
   [project roadmap](docs/roadmap.md) for scope and validation steps.

See `AGENTS.md` for Codex constraints and `docs/song-schema-v1.md` for the data contract.

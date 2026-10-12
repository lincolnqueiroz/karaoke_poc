# Karaoke PoC — v0.1 Release Report

## Source and scope

Version: **v0.1**, the first playable Windows MVP.
Source commit: `5632a161d4587ad501bb89d283541fefa54fbb2f`
(`version 0.1`, October 11, 2026).

The user confirmed that this commit is the source of tag v0.1. The tag itself
was not present in the local checkout, and outbound GitHub access failed;
the tag-to-commit association is therefore user-confirmed rather than independently
verified. The gameplay and analyzer sources used for the build match that commit.
The installer configuration, license collector, release report and selectable
packaging output directory were added afterward as release tooling; they are
not part of the tag. Ignored local music/effect assets were supplied from the
workspace for the binary build; the source tag alone does not reproduce those assets.

## What v0.1 contains

- A local-first karaoke application built with Godot 4 and a separate Python
  analysis executable. Players import local MP3 files instead of receiving a
  bundled karaoke song collection.
- Offline vocal separation with Demucs and melody estimation using pYIN.
  Conservative recovery and agreement between two analysis windows improve
  coverage of weaker vocal passages. Original audio is preserved, with diagnostic
  outputs and a schema v1 JSON melody reference.
- A song selector and import workflow with a required title, optional artist,
  explicit CPU/CUDA selection and progress/error reporting. Model downloads
  require an explicit opt-in; the Windows package includes cached model weights.
- Optional synchronized lyrics, either from a local LRC file or a selected
  LRCLIB search result, with preview and duration mismatch warnings. Imported
  songs remain usable offline; LRCLIB is only used during optional preparation.
- A scrolling melody display driven by the audio playback clock, a live green
  voice trace, timestamps, configurable visual timing and advance lyric previews.
- Microphone device selection, input gain and octave adjustment for lower or
  higher voices. Microphone inference runs in GDScript rather than embedding
  Python or machine learning in the game.
- A preparation screen, a three-second countdown, singing and accompaniment
  modes, replay/restart, and a final result. Scores are displayed from **0.0 to
  10.0**, with pitch accuracy and vocal coverage; the large result color blends
  from red through yellow to green.
- A neon/night visual identity, centered menus, luminous borders and titles,
  a local menu background, button click sounds and a complete countdown sound.
  Menu music continues into the waiting room and stops before the countdown.
- Persistent microphone and volume settings. Separate audio channels control
  master output, the karaoke song, effects and menu background music.
- Windows packaging that bundles the analysis runtime, FFmpeg/FFprobe and model
  weights. Players do not need to install Python or FFmpeg separately.

The LRC integration, microphone input, scoring and packaging extend the original
analysis-and-visualization proof-of-concept milestone. Multiplayer, automatic
lyric transcription and a note-editing tool are not implemented.

## Installer behavior

The installer uses Inno Setup, targets Windows 10/11 x64, and installs per user
under `%LOCALAPPDATA%\Programs\KaraokePoC` without requiring administrator rights.
It creates a Start Menu shortcut and offers an optional desktop shortcut.
Uninstalling removes installed program files while preserving the song library
and settings under `%APPDATA%\Godot\app_userdata\Karaoke PoC`.

The installer is split into a Setup executable and adjacent `.bin` payload files,
with slices capped at 1.5 GB. All files must be downloaded into the same folder
before launching Setup. The substantial package size is primarily due to the
bundled CUDA-enabled analysis runtime. The package does not migrate development
workspace songs into a player's library.

Generated release assets in `dist/releases/v0.1/installer/`:

| File | Size in bytes |
| --- | ---: |
| `KaraokePoC-0.1-Setup.exe` | 3,448,199 |
| `KaraokePoC-0.1-Setup-1.bin` | 1,496,551,680 |
| `KaraokePoC-0.1-Setup-2.bin` | 545,870,580 |

The complete installer set totals **2,045,870,459 bytes** (approximately 2.05 GB).
`SHA256SUMS.txt` records the final hashes; `BUILD-METADATA.json` records the build
environment and source commit. The unpacked application is available separately
under `dist/releases/v0.1/Karaoke/`.

## Validation

- Python unit tests: **82 passed** using the existing Python 3.11 virtual environment.
- Godot: all **eight existing test scripts passed**, covering gameplay, import,
  LRCLIB responses, lyrics, menu/settings, synthetic microphone estimates,
  scoring and timeline synchronization.
- CUDA availability was rechecked: PyTorch `2.14.1+cu126`, Python `3.11.9`,
  NVIDIA GeForce RTX 3070; `torch.cuda.is_available()` returned `True`.
- Full Ruff validation reported two pre-existing import-order issues in
  `analyzer/src/karaoke_analyzer/cli.py` and `analyzer/tests/test_exporter.py`.
  They were left unchanged to preserve the release's application source.
- Godot's Windows certificate-store warning appeared in this restricted
  environment. Fast headless menu shutdown also reported a small number of
  retained audio objects. Test scripts completed successfully; these warnings
  do not establish that normal-session shutdown or live HTTPS access is verified.
- The microphone hardware/bus integration is skipped with the Dummy audio
  driver. Synthetic pitch tests do not substitute for testing real input devices.

The fresh PyInstaller bundle and Godot Windows release export completed
successfully. `karaoke-analyzer.exe --help` passed. The exported `Karaoke.exe`
started headlessly and exited after 120 frames with exit code 0; the certificate
and audio-cleanup warnings above remained visible.

With PATH restricted to Windows System32, the packaged analyzer imported a
synthetic 1.5-second MP3 in CPU mode without separation into a test data directory
containing spaces. The job completed successfully without external Python or
FFmpeg, detected MIDI 69 for 1.5 seconds, and preserved the input's SHA-256 hash.
Offline Demucs separation also completed on the RTX 3070/CUDA using the packaged
runtime and cached weights, without model-download permission. As expected for
a synthetic tone with no singer, it exported no vocal notes and displayed the
empty-reference warning. This verifies execution, not melody quality.

The build contains 13,670 files totaling 4,904,617,905 bytes (approximately
4.90 GB / 4.57 GiB). Export logs confirm inclusion of menu music, click/countdown
effects and the menu background, with no local demo song collection.

Inno Setup **6.7.3** compiled the complete installer successfully in approximately
634 seconds. A silent installation was attempted twice in an isolated workspace
folder, with shortcuts disabled. Both attempts stopped before copying application
files: Windows `SHGetFolderPath` returned `0x80070002`, and Inno Setup could not
expand the `localappdata` shell-folder constant in this execution environment.
Creating the isolated LocalAppData directory did not resolve the shell API failure.
The installer exited with code 1. Installation, installed-game startup and
uninstallation therefore remain **unverified**; user-data preservation describes
the configuration's intended behavior, not a completed uninstall test.

The application build and packaged CPU/CUDA smoke tests succeeded independently
of this installer-environment limitation. The installer must be exercised from
a normal Windows user session before release installation can be considered verified.

Locally available Python, FFmpeg and analysis-dependency license/notice texts
were copied into the package, with an inventory covering 31 distributions.
The collector passed Ruff validation. This is an initial notices inventory,
not a complete review of binary, weight or media redistribution terms.

## Known limitations and publication checks

- Melody extraction is an estimate. Backing vocals, harmonies and several
  singers at once can produce missing, incorrect or octave-shifted notes.
  The reference confidence is not a calibrated probability.
- Real LRCLIB HTTPS requests and an end-to-end test on a second Windows machine
  without developer tools remain pending. The latter was explicitly deferred
  by the user earlier in development.
- The silent installer smoke test was blocked by the shell-folder failure above.
  A normal-session install/uninstall test is still required, even on the current PC.
- Import defaults to the NVIDIA/CUDA option. Players without a compatible
  NVIDIA GPU must select CPU; GPU failure does not silently switch the runtime
  to CPU. Large imports and CPU separation can take several minutes.
- No application or installer code signing is configured. A Windows trust or
  SmartScreen prompt may therefore appear.
- The packaged FFmpeg build is GPL. The bundled license text is not, by itself,
  a complete source redistribution arrangement; corresponding-source and notice
  obligations must be resolved for the actual shipped binaries before public
  distribution. The provenance and redistribution terms of local artwork, music,
  effects and model weights must also be recorded.
- Optional YouTube downloader scripts are still tracked in the confirmed source
  commit despite the `.gitignore` entries. The runtime excludes `yt_dlp`, and the
  player import flow uses local MP3 files. Ignoring a file does not remove it from
  an existing commit or tag.

Recommended next step: test installation, offline import, microphone input,
scoring, restart and uninstall on a clean Windows PC, then publish the complete
installer file set and checksums with these release notes after resolving the
remaining publication checks.

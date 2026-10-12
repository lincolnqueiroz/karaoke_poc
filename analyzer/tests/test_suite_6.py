import json
import subprocess
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest

from karaoke_analyzer import pipeline
from karaoke_analyzer.suites.suite_6 import pipeline as suite
from karaoke_analyzer.suites.suite_6 import separator


def mock_demucs(monkeypatch):
    commands = []
    monkeypatch.setattr(separator, "demucs_command", lambda: ["python", "-m", "demucs"])

    def run(command, **kwargs):
        commands.append(command)
        assert kwargs["check"] and kwargs["capture_output"]
        source = Path(command[-1])
        root = Path(command[command.index("-o") + 1])
        stems = root / "htdemucs" / source.stem
        stems.mkdir(parents=True)
        for name in ("vocals.wav", "no_vocals.wav"):
            (stems / name).write_bytes(b"stem")

    monkeypatch.setattr(separator.subprocess, "run", run)
    return commands


def test_explicit_parameters_and_config_without_changing_source(tmp_path, monkeypatch):
    commands = mock_demucs(monkeypatch)
    source = tmp_path / "song & spaces.mp3"
    source.write_bytes(b"original")
    output = tmp_path / "analysis" / "stems"
    vocals = separator.separate_vocals(source, output, "cuda")
    cmd = commands[0]
    for flag, value in [("-n", "htdemucs"), ("--shifts", "4"), ("--overlap", "0.5"),
                        ("--clip-mode", "none"), ("--other-method", "add"), ("-d", "cuda")]:
        assert cmd[cmd.index(flag) + 1] == value
    assert "--float32" in cmd and cmd[-1] == str(source)
    assert vocals.is_file() and vocals.with_name("no_vocals.wav").is_file()
    assert source.read_bytes() == b"original"
    config = json.loads((output.parent / "demucs-config-debug.json").read_text())
    assert config["shifts"] == 4 and config["overlap"] == 0.5
    assert config["clip_mode"] == "none" and config["float32"]


def test_failures_do_not_publish_successful_config(tmp_path, monkeypatch):
    source = tmp_path / "song.mp3"
    source.write_bytes(b"original")
    output = tmp_path / "analysis" / "stems"

    def fail(*args, **kwargs):
        raise subprocess.CalledProcessError(1, "demucs", stderr="GPU failure")

    monkeypatch.setattr(separator.subprocess, "run", fail)
    with pytest.raises(RuntimeError, match="GPU failure"):
        separator.separate_vocals(source, output)
    monkeypatch.setattr(separator.subprocess, "run", lambda *args, **kwargs: None)
    with pytest.raises(RuntimeError, match="expected output"):
        separator.separate_vocals(source, output)
    assert not (output.parent / "demucs-config-debug.json").exists()


def test_adjusted_demucs_output_reaches_hpss_and_both_pitch_windows(tmp_path, monkeypatch):
    commands = mock_demucs(monkeypatch)
    source = tmp_path / "song.mp3"
    source.write_bytes(b"original")
    output = tmp_path / "analysis"
    filtered = output / "hpss-harmonic.wav"
    calls, pitch_inputs = [], []
    monkeypatch.setattr(suite, "decode_to_wav", lambda source, path: path)

    def preprocess(audio, destination):
        calls.append(audio)
        return destination

    def pitch(audio, **kwargs):
        pitch_inputs.append(audio)
        times = np.arange(0, 1, 0.01)
        return times, np.full(100, 220.0), np.ones(100, bool), np.ones(100)

    monkeypatch.setattr(suite, "harmonic_reference", preprocess)
    monkeypatch.setattr(suite, "estimate_pitch", pitch)
    monkeypatch.setattr(suite, "estimate_secondary_pitch", pitch)
    monkeypatch.setattr(suite, "frame_rms_db", lambda audio, t: np.full(len(t), -15.0))
    monkeypatch.setattr(suite.sf, "info", lambda *args: SimpleNamespace(duration=1.0))
    manifest = pipeline.analyze(source, output, True, "cuda", suite="suite_6")
    assert len(commands) == 1
    assert calls == [output / "stems" / "htdemucs" / "song" / "vocals.wav"]
    assert pitch_inputs == [filtered, filtered]
    assert json.loads(manifest.read_text())["notes"]
    assert '"suite_6"' in (output / "analysis-suite.json").read_text()
    assert (output / "demucs-config-debug.json").is_file()


def test_separation_required_before_outputs(tmp_path):
    with pytest.raises(ValueError, match="requires Demucs"):
        pipeline.analyze(tmp_path / "missing.mp3", tmp_path / "output", suite="suite_6")
    assert not (tmp_path / "output").exists()

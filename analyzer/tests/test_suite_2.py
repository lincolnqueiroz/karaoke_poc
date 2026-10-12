from types import SimpleNamespace

import numpy as np
import pytest

from karaoke_analyzer import pipeline
from karaoke_analyzer.suites.suite_2 import pipeline as double


def test_two_passes_track_second_vocal_and_keep_original_mix(tmp_path, monkeypatch):
    source = tmp_path / "song.mp3"
    source.write_bytes(b"original")
    output = tmp_path / "analysis"
    decoded = output / "analysis.wav"
    first = output / "stems" / "htdemucs" / "song" / "vocals.wav"
    second = output / "stems-pass-2" / "htdemucs" / "vocals" / "vocals.wav"
    calls, pitch_inputs, energy_inputs, reports = [], [], [], []

    def separate(audio, directory, device):
        calls.append((audio, directory, device))
        return first if len(calls) == 1 else second

    times = np.arange(0, 1, 0.01)

    def pitch(audio, **kwargs):
        pitch_inputs.append(audio)
        return times, np.full(100, 220.0), np.ones(100, dtype=bool), np.ones(100)

    def energy(audio, timestamps):
        energy_inputs.append(audio)
        return np.full(len(timestamps), -15.0)

    monkeypatch.setattr(double, "decode_to_wav", lambda *args: decoded)
    monkeypatch.setattr(double, "separate_vocals", separate)
    monkeypatch.setattr(double, "estimate_pitch", pitch)
    monkeypatch.setattr(double, "estimate_secondary_pitch", pitch)
    monkeypatch.setattr(double, "frame_rms_db", energy)
    monkeypatch.setattr(double.sf, "info", lambda *args: SimpleNamespace(duration=1.0))
    manifest = pipeline.analyze(source, output, True, "cuda",
                                progress=lambda fraction, text: reports.append(fraction),
                                suite="suite_2")
    assert manifest.is_file()
    assert calls == [(source, output / "stems", "cuda"),
                     (first, output / "stems-pass-2", "cuda")]
    assert pitch_inputs == [second, second]
    assert energy_inputs == [second, decoded]
    assert source.read_bytes() == (output / "original.mp3").read_bytes() == b"original"
    assert reports == sorted(reports) and 0.38 in reports
    assert '"suite_2"' in (output / "analysis-suite.json").read_text()


def test_suite_2_rejects_no_separation_without_creating_outputs(tmp_path):
    output = tmp_path / "analysis"
    with pytest.raises(ValueError, match="requires Demucs"):
        pipeline.analyze(tmp_path / "song.mp3", output, suite="suite_2")
    assert not output.exists()


def test_second_pass_failure_stops_before_pitch(tmp_path, monkeypatch):
    source = tmp_path / "song.mp3"
    source.write_bytes(b"original")
    calls = []

    def separate(audio, directory, device):
        calls.append(audio)
        if len(calls) == 2:
            raise RuntimeError("Second separation failed")
        return tmp_path / "first.wav"

    monkeypatch.setattr(double, "decode_to_wav", lambda *args: tmp_path / "decoded.wav")
    monkeypatch.setattr(double, "separate_vocals", separate)
    monkeypatch.setattr(double, "estimate_pitch", lambda *args, **kwargs: pytest.fail("Pitch ran"))
    output = tmp_path / "analysis"
    with pytest.raises(RuntimeError, match="Second separation failed"):
        pipeline.analyze(source, output, True, suite="suite_2")
    assert len(calls) == 2
    assert not (output / "song.json").exists()
    assert not (output / "analysis-suite.json").exists()

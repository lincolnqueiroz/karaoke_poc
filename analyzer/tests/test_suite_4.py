import json
from types import SimpleNamespace

import numpy as np
import pytest
import soundfile as sf

from karaoke_analyzer import pipeline
from karaoke_analyzer.suites.suite_4 import pipeline as hpss
from karaoke_analyzer.suites.suite_4.preprocessing import harmonic_reference


def test_real_hpss_preserves_tone_timing_channels_and_reduces_clicks(tmp_path):
    rate = 22050
    t = np.arange(rate * 2) / rate
    tone = 0.2 * np.sin(2 * np.pi * 220 * t)
    signal = tone.copy()
    clicks = np.array([rate // 2, rate, 3 * rate // 2])
    signal[clicks] += 0.8
    source, output = tmp_path / "input.wav", tmp_path / "harmonic.wav"
    sf.write(source, np.column_stack([signal, signal * 0.5]), rate, subtype="FLOAT")
    before = source.read_bytes()
    harmonic_reference(source, output)
    filtered, actual_rate = sf.read(output, always_2d=True)
    assert actual_rate == rate and filtered.shape == (len(t), 2)
    assert source.read_bytes() == before
    assert np.allclose(filtered[:, 1], filtered[:, 0] * 0.5, atol=1e-6)
    assert np.max(np.abs(filtered[clicks, 0])) < 0.4
    central = filtered[rate // 4:-rate // 4, 0]
    frequency = np.fft.rfftfreq(len(central), 1 / rate)[np.argmax(abs(np.fft.rfft(central)))]
    assert frequency == pytest.approx(220, abs=1)
    assert np.sqrt(np.mean(central ** 2)) > 0.08


def test_preprocessing_rejects_overwrite_and_missing_inputs(tmp_path):
    source = tmp_path / "input.wav"
    source.write_bytes(b"preserved")
    with pytest.raises(ValueError, match="overwrite"):
        harmonic_reference(source, source)
    assert source.read_bytes() == b"preserved"
    with pytest.raises(ValueError, match="existing"):
        harmonic_reference(tmp_path / "missing.wav", tmp_path / "output.wav")


@pytest.mark.parametrize("separate", [False, True])
def test_pipeline_filters_pitch_only_and_preserves_suite_1_energy(tmp_path, monkeypatch, separate):
    source = tmp_path / "song.mp3"
    source.write_bytes(b"original")
    output = tmp_path / "analysis"
    decoded, vocals = output / "analysis.wav", tmp_path / "vocals.wav"
    filtered = output / "hpss-harmonic.wav"
    calls, pitch_inputs, energy_inputs = [], [], []
    monkeypatch.setattr(hpss, "decode_to_wav", lambda *args: decoded)
    monkeypatch.setattr(hpss, "separate_vocals", lambda *args, **kwargs: vocals)

    def preprocess(audio, destination):
        calls.append((audio, destination))
        return destination

    def pitch(audio, **kwargs):
        pitch_inputs.append(audio)
        times = np.arange(0, 1, 0.01)
        return times, np.full(100, 220.0), np.ones(100, bool), np.ones(100)

    def energy(audio, times):
        energy_inputs.append(audio)
        return np.full(len(times), -15.0)

    monkeypatch.setattr(hpss, "harmonic_reference", preprocess)
    monkeypatch.setattr(hpss, "estimate_pitch", pitch)
    monkeypatch.setattr(hpss, "estimate_secondary_pitch", pitch)
    monkeypatch.setattr(hpss, "frame_rms_db", energy)
    monkeypatch.setattr(hpss.sf, "info", lambda *args: SimpleNamespace(duration=1.0))
    manifest = pipeline.analyze(source, output, separate=separate, suite="suite_4")
    reference = vocals if separate else decoded
    assert calls == [(reference, filtered)]
    assert pitch_inputs == [filtered, filtered]
    assert energy_inputs == ([vocals, decoded] if separate else [decoded])
    assert json.loads(manifest.read_text())["notes"]
    assert '"suite_4"' in (output / "analysis-suite.json").read_text()
    assert (output / "original.mp3").read_bytes() == source.read_bytes() == b"original"

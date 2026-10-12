"""Optional FFmpeg integration using generated audio, never supplied songs."""
import hashlib
import json
import shutil
import subprocess

import numpy as np
import pytest
import soundfile as sf

from karaoke_analyzer.audio import decode_to_wav
from karaoke_analyzer.pipeline import analyze

pytestmark = pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="FFmpeg not available")


def make_mp3(tmp_path, rate, vbr, stereo=False):
    time = np.arange(rate) / rate
    tone = 0.2 * np.sin(2 * np.pi * 440 * time)
    wav = tmp_path / "generated.wav"
    sf.write(wav, np.column_stack((tone, tone)) if stereo else tone, rate)
    mp3 = tmp_path / "canção com espaços.mp3"
    subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-i",
                    str(wav), "-c:a", "libmp3lame", *( ["-q:a", "4"] if vbr
                    else ["-b:a", "128k"]), str(mp3)], check=True, capture_output=True)
    return mp3


@pytest.mark.parametrize("rate,vbr,stereo", [(44100, False, False), (48000, True, True)])
def test_decode_real_mp3_and_preserve_input(tmp_path, rate, vbr, stereo):
    source = make_mp3(tmp_path, rate, vbr, stereo)
    before = hashlib.sha256(source.read_bytes()).digest()
    result = decode_to_wav(source, tmp_path / "decoded.wav")
    audio, output_rate = sf.read(result)
    assert output_rate == 22050 and audio.ndim == 1
    assert abs(len(audio) / output_rate - 1) < 0.02
    assert np.sqrt(np.mean(audio**2)) > 0.1
    assert hashlib.sha256(source.read_bytes()).digest() == before


def test_corrupt_mp3_reports_subprocess_failure(tmp_path):
    path = tmp_path / "broken.mp3"
    path.write_bytes(b"not an audio file")
    with pytest.raises(RuntimeError, match="FFmpeg failed"):
        decode_to_wav(path, tmp_path / "result.wav")


def test_real_mp3_to_notes_without_gpu(tmp_path):
    source = make_mp3(tmp_path, 48000, True)
    manifest = analyze(source, tmp_path / "result")
    data = json.loads(manifest.read_text(encoding="utf-8"))
    assert abs(data["duration_seconds"] - 1) < 0.02
    assert data["notes"] and {note["midi"] for note in data["notes"]} == {69}
    assert sum(note["duration"] for note in data["notes"]) > 0.8

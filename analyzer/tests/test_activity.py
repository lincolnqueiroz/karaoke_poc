import numpy as np
import pytest
import soundfile as sf

from karaoke_analyzer.activity import frame_rms_db


def test_stereo_phase_cancellation_does_not_hide_energy(tmp_path):
    path = tmp_path / "signal.wav"
    sf.write(str(path), np.tile([0.1, -0.1], (1000, 1)), 1000, subtype="FLOAT")
    energy = frame_rms_db(path, [0, 0.5, 1.0])
    np.testing.assert_allclose(energy, -20, atol=1e-5)


def test_silence_and_invalid_timestamps(tmp_path):
    path = tmp_path / "silence.wav"
    sf.write(str(path), np.zeros(1000), 1000)
    assert np.isneginf(frame_rms_db(path, [0.5])[0])
    with pytest.raises(ValueError, match="exceed"):
        frame_rms_db(path, [2])
    with pytest.raises(ValueError, match="timestamps"):
        frame_rms_db(path, [np.nan])

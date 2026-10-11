import sys
from types import SimpleNamespace

import pytest

from karaoke_analyzer import demucs_runner


def test_offline_runner_refuses_model_downloads(monkeypatch):
    hub = SimpleNamespace(download_url_to_file=None)
    monkeypatch.setitem(sys.modules, "torch", SimpleNamespace(hub=hub))
    monkeypatch.setitem(sys.modules, "demucs", SimpleNamespace(__path__=[]))
    monkeypatch.setitem(sys.modules, "demucs.separate", SimpleNamespace(
        main=lambda: hub.download_url_to_file("https://example.invalid/model", "model")))
    monkeypatch.setenv("HF_HUB_OFFLINE", "0")
    with pytest.raises(RuntimeError, match="Autorize"):
        demucs_runner.main()

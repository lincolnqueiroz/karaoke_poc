import json

import pytest

from karaoke_analyzer import pipeline, song_import
from karaoke_analyzer.suites import DEFAULT_SUITE, get_suite, suite_ids
from karaoke_analyzer.suites.suite_1 import pipeline as baseline


def test_default_dispatch_preserves_baseline_and_records_provenance(tmp_path, monkeypatch):
    calls = []

    def fake(source, output, separate, device, progress):
        calls.append((source, separate, device, progress))
        output.mkdir()
        manifest = output / "song.json"
        manifest.write_text('{"schema_version":"1.0"}')
        return manifest

    monkeypatch.setattr(baseline, "analyze", fake)
    source = tmp_path / "source.mp3"
    output = tmp_path / "result"
    manifest = pipeline.analyze(source, output, True, "cuda")
    assert calls == [(source, True, "cuda", None)]
    assert json.loads(manifest.read_text()) == {"schema_version": "1.0"}
    provenance = json.loads((output / "analysis-suite.json").read_text(encoding="utf-8"))
    assert provenance["id"] == DEFAULT_SUITE and provenance["version"] == 1
    assert get_suite().analyze is fake
    assert suite_ids() == (DEFAULT_SUITE, "suite_2", "suite_3", "suite_4", "suite_5", "suite_6", "suite_7", "suite_8")


def test_unknown_suite_rejected_before_analysis(tmp_path, monkeypatch):
    def forbidden(*args, **kwargs):
        pytest.fail("Unknown suite must not execute the baseline")

    monkeypatch.setattr(baseline, "analyze", forbidden)
    output = tmp_path / "output"
    with pytest.raises(ValueError, match="Unknown analysis suite"):
        pipeline.analyze(tmp_path / "missing.mp3", output, suite="unknown")
    assert not output.exists()


def test_import_reports_unknown_suite_without_publishing(tmp_path):
    workspace = tmp_path / "workspace"
    status = workspace / "status.json"
    with pytest.raises(ValueError, match="Unknown analysis suite"):
        song_import.import_song(tmp_path / "missing.mp3", workspace / "songs", status,
                                storage_root=workspace, suite="unknown")
    assert json.loads(status.read_text())["state"] == "error"
    assert not (workspace / "songs").exists()

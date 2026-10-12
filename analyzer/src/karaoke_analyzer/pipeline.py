"""Dispatch offline analysis to a versioned algorithm suite."""
import json
from pathlib import Path

from .suites import DEFAULT_SUITE, get_suite


def analyze(source: Path, output: Path, separate: bool = False, device: str = "cpu",
            progress=None, suite: str = DEFAULT_SUITE) -> Path:
    selected = get_suite(suite)  # Reject unknown suites before touching inputs or loading models.
    manifest = selected.analyze(source, output, separate, device, progress)
    (manifest.parent / "analysis-suite.json").write_text(
        json.dumps({"id": selected.id, "version": selected.version, "label": selected.label},
                   ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest

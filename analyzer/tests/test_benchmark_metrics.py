"""Keep diagnostic interval coverage honest, including overlapping notes."""
import importlib.util
from pathlib import Path

import pytest

SCRIPT = Path(__file__).parents[1] / "scripts" / "summarize_pitch_validation.py"
SPEC = importlib.util.spec_from_file_location("pitch_benchmark_summary", SCRIPT)
SUMMARY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SUMMARY)


def test_coverage_clips_and_does_not_double_count():
    notes = [{"start": 0, "duration": 2}, {"start": 1.5, "duration": 1.5},
             {"start": 4, "duration": 2}, {"start": 20, "duration": 1}]
    assert SUMMARY.region_coverage(notes, 1, 5) == pytest.approx(0.75)
    assert SUMMARY.region_coverage([], 1, 5) == 0

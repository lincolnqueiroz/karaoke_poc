"""Explicit registry of independently preserved analysis suites."""
from collections.abc import Callable
from dataclasses import dataclass

DEFAULT_SUITE = "suite_1"


@dataclass(frozen=True)
class AnalysisSuite:
    id: str
    label: str
    version: int
    analyze: Callable


def get_suite(suite_id: str = DEFAULT_SUITE) -> AnalysisSuite:
    if suite_id == "suite_8":
        from .suite_8.pipeline import analyze
        return AnalysisSuite("suite_8", "Suíte 8 — HPSS + Pós-processamento", 2, analyze)
    if suite_id == "suite_7":
        from .suite_7.pipeline import analyze
        return AnalysisSuite("suite_7", "Suíte 7 — HPSS + Corte absoluto", 2, analyze)
    if suite_id == "suite_6":
        from .suite_6.pipeline import analyze
        return AnalysisSuite("suite_6", "Suíte 6 — Demucs ajustado + HPSS", 1, analyze)
    if suite_id == "suite_5":
        from .suite_5.pipeline import analyze
        return AnalysisSuite("suite_5", "Suíte 5 — HPSS + Harmônicos", 1, analyze)
    if suite_id == "suite_4":
        from .suite_4.pipeline import analyze
        return AnalysisSuite("suite_4", "Suíte 4 — HPSS", 1, analyze)
    if suite_id == "suite_3":
        from .suite_3.pipeline import analyze
        return AnalysisSuite("suite_3", "Suíte 3 — Energia relativa", 3, analyze)
    if suite_id == "suite_2":
        from .suite_2.pipeline import analyze
        return AnalysisSuite("suite_2", "Suíte 2 — Demucs duplo", 1, analyze)
    if suite_id != DEFAULT_SUITE:
        raise ValueError(f"Unknown analysis suite: {suite_id}")
    from .suite_1.pipeline import analyze
    return AnalysisSuite(DEFAULT_SUITE, "Suíte 1 — pYIN conservador", 1, analyze)


def suite_ids() -> tuple[str, ...]:
    return (DEFAULT_SUITE, "suite_2", "suite_3", "suite_4", "suite_5", "suite_6", "suite_7", "suite_8")

"""Offline analysis orchestration."""
import csv
import shutil
from pathlib import Path

import numpy as np
import soundfile as sf

from ...audio import decode_to_wav
from ...exporter import export_song
from ...separator import separate_vocals
from .activity import frame_rms_db
from .pitch import estimate_pitch, estimate_secondary_pitch
from .pitch_consensus import pitch_consensus
from .reference_track import select_reference, vocal_activity
from .segmentation import segment_notes


def analyze(source: Path, output: Path, separate: bool = False, device: str = "cpu",
            progress=None) -> Path:
    report = progress if progress is not None else lambda fraction, message: None
    report(0.02, "Validando o MP3")
    source = source.resolve()
    if not source.is_file() or source.suffix.lower() != ".mp3":
        raise ValueError("Input must be an existing MP3 file")
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    original = output / "original.mp3"
    if original.resolve() != source:
        shutil.copy2(source, original)
    report(0.08, "Decodificando o áudio com FFmpeg")
    original_wav = decode_to_wav(source, output / "analysis.wav")
    reference = source
    if separate:
        report(0.15, "Separando a voz com Demucs")
        vocals = separate_vocals(source, output / "stems", device=device)
        reference = vocals
    analysis_wav = original_wav if reference == source else reference
    report(0.60, "Estimando pitch e segmentando notas")
    primary_diagnostics = {}
    times, f0, voiced, probability = estimate_pitch(analysis_wav, diagnostics=primary_diagnostics)
    energy = frame_rms_db(analysis_wav, times)
    report(0.72, "Conferindo o pitch com uma segunda janela de análise")
    secondary_diagnostics = {}
    secondary_times, secondary_f0, secondary_voiced, secondary_probability = estimate_secondary_pitch(
        analysis_wav, diagnostics=secondary_diagnostics)
    if secondary_times.shape != times.shape or not np.allclose(secondary_times, times):
        raise ValueError("Secondary pitch timestamps do not match the primary analysis")
    support, distance = pitch_consensus(times, f0, voiced, probability, secondary_f0,
                                         secondary_voiced, secondary_probability, energy)
    mixture_energy = None
    if separate:
        # Demucs padding may extend beyond the original decode; clamp energy
        # sampling only, preserving the pitch timestamps and final note clipping.
        original_duration = sf.info(str(original_wav)).duration
        mixture_energy = frame_rms_db(original_wav, np.minimum(times, original_duration))
    active = vocal_activity(energy, mixture_energy, f0=f0, probability=probability)
    reference_f0, reference_voiced, reference_probability, reference_support, selection = (
        select_reference(times, f0, voiced, probability, secondary_f0, secondary_voiced,
                         secondary_probability, active, support,
                         primary_candidate=primary_diagnostics.get("candidate_f0"),
                         secondary_candidate=secondary_diagnostics.get("candidate_f0")))
    recovery = {}
    notes = segment_notes(times, reference_f0, reference_voiced,
                          probability=reference_probability, rms_db=energy,
                          recovery_diagnostics=recovery, support_mask=reference_support,
                          activity_mask=active)
    info = sf.info(str(original_wav))
    # Centered pitch frames can extend slightly past the end of the decoded MP3.
    notes = [dict(note, duration=min(note["duration"], info.duration - note["start"]))
             for note in notes if note["start"] < info.duration]
    with (output / "activity-debug.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_seconds", "rms_dbfs"])
        writer.writerows((float(t), float(e)) for t, e in zip(times, energy))
    with (output / "reference-debug.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_seconds", "f0_hz", "voiced", "voiced_probability",
                         "vocal_activity", "supported", "source"])
        writer.writerows(zip(times, reference_f0, reference_voiced, reference_probability,
                             active, reference_support, selection))
    with (output / "pitch-candidates-debug.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_seconds", "primary_f0_hz", "secondary_f0_hz"])
        writer.writerows(zip(times, primary_diagnostics.get("candidate_f0", f0),
                             secondary_diagnostics.get("candidate_f0", secondary_f0)))
    with (output / "recovery-debug.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_seconds", "recovered_low_probability"])
        writer.writerows((float(t), bool(r)) for t, r in
                         zip(times, recovery.get("recovered", [False] * len(times))))
    with (output / "pitch-secondary-debug.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_seconds", "f0_hz", "voiced", "voiced_probability"])
        writer.writerows(zip(secondary_times, secondary_f0, secondary_voiced, secondary_probability))
    with (output / "pitch-consensus-debug.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_seconds", "supported_by_both_windows", "difference_semitones"])
        writer.writerows(zip(times, support, distance))
    with (output / "pitch-debug.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_seconds", "f0_hz", "voiced", "voiced_probability"])
        for t, f, v, p in zip(times, f0, voiced, probability):
            writer.writerow([float(t), float(f), bool(v), float(p)])
    # Duration from original decoded file, not the potentially shortened vocal stem.
    report(0.90, "Exportando notas e diagnósticos")
    return export_song(output / "song.json", source.stem, info.duration,
                       {"original": "original.mp3"}, notes)

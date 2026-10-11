"""Offline analysis orchestration."""
import csv
import shutil
from pathlib import Path

import numpy as np
import soundfile as sf

from .activity import frame_rms_db
from .audio import decode_to_wav
from .exporter import export_song
from .pitch import estimate_pitch, estimate_secondary_pitch
from .pitch_consensus import pitch_consensus
from .segmentation import segment_notes
from .separator import separate_vocals


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
    times, f0, voiced, probability = estimate_pitch(analysis_wav)
    energy = frame_rms_db(analysis_wav, times)
    report(0.72, "Conferindo o pitch com uma segunda janela de análise")
    secondary_times, secondary_f0, secondary_voiced, secondary_probability = estimate_secondary_pitch(analysis_wav)
    if secondary_times.shape != times.shape or not np.allclose(secondary_times, times):
        raise ValueError("Secondary pitch timestamps do not match the primary analysis")
    support, distance = pitch_consensus(times, f0, voiced, probability, secondary_f0,
                                         secondary_voiced, secondary_probability, energy)
    recovery = {}
    notes = segment_notes(times, f0, voiced, probability=probability, rms_db=energy,
                          recovery_diagnostics=recovery, support_mask=support)
    info = sf.info(str(original_wav))
    # Centered pitch frames can extend slightly past the end of the decoded MP3.
    notes = [dict(note, duration=min(note["duration"], info.duration - note["start"]))
             for note in notes if note["start"] < info.duration]
    with (output / "activity-debug.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_seconds", "rms_dbfs"])
        writer.writerows((float(t), float(e)) for t, e in zip(times, energy))
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

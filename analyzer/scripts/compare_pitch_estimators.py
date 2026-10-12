"""Compare pYIN and optional SwiftF0 offline, without changing production defaults."""
import argparse
import csv
import importlib.metadata
import json
import time
from pathlib import Path

import numpy as np
import soundfile as sf

from karaoke_analyzer.pitch import estimate_pitch
from karaoke_analyzer.segmentation import segment_notes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--wav", type=Path, nargs="*", default=[])
    parser.add_argument("--pyin-cache", type=Path, nargs="*", default=[],
                        help="Production pitch-debug.csv files paired with --wav, in order")
    parser.add_argument("--swift", action="store_true",
                        help="Requires separately approved swift-f0 installation/model")
    parser.add_argument("--harmonics", action="store_true",
                        help="Add second/third harmonics to the synthetic reference tones")
    parser.add_argument("--no-synthetic", action="store_true",
                        help="Only compare supplied WAVs; synthetic benchmarks are separate")
    parser.add_argument("--swift-fmin", type=float, default=65.4,
                        help="SwiftF0 search floor; 46.875 tests its full lower range")
    args = parser.parse_args()
    if args.pyin_cache and len(args.pyin_cache) != len(args.wav):
        parser.error("Provide one pYIN cache for each WAV")
    detector = None
    if args.swift:
        try:
            from swift_f0 import SwiftF0
        except ImportError:
            parser.error("SwiftF0 is not installed; obtain dependency/model approval first")
        detector = SwiftF0(threads=1, spin=False)
    if args.output.exists():
        parser.error("Use a new output directory")
    args.output.mkdir(parents=True)
    cases = []
    frequencies = [] if args.no_synthetic else [65.4, 82.4, 110.0, 220.0, 440.0, 880.0, 1760.0, 0.0]
    for frequency in frequencies:
        rate = 22050
        samples = np.arange(rate) / rate
        path = args.output / f"synthetic-{frequency}.wav"
        audio = 0.2 * np.sin(2 * np.pi * frequency * samples)
        if args.harmonics:
            audio += (0.08 * np.sin(4 * np.pi * frequency * samples)
                      + 0.04 * np.sin(6 * np.pi * frequency * samples))
        sf.write(path, audio, rate)
        cases.append((path, frequency))
    cases.extend((path, None) for path in args.wav)
    rows = []
    for index, (path, target) in enumerate(cases):
        for backend in (["pyin", "swift"] if detector else ["pyin"]):
            began = time.perf_counter()
            cached = backend == "pyin" and target is None and bool(args.pyin_cache)
            if backend == "pyin":
                if cached:
                    cache_path = args.pyin_cache[index - len(frequencies)]
                    with cache_path.open(encoding="utf-8") as handle:
                        frames = list(csv.DictReader(handle))
                    times = np.array([float(frame["time_seconds"]) for frame in frames])
                    f0 = np.array([float(frame["f0_hz"]) for frame in frames])
                    voiced = np.array([frame["voiced"] == "True" for frame in frames])
                    confidence = np.array([float(frame["voiced_probability"]) for frame in frames])
                else:
                    times, f0, voiced, confidence = estimate_pitch(path)
            else:
                audio, rate = sf.read(path, dtype="float32")
                result = detector.detect(audio, rate, fmin=args.swift_fmin, fmax=2093.0)
                times, f0, confidence = result.timestamps, result.pitch_hz, result.confidence
                voiced = confidence >= 0.5
            seconds = time.perf_counter() - began
            # Same single-pass segmentation rules; no fabricated second-window consensus.
            notes = segment_notes(times, f0, voiced, probability=confidence, recovery=False)
            (args.output / f"{index}-{backend}-notes.json").write_text(
                json.dumps(notes, indent=2), encoding="utf-8")
            row = {"source": str(path), "backend": backend,
                   "seconds": None if cached else seconds,
                   "cached_frames": str(cache_path) if cached else None,
                   "duration": sf.info(path).duration, "notes": len(notes),
                   "note_seconds": sum(note["duration"] for note in notes),
                   "quality": None, "target_frequency": target}
            if target is not None:
                interior = (times >= 0.2) & (times <= 0.8)
                valid = voiced & np.isfinite(f0) & (f0 > 0)
                if target > 0:
                    correct = np.zeros(len(times), dtype=bool)
                    correct[valid] = np.abs(1200 * np.log2(f0[valid] / target)) <= 50
                    row["quality"] = {"correct_voiced_fraction": float(np.mean(correct[interior]))}
                else:
                    row["quality"] = {"false_voiced_fraction": float(np.mean(valid[interior]))}
            with (args.output / f"{index}-{backend}-frames.csv").open(
                "w", newline="", encoding="utf-8"
            ) as handle:
                writer = csv.writer(handle)
                writer.writerow(["seconds", "f0_hz", "voiced", "confidence"])
                writer.writerows(zip(times, f0, voiced, confidence))
            rows.append(row)
            print(f"{path.name} {backend}: " + ("cached" if cached else f"{seconds:.3f}s"),
                  flush=True)
    report = {"results": rows, "synthetic_harmonics": args.harmonics,
              "swift_fmin": args.swift_fmin,
              "swift_version": importlib.metadata.version("swift-f0")
              if detector else None,
              "notes": "Single-pass comparison, not production dual-window pipeline. "
                       "First pYIN call includes initialization; confidences are not calibrated "
                       "across models. Real-audio quality is unknown without annotations."}
    (args.output / "comparison.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()

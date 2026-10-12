"""Measure pYIN parameter variants on contextualized user-reported passages."""
import argparse
import csv
import json
import time
from pathlib import Path

import librosa
import numpy as np
from scipy.signal import butter, lfilter, sosfiltfilt

from karaoke_analyzer.segmentation import segment_notes


def coverage(notes, start, end):
    return sum(max(0, min(end, n["start"] + n["duration"]) - max(start, n["start"]))
               for n in notes) / (end - start)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wav", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--experiment", choices=["parameters", "short-windows", "filtering", "combined"],
                        default="parameters")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output directory")
    args.output.mkdir(parents=True)
    audio, rate = librosa.load(args.wav, sr=22050, mono=True)
    profiles = {
        "baseline": {},
        "beta-2-12": {"beta_parameters": (2, 12)},
        "beta-2-8": {"beta_parameters": (2, 8)},
        "beta-2-6": {"beta_parameters": (2, 6)},
        "beta-2-4": {"beta_parameters": (2, 4)},
        "beta-2-8-low-floor": {"beta_parameters": (2, 8), "no_trough_prob": 0.001},
        "beta-2-8-slow": {"beta_parameters": (2, 8), "max_transition_rate": 12},
    }
    windows = [2048, 4096]
    filters = {}
    if args.experiment == "short-windows":
        profiles = {"baseline": {}}
        windows = [768, 1024, 1536]
    elif args.experiment in ["filtering", "combined"]:
        names = (["highpass50", "highpass150", "highpass300", "preemphasis"]
                 if args.experiment == "filtering" else ["highpass300", "preemphasis"])
        profiles = {}
        for name in names:
            for beta in ([18] if args.experiment == "filtering" else [8, 4]):
                key = f"{name}-beta{beta}"
                profiles[key] = ({} if beta == 18 else
                                 {"beta_parameters": (2, beta), "no_trough_prob": 0.001})
                filters[key] = name
    rows = []
    for label, start, end in [("instrumental-intro", 17, 19),
                              ("instrumental-middle", 36, 38), ("chorus", 101, 108)]:
        left, right = max(0, start - 3), min(len(audio) / rate, end + 3)
        excerpt = audio[round(left * rate):round(right * rate)]
        for name, parameters in profiles.items():
            filtered = excerpt
            filter_name = filters.get(name)
            if filter_name == "preemphasis":
                filtered = lfilter([1, -0.97], [1], excerpt)
            elif filter_name:
                filtered = sosfiltfilt(butter(3, int(filter_name[8:]), fs=rate,
                                             btype="highpass", output="sos"), excerpt)
            for window in windows:
                began = time.perf_counter()
                f, v, p = librosa.pyin(filtered, sr=rate, hop_length=256,
                                     frame_length=window, fmin=librosa.note_to_hz("C2"),
                                     fmax=librosa.note_to_hz("C7"), fill_na=None, **parameters)
                elapsed = time.perf_counter() - began
                t = librosa.times_like(f, sr=rate, hop_length=256) + left
                region = (t >= start) & (t < end)
                accepted = region & v & (p >= 0.1)
                notes = segment_notes(t, f, v, probability=p, recovery=False)
                row = {"region": label, "start": start, "end": end, "profile": name,
                       "parameters": parameters, "window": window, "seconds": elapsed,
                       "filter": filter_name,
                       "voiced_fraction": float(np.mean(v[region])),
                       "accepted_fraction": float(np.mean(accepted[region])),
                       "median_probability": float(np.median(p[region])),
                       "note_coverage": coverage(notes, start, end),
                       "median_midi": (float(np.median(69 + 12 * np.log2(f[accepted] / 440)))
                                       if np.any(accepted) else None),
                       "accuracy": None}
                path = args.output / f"{label}-{name}-{window}.csv"
                with path.open("w", newline="", encoding="utf-8") as handle:
                    writer = csv.writer(handle)
                    writer.writerow(["time_seconds", "candidate_f0_hz", "voiced", "probability"])
                    writer.writerows(zip(t, f, v, p))
                rows.append(row)
                (args.output / "results.json").write_text(
                    json.dumps(rows, indent=2), encoding="utf-8")
                print(json.dumps(row), flush=True)


if __name__ == "__main__":
    main()

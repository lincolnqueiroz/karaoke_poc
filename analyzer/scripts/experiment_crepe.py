"""Optional, explicitly approved CREPE benchmark; never changes production defaults."""
import argparse
import csv
import importlib.metadata
import json
import time
from pathlib import Path

import numpy as np
import soundfile as sf

from karaoke_analyzer.segmentation import segment_notes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wav", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--device", choices=["cpu", "cuda:0"], default="cuda:0")
    parser.add_argument("--model", choices=["tiny", "full"], default="full")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output directory")
    if not args.wav.is_file():
        parser.error("WAV input does not exist")
    try:
        import torch
        import torchcrepe
    except ImportError:
        parser.error("Obtain approval before installing torchcrepe and its official model weights")
    if args.device == "cuda:0" and not torch.cuda.is_available():
        parser.error("CUDA unavailable; select CPU explicitly")
    args.output.mkdir(parents=True)
    data, rate = sf.read(args.wav, dtype="float32", always_2d=True)
    if len(data) / rate < 111 or not np.all(np.isfinite(data)):
        parser.error("This reported-passage benchmark needs at least 111s of finite audio")
    results = []
    for label, start, end in [("instrumental-intro", 17, 19),
                              ("instrumental-middle", 36, 38), ("chorus", 101, 108)]:
        left = start - 3
        audio = torch.from_numpy(data[round(left * rate):round((end + 3) * rate)].mean(axis=1)).unsqueeze(0)
        hop = round(rate * 0.01)
        began = time.perf_counter()
        with torch.inference_mode():
            pitch, periodicity = torchcrepe.predict(
                audio, rate, hop, 50, 2000, args.model, batch_size=256,
                device=args.device, return_periodicity=True)
        f, p = (value.cpu().numpy().reshape(-1) for value in (pitch, periodicity))
        t = np.arange(len(f)) * hop / rate + left
        with (args.output / f"{label}-frames.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["time_seconds", "f0_hz", "periodicity"])
            writer.writerows(zip(t, f, p))
        for threshold in [0.21, 0.5, 0.8]:
            notes = segment_notes(t, f, p >= threshold, recovery=False)
            (args.output / f"{label}-{threshold}-notes.json").write_text(
                json.dumps(notes, indent=2), encoding="utf-8")
            coverage = sum(max(0, min(end, n["start"] + n["duration"]) - max(start, n["start"]))
                           for n in notes) / (end - start)
            results.append({"region": label, "threshold": threshold, "coverage": coverage,
                            "accuracy": None, "seconds": time.perf_counter() - began})
        print(label, results[-3:], flush=True)
    report = {"results": results, "model": args.model, "device": args.device,
              "torchcrepe": importlib.metadata.version("torchcrepe"),
              "torch": torch.__version__, "source": str(args.wav.resolve()),
              "caution": "Periodicity is not voice identity; coverage is not pitch accuracy"}
    (args.output / "results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()

"""Compare old and new note assembly on identical cached pYIN estimates."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path

import numpy as np
import soundfile as sf

from karaoke_analyzer.activity import frame_rms_db
from karaoke_analyzer.audio import decode_to_wav
from karaoke_analyzer.pitch import estimate_pitch, estimate_secondary_pitch
from karaoke_analyzer.pitch_consensus import pitch_consensus
from karaoke_analyzer.reference_track import select_reference, vocal_activity
from karaoke_analyzer.segmentation import segment_notes
from karaoke_analyzer.separator import separate_vocals


def read_track(path):
    with path.open(encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    return (np.array([float(row["time_seconds"]) for row in rows]),
            np.array([float(row["f0_hz"]) for row in rows]),
            np.array([row["voiced"] == "True" for row in rows]),
            np.array([float(row["voiced_probability"]) for row in rows]))


def write_track(path, track):
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_seconds", "f0_hz", "voiced", "voiced_probability"])
        writer.writerows(zip(*track))


def compare(folder, destination):
    t, f, v, p = read_track(folder / "pitch-debug.csv")
    st, other, ov, op = read_track(folder / "pitch-secondary-debug.csv")
    if t.shape != st.shape or not np.allclose(t, st):
        raise ValueError("Pitch timestamps differ")
    energy = frame_rms_db(folder / "vocals.wav", t)
    duration = sf.info(folder / "analysis.wav").duration
    mixture = frame_rms_db(folder / "analysis.wav", np.minimum(t, duration))
    support, _ = pitch_consensus(t, f, v, p, other, ov, op, energy)
    old = segment_notes(t, f, v, probability=p, rms_db=energy, support_mask=support)
    active = vocal_activity(energy, mixture, f0=f, probability=p)
    candidates = {}
    if (folder / "pitch-candidates-debug.csv").exists():
        with (folder / "pitch-candidates-debug.csv").open(encoding="utf-8") as h:
            rows = list(csv.DictReader(h))
        candidates = {"primary_candidate": np.array([float(x["primary_f0_hz"]) for x in rows]),
                      "secondary_candidate": np.array([float(x["secondary_f0_hz"]) for x in rows])}
    chosen, flags, confidence, supported, source = select_reference(
        t, f, v, p, other, ov, op, active, support, **candidates)
    new = segment_notes(t, chosen, flags, probability=confidence, rms_db=energy,
                        support_mask=supported, activity_mask=active)
    destination.mkdir(parents=True)
    for label, notes in [("before", old), ("after", new)]:
        (destination / f"{label}-notes.json").write_text(
            json.dumps(notes, indent=2), encoding="utf-8")
    with (destination / "reference-debug.csv").open("w", newline="", encoding="utf-8") as h:
        writer = csv.writer(h)
        writer.writerow(["time_seconds", "f0_hz", "voiced", "probability", "active", "source"])
        writer.writerows(zip(t, chosen, flags, confidence, active, source))
    hop = np.median(np.diff(t)) if len(t) > 1 else 0.01
    result = {"name": destination.name, "duration": duration,
              "before_notes": len(old), "after_notes": len(new),
              "before_seconds": sum(n["duration"] for n in old),
              "after_seconds": sum(n["duration"] for n in new),
              "secondary_seconds": float(np.sum(source == 2) * hop),
              "interpolated_seconds": float(np.sum(source == 3) * hop),
              "candidate_diagnostics": bool(candidates),
              "accuracy": None, "reason": "No reviewed reference; coverage is not accuracy"}
    print(json.dumps(result), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cache-root", type=Path)
    parser.add_argument("--downloads", type=Path)
    parser.add_argument("--replay", type=Path, help="Previous inputs directory; avoid new separation")
    parser.add_argument("--refresh-candidates", action="store_true",
                        help="Compute candidate diagnostics for 30s excerpts during replay")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output directory")
    args.output.mkdir(parents=True)
    os.environ["KARAOKE_OFFLINE_MODELS"] = "1"
    results = []
    if args.replay:
        metadata_path = args.replay.parent / "results.json"
        previous_results = (json.loads(metadata_path.read_text(encoding="utf-8"))
                            if metadata_path.exists() else [])
        metadata = {row["name"]: row for row in previous_results}
        for previous in sorted(args.replay.iterdir()):
            if not previous.is_dir():
                continue
            folder = args.output / "inputs" / previous.name
            folder.mkdir(parents=True)
            for name in ["vocals.wav", "analysis.wav", "pitch-debug.csv",
                         "pitch-secondary-debug.csv", "pitch-candidates-debug.csv"]:
                if (previous / name).exists():
                    os.link(previous / name, folder / name)
            if args.refresh_candidates and sf.info(folder / "vocals.wav").duration <= 30.1:
                print(f"{previous.name}: candidate diagnostics", flush=True)
                primary, secondary = {}, {}
                for function, diagnostic, cache in [
                    (estimate_pitch, primary, "pitch-debug.csv"),
                    (estimate_secondary_pitch, secondary, "pitch-secondary-debug.csv"),
                ]:
                    actual = function(folder / "vocals.wav", diagnostics=diagnostic)
                    expected = read_track(folder / cache)
                    if any(not np.allclose(a, b, equal_nan=True) for a, b in zip(actual, expected)):
                        raise ValueError("Raw pitch changed; do not compare different estimates")
                if (folder / "pitch-candidates-debug.csv").exists():
                    raise ValueError("Candidate diagnostics already exist; preserve the cache")
                with (folder / "pitch-candidates-debug.csv").open(
                    "w", newline="", encoding="utf-8") as h:
                    writer = csv.writer(h)
                    writer.writerow(["time_seconds", "primary_f0_hz", "secondary_f0_hz"])
                    writer.writerows(zip(actual[0], primary["candidate_f0"], secondary["candidate_f0"]))
            result = compare(folder, args.output / previous.name)
            for key in ["group", "excerpt_start", "original_preserved"]:
                if key in metadata.get(previous.name, {}):
                    result[key] = metadata[previous.name][key]
            if previous.name == "i_want_it_that_way":
                result["group"] = "multiple_vocals"
            results.append(result)
            (args.output / "results.json").write_text(
                json.dumps(results, indent=2), encoding="utf-8")
        return
    if args.cache_root is None or args.downloads is None:
        parser.error("Provide --cache-root and --downloads, or --replay")
    for cache in sorted(args.cache_root.glob("*-vocals")):
        name = cache.name.removesuffix("-vocals")
        folder = args.output / "inputs" / name
        folder.mkdir(parents=True)
        # Paths to existing audio, not copies of full stems.
        for file in ["pitch-debug.csv", "pitch-secondary-debug.csv", "analysis.wav"]:
            os.link(cache / file, folder / file)
        os.link(cache / "stems" / "htdemucs" / name / "vocals.wav", folder / "vocals.wav")
        results.append(compare(folder, args.output / name))
    groups = {"solo": ["acid_rain", "heroes_of_sand", "nova_era", "rebirth"],
              "multiple_vocals": ["as_long_as_you_love_me", "quit_playing_games",
                                  "shape_of_my_heart"]}
    for group, names in groups.items():
        for name in names:
            source = args.downloads / f"{name}.mp3"
            with source.open("rb") as handle:
                before = hashlib.file_digest(handle, "sha256").hexdigest()
            folder = args.output / "inputs" / name
            folder.mkdir(parents=True)
            print(f"{name}: decode and separate (offline CUDA)", flush=True)
            mixture = decode_to_wav(source, folder / "full-mixture.wav")
            vocals = separate_vocals(source, folder / "stems", device="cuda")
            # Fixed 30s midpoint excerpt; not a hand-selected favorable region.
            duration = sf.info(mixture).duration
            start = max(0, duration / 2 - 15)
            for audio_path, output in [(mixture, "analysis.wav"), (vocals, "vocals.wav")]:
                with sf.SoundFile(audio_path) as audio:
                    audio.seek(round(start * audio.samplerate))
                    data = audio.read(round(30 * audio.samplerate))
                    sf.write(folder / output, data, audio.samplerate, subtype="FLOAT")
            print(f"{name}: pYIN primary", flush=True)
            write_track(folder / "pitch-debug.csv", estimate_pitch(folder / "vocals.wav"))
            print(f"{name}: pYIN secondary", flush=True)
            write_track(folder / "pitch-secondary-debug.csv",
                        estimate_secondary_pitch(folder / "vocals.wav"))
            result = compare(folder, args.output / name)
            with source.open("rb") as handle:
                result["original_preserved"] = (
                    hashlib.file_digest(handle, "sha256").hexdigest() == before)
            result.update(group=group, excerpt_start=start)
            results.append(result)
            (args.output / "results.json").write_text(
                json.dumps(results, indent=2), encoding="utf-8")
    (args.output / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()

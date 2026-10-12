"""Run the production pipeline into isolated outputs and time its actual stages."""
import argparse
import ctypes
import datetime
import hashlib
import importlib.metadata
import json
import os
import platform
import shutil
import subprocess
import threading
import time
from pathlib import Path
from unittest.mock import patch

from karaoke_analyzer import pipeline
from karaoke_analyzer.runtime import subprocess_options


def checksum(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def peak_parent_memory():
    if platform.system() != "Windows":
        return None

    class Counters(ctypes.Structure):
        _fields_ = [("cb", ctypes.c_ulong), ("PageFaultCount", ctypes.c_ulong),
                    *[(name, ctypes.c_size_t) for name in
                      ["PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage",
                       "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage",
                       "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage"]]]

    counters = Counters()
    counters.cb = ctypes.sizeof(counters)
    kernel = ctypes.windll.kernel32
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    query = ctypes.windll.psapi.GetProcessMemoryInfo
    query.argtypes = [ctypes.c_void_p, ctypes.POINTER(Counters), ctypes.c_ulong]
    if query(kernel.GetCurrentProcess(), ctypes.byref(counters), counters.cb):
        return counters.PeakWorkingSetSize
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--separate", action="store_true")
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    args = parser.parse_args()
    # Benchmarks must not implicitly fetch weights.
    os.environ["KARAOKE_OFFLINE_MODELS"] = "1"
    if args.output.exists():
        parser.error("Benchmark output must be a new directory; existing outputs are preserved")
    args.output.mkdir(parents=True)
    stages = {}
    before = checksum(args.source)
    began = time.perf_counter()
    gpu_samples = []
    sampling_done = threading.Event()

    def sample_gpu():
        while not sampling_done.is_set():
            try:
                query = subprocess.run(
                    ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                    check=False, capture_output=True, text=True, timeout=5, **subprocess_options())
                if query.returncode == 0:
                    gpu_samples.append(int(query.stdout.splitlines()[0].strip()) * 2**20)
            except (OSError, ValueError, subprocess.TimeoutExpired):
                pass
            sampling_done.wait(2)

    sampler = None
    if args.separate and args.device == "cuda" and shutil.which("nvidia-smi"):
        sampler = threading.Thread(target=sample_gpu, daemon=True)
        sampler.start()

    def timed(name, function):
        def run(*values, **options):
            started = time.perf_counter()
            try:
                return function(*values, **options)
            finally:
                stages[name] = time.perf_counter() - started
                print(f"{name}: {stages[name]:.3f}s", flush=True)
        return run

    report = {"source": str(args.source.resolve()), "separate": args.separate,
              "device": args.device, "python": platform.python_version(),
              "platform": platform.platform(),
              "versions": {name: importlib.metadata.version(name)
                           for name in ["numpy", "librosa", "torch", "demucs"]},
              "quality_metrics": None,
              "quality_pending_reason": "No human-reviewed reference annotations",
              "memory_scope": "Parent process lifetime peak; excludes FFmpeg/Demucs children",
              "gpu_peak_memory_bytes": None}
    report["started_utc"] = datetime.datetime.now(datetime.UTC).isoformat()
    report["source_sha256"] = before
    report["analysis_source_hashes"] = {
        path.name: checksum(path) for path in Path(pipeline.__file__).parent.glob("*.py")}
    report["cpu"] = platform.processor()
    report["logical_cpus"] = os.cpu_count()
    report["timing_caution"] = "Observational run; concurrent validation/system load not controlled"
    report["gpu_memory_scope"] = "Total first GPU device memory sampled every 2s; includes other apps"
    try:
        from contextlib import ExitStack
        with ExitStack() as stack:
            for name in ["decode_to_wav", "separate_vocals", "estimate_pitch",
                         "estimate_secondary_pitch", "frame_rms_db", "pitch_consensus",
                         "segment_notes", "export_song"]:
                stack.enter_context(patch.object(pipeline, name, timed(name, getattr(pipeline, name))))
            path = pipeline.analyze(args.source, args.output, args.separate, args.device,
                                    progress=lambda _, text: print(text, flush=True))
        data = json.loads(path.read_text(encoding="utf-8"))
        duration = data["duration_seconds"]
        report.update(duration_seconds=duration, note_count=len(data["notes"]),
                      note_seconds=sum(note["duration"] for note in data["notes"]))
        report["success"] = True
    except Exception as error:
        report.update(success=False, error=f"{type(error).__name__}: {error}")
        raise
    finally:
        total_seconds = time.perf_counter() - began
        sampling_done.set()
        if sampler:
            sampler.join(timeout=6)
        report.update(total_seconds=total_seconds, stages_seconds=stages,
                      peak_parent_memory_bytes=peak_parent_memory(),
                      gpu_peak_memory_bytes=max(gpu_samples) if gpu_samples else None,
                      original_preserved=checksum(args.source) == before)
        report["finished_utc"] = datetime.datetime.now(datetime.UTC).isoformat()
        if report.get("duration_seconds"):
            report["rtf"] = report["total_seconds"] / report["duration_seconds"]
        (args.output / "benchmark.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()

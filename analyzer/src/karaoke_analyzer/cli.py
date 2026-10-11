"""CLI entrypoint."""
import argparse
from pathlib import Path
from .pipeline import analyze


def main(argv=None):
    parser = argparse.ArgumentParser(description="Offline MP3-to-karaoke melody analyzer")
    sub = parser.add_subparsers(dest="command", required=True)
    cmd = sub.add_parser("analyze", help="Generate notes from an MP3")
    cmd.add_argument("source", type=Path)
    cmd.add_argument("--output", type=Path, required=True)
    cmd.add_argument("--separate", action="store_true", help="Use Demucs before pitch tracking")
    cmd.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    args = parser.parse_args(argv)
    if args.command == "analyze":
        result = analyze(args.source, args.output, args.separate, args.device)
        print(f"Generated {result}")

if __name__ == "__main__":
    main()

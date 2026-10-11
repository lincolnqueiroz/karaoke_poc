"""PyInstaller entry point; dispatch before importing heavyweight analysis code."""
import multiprocessing
import sys


def main():
    multiprocessing.freeze_support()
    if len(sys.argv) > 1 and sys.argv[1] == "--demucs":
        del sys.argv[1]
        from karaoke_analyzer.demucs_runner import main as run
    else:
        from karaoke_analyzer.song_import import main as run
    run()


if __name__ == "__main__":
    main()

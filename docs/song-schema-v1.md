# Song manifest v1

The analyzer emits UTF-8 `song.json` alongside the MP3. Times are seconds from the start of the original audio, and MIDI pitch numbers use A4 = 69 = 440 Hz.

```json
{
  "schema_version": "1.0",
  "title": "Demo",
  "duration_seconds": 3.0,
  "audio": { "original": "original.mp3" },
  "notes": [
    { "start": 0.5, "duration": 0.3, "midi": 69, "confidence": 1.0 }
  ]
}
```

`audio.original` is a path relative to the manifest directory. `notes` may be empty. Each note must have a nonnegative `start`, positive `duration`, integer `midi` in 0..127, and `confidence` in 0..1. Note intervals should not extend beyond the song duration. Confidence remains a placeholder (1.0) for accepted segments, **not** a calibrated model probability. The segmenter now filters low-probability frames and stabilizes pitch before semitone quantization; this changes the generated notes without changing schema v1. See [segmentation.md](segmentation.md) for parameters and limitations. Evaluate the reference before gameplay scoring.

Future compatible additions may include `audio.instrumental`, continuous pitch curves, lyrics, voice identity and provenance. Do not break v1 consumers without a migration.

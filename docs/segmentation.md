# Pitch stabilization and note segmentation

The analyzer retains the raw estimated F0, voicing and probability in
`pitch-debug.csv`, and writes centered vocal/input energy to `activity-debug.csv`.
Processing affects only the exported notes; neither the
source MP3 nor the raw frame arrays are modified. Song schema v1 and Godot's
reader remain unchanged. Note confidence is still the documented 1.0 placeholder.

`segment_notes` accepts the previous positional arguments plus optional keyword
parameters. The pipeline supplies pYIN's `probability` array; callers that omit
it retain voiced-only filtering. The pipeline also supplies `rms_db`, measured
over centered 90 ms windows. Channel powers are averaged rather than mixing
channels, so stereo phase cancellation does not hide audio activity.

| Parameter | Default | Meaning |
| --- | --- | --- |
| `min_probability` | 0.1 | Reject nonfinite or lower voicing probabilities |
| `min_rms_db` | -50 dBFS | Reject near-silent frames when `rms_db` is supplied |
| `smoothing_window` | 0.07 s | Centered median of continuous MIDI pitch |
| `hysteresis` | 0.75 semitones | Distance from the current integer pitch needed for a change |
| `change_duration` | 0.08 s | Minimum sustained candidate before accepting a change |
| `octave_glitch_duration` | 0.15 s | Maximum octave excursion repaired when both neighboring notes agree |
| `merge_gap` | 0.06 s | Maximum gap bridged between identical pitches |
| `min_duration` | 0.12 s | Minimum exported note duration, after merging |

Smoothing and change detection run independently within voiced islands, without
crossing silence or missing timestamp gaps. Confirmed changes retain the onset
of their candidate frames rather than adding the confirmation time to playback.
Centered smoothing may move boundaries slightly (approximately half its window).
The octave rule never folds every note into a fixed register: sustained octave
changes and transitions without matching neighbors are preserved.

Merging briefly bridges silence/low-confidence frames only between the same
pitch. Different pitches remain separate. Lowering probability thresholds may
retain more vocals and more pitch noise; higher values may omit genuine vocal
phrases. These parameters are function arguments, not new CLI options.

## Local comparison

Reprocessing the existing raw diagnostics for `como_eu_quero` with the first
stabilized version (probability 0.5, without the energy gate)
changed 541 notes to 295. The pitch range changed from MIDI 36–93 to 55–74,
and total note duration decreased from 175.284 s to 99.345 s. This is evidence
of filtering/stabilization, not evidence that every remaining note is correct.
The removed coverage needs listening and visual review. Backing vocals,
harmonies, sustained octave mistakes, vibrato larger than the hysteresis band,
fast ornamentation and ambiguous pitch estimates remain limitations.

A user-reported group-music test also found incorrect note recognition when
multiple singers sang simultaneously. The analyzer estimates one pitch per
frame, and vocal separation does not guarantee an isolated lead singer.
Overlapping voices can leave the melody reference ambiguous; agreement between
analysis windows does not resolve singer identity. This is a qualitative manual
observation, without measured error rates. Review group-vocal passages before
scoring and include them in future regression material.

The previous manifest was retained locally as `song-before-stabilization.json`;
the raw diagnostic CSV was checked by SHA-256 and remained unchanged.
The updated manifest was copied to the local ignored Godot demo folder.
No Demucs execution or new model download was needed for this comparison.

## Reported passage correction

The user reported continuous voice missing notes at 52–57 s and false notes
without vocals at 109–115 s (times from the audio readout).

The first passage contains strong vocal energy but fluctuating pYIN probability.
The second contains near-silent periodic residuals (centered RMS approximately
-87 to -63 dBFS) that sometimes receive probability near 1.0. Probability alone
cannot reliably reject that silence. Lowering its cutoff to 0.1 while requiring
energy at least -50 dBFS gives this comparison on the same raw pitch:

| Passage | Previous note coverage | Updated note coverage |
| --- | --- | --- |
| 52–57 s | 1.343 s | 3.154 s |
| 109–115 s | 1.368 s | 0 s |

The whole reference now contains 388 notes, updated in the ignored Godot demo.
The prior 295-note manifest is retained as `song-before-energy-gate.json`.
`reported-ranges.png` and `reported-ranges.json` under the song output record the
comparison. The original `pitch-debug.csv` was preserved and verified by SHA-256.

There are still gaps in the voiced passage: uncertain/unvoiced frames and very
short segments are omitted rather than filled with invented notes. The RMS gate
detects near-silence, not voice identity; audible instrument leakage may still
produce notes. A fixed dBFS threshold can omit quiet recordings, so calibrate
`min_rms_db` for different material. Standalone callers without RMS do not get
this silence protection. All durations and threshold parameters remain Python
function arguments, without new dependencies or schema changes.

## Conservative recovery

The default pipeline now recovers low-probability frames only when they already
have a finite F0, are marked voiced, pass the unchanged -50 dBFS energy gate,
and have probability at least 0.01. A continuous candidate region must contain
an anchor passing the original 0.1 probability threshold for at least 30 ms.
Recovery reaches at most 250 ms from an original anchor and stays within
1.5 semitones of it. Recovered frames never become new anchors. Missing F0,
silence, timestamp discontinuities and pitch jumps above 1.5 semitones split
regions. Raw pitch, probability and energy are preserved.

`recovery=False` restores the previous segmentation for comparisons. Recovery
is disabled without probability or energy evidence. The additional
`recovery-debug.csv` records which input frames were recovered; some may still
be removed by stabilization or minimum duration. The v1 confidence placeholder
does not change. Godot now expands its vertical pitch range when the reference
contains notes outside MIDI 48–84, so low notes do not collapse onto one row.

On the existing diagnostics, `amiga_da_minha_mulher` changes from 178 notes /
42.27 s to 421 notes / 106.93 s. In the reported 68–70 s passage, coverage rises
from 0 to 0.673 s. Recovery remains incomplete, including intervals with no F0.
`como_eu_quero` changes from 388 to 418 notes; its 52–57 s coverage rises from
3.154 to 4.663 s, while 109–115 s remains at zero. This comparison checks the
reported passages, not correctness of every added note throughout both songs.

Both workspace manifests and the existing local demo copy were updated without
rerunning Demucs or pitch estimation. Prior manifests are retained as
`song-before-conservative-recovery.json`; SHA-256 checks confirm the raw CSVs
remain unchanged. The detailed comparison is under
`workspace/environment-check/recovery-comparison.json`.

## Support from two analysis windows

New analyses run pYIN with both 2048- and 4096-sample centered windows at the
same 22,050 Hz sample rate and 256-sample hop. The primary window continues
to supply the actual note pitch. The secondary window supplies corroborating
evidence; it does not overwrite missing primary F0 or change raw probabilities.
Their frame times must match. These are two configurations of the same estimator,
so agreement is useful evidence but not independent proof of a correct pitch.

Support requires both estimates to be finite and voiced, both probabilities
at least 0.01, energy at least -50 dBFS, and a difference no larger than half
a semitone. Agreement must last at least 80 ms without timestamp gaps or jumps
above 1.5 semitones. Supported primary frames can pass the additional 0.1
probability gate; they do not become anchors for the original recovery rule.

The usual minimum note duration remains 120 ms. Notes lasting 80–120 ms are
retained only when at least 80% of their frames have cross-window support.
This avoids globally accepting short fragments while retaining more rapid
vocal notes. Neither silence nor unvoiced/NaN primary frames can be accepted
through this support path. Both analyses can still agree on leakage, harmonics
or an incorrect octave; listening remains necessary.

`pitch-secondary-debug.csv` retains the secondary F0, voicing and probability;
`pitch-consensus-debug.csv` stores support decisions and pitch differences.
The manifest remains schema v1 with the unchanged confidence placeholder.
Import now includes a second pitch-analysis stage and takes longer; no new
dependencies or model weights are required.

### Reported passages with cross-window support

The updated complete references use the existing primary diagnostics and a
fresh 4096-sample analysis of the existing vocal stems. `amiga_da_minha_mulher`
changes from 421 notes / 106.93 s to 607 notes / 133.15 s; `como_eu_quero` changes
from 418 to 433 notes. No Demucs run or model download was involved.

| Passage | Previous recovery | Cross-window support |
| --- | ---: | ---: |
| amiga_da_minha_mulher, 26–28 s | 0.575 s | 1.214 s |
| amiga_da_minha_mulher, 68–70 s | 0.673 s | 1.021 s |
| como_eu_quero, 52–57 s | 4.663 s | 4.663 s |
| como_eu_quero, 109–115 s | 0 s | 0 s |

Both workspace references and the existing Godot demo copy were updated.
Prior manifests are retained as `song-before-pitch-consensus.json`. Primary
pitch/energy CSV hashes were verified unchanged. The comparison is stored at
`workspace/environment-check/consensus-comparison.json`.
Remaining gaps can include absent primary F0, disagreement between windows and
segments without sustained support. Larger windows alone were tested and did
not solve the problem; 6144-sample windows even reduced usable coverage in the
reported intervals. More reference coverage does not by itself prove correct
notes; the newly admitted regions need listening and gameplay review.

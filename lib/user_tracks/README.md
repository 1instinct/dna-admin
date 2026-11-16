# track_post.py

Turns a generated track (a "song" with an intro and a silent tail) into a seamless loop of whole
bars, normalises it, and measures what it is: tempo, key, range and timbre. The Rails side runs it
as a subprocess and stores the printed JSON.

## Run it

```sh
python3 lib/user_tracks/track_post.py --in in.flac --out loop.flac \
  --bpm 100 --bars 16 --beats-per-bar 4 --key A --scale minor
```

- Input: anything libsndfile reads (FLAC, WAV; not MP3), mono or stereo.
- Output: `loop.flac`, 16-bit stereo at the input's sample rate (48 kHz for the model's FLAC),
  exactly `round(bars × beats-per-bar × 60 / bpm × sampleRate)` samples long.
- `--key` takes a note name (`A`, `Bb`, `C#`) or a pitch class `0`–`11`; `--scale` is `major` or
  `minor`. They are the request: the key is measured regardless, and `keyMatch` compares.
- It prints one JSON object on stdout. An unusable track is `{"ok": false, "reason": ...}` with
  exit code 0; the exit code is non-zero only on a crash (bad arguments, an unreadable file).
- Importable too: `post(in_path, out_path, bpm, bars, beats_per_bar, key, scale) -> dict`.

Runtime: Python 3.7+, numpy 1.16+ and soundfile (Debian Buster: `python3 python3-numpy
python3-soundfile`). About 2 s and 160 MB for a 120 s input.

## Output

| Field | Meaning |
|---|---|
| `ok`, `reason` | `reason` is `no_loop_window` when no window qualifies (too short, mostly silent, a gap or fade at every possible seam). |
| `bpm` | The requested bpm. |
| `bpmMeasured` | The strongest periodicity, measured over the loop (over the whole input when there is no loop). |
| `bpmMatch` | `"x1"`, `"x2"` or `"x0.5"` when `bpmMeasured` is within 1 % of that multiple of `bpm`, else `null` (the track drifted or has another tempo). |
| `driftMs` | How far the loop's length is from `bars` bars at the measured tempo; the timing error at the seam. |
| `loopStartSec`, `loopSamples`, `sampleRate` | Where the loop was cut from the input, and its exact length. |
| `loopStartBar` | Which bar of the music (0 = the first sounding bar) the loop starts on. |
| `seam` | `after`: the audio after the window was crossfaded into its head; `before`: the audio before it into its tail (the music stops at the window's end); `none`: no neighbour sounds (the input is already the loop, or the music starts and ends on silence). |
| `key`, `keyPc`, `scale` | The measured key: name (`C`, `C#`, `D`, `Eb`, `E`, `F`, `F#`, `G`, `Ab`, `A`, `Bb`, `B`), pitch class 0–11, `major` or `minor`. |
| `keyMatch` | The measured key and scale equal the requested ones. |
| `keyScore` | How well the loop's harmony fits the measured key: the Krumhansl–Kessler correlation (see Key). |
| `keyMargin` | The key's lead over the runner-up after the tonic evidence; a relative key is usually the runner-up. |
| `keyMarginNonRelative` | The lead over the best key that isn't the relative major or minor: whether the *notes* are clear even when the tonic isn't. |
| `keyTop3` | `[{key, scale, score, fit}]`: `fit` is the correlation, `score` adds the tonic evidence. |
| `bassRoot`, `bassPcs` | The note that leads the bass in the loop's first bar (or null), and the bass pitch-class shares over the loop (C..B). |
| `lufs`, `peakDb` | Integrated loudness (target −16 LUFS) and sample peak (≤ −1 dBFS) of `loop.flac`. |
| `lowNote`, `medianNote`, `highNote` | MIDI notes: the 10th, 50th and 90th percentile of the bass and top-voice pitches. Null when too little is pitched. |
| `timbre` | `{brightness, noisiness, percussiveness, sustain, density}`, 0–127 on the scales of the app's on-device analysis (spectral centroid 200 Hz–5 kHz, flatness, attack slope, decay rate, onsets per second 0–8). Null when too little sounds. |

The confidence rule the Rails side applies: a key is confident when `keyScore >= 0.75` and
`keyMargin >= 0.15`.

## Method

**Features.** One mono pass computes: 10 ms levels; onset flux from 21 ms frames (5 ms hop) in 36
log bands, plus the same below 160 Hz; semitone magnitudes from 170 ms frames (C3 up) and 680 ms
frames (the bass register), 43 ms hop, with a median-filter harmonic/percussive split (0.7 s along
time against 13 semitones along pitch).

**Tempo.** The onset envelope's autocorrelation, combed at 1–4 (then 1–8) multiples of each
candidate period from 40 to 250 bpm, with a gentle prior around 120 bpm. When the winner isn't an
octave of the request, a local peak within 1 % of the request (×½, ×1, ×2) that is at least 85 %
as strong is taken instead: a dotted or triplet feel can outscore the beat without the track
having drifted.

**Beat phase.** The onset envelope folded at the requested period over the sounding part; the
peak of the folded histogram is the beat.

**Downbeat.** Each half-beat position in the bar is scored by the low-band attacks and the harmonic
change (chroma before against after) that land on it, plus a bonus for the position the music
starts on after any intro silence. Half beats are candidates because the strongest pulse is
often the off-beat (off-beat bass and hats).

**Window.** Every downbeat whose `bars`-long window fits is a candidate. A candidate is rejected if
any bar is 10 dB under the track's median bar, if its first or last beat has a gap (a 50 ms
stretch 40 dB under the track's loud level, or under −70 dBFS), or if a gap inside it runs longer
than a beat. That excludes the intro silence and the trailing fade while allowing a musical stop.
The rest are ranked on steadiness (spread of bar levels and bar spectra), on the seam (the bar
after the window against its first bar, and the 100 ms around its end against the 100 ms around
its start), and on starting a 4-bar phrase, each term relative to its median over the
candidates. The winner's start is then refined on the window's own beat phase. An input that is
already `bars` long (within 0.1 s) is taken whole.

**Seam.** The window is cut at exact samples. The 30 ms after it are crossfaded (equal power) over
its head, so its last sample runs into its first as the track ran on. If the music stops there,
the 30 ms before the window go over its tail instead.

**Loudness.** ITU-R BS.1770-4: K-weighting (applied in the frequency domain), 400 ms blocks with
75 % overlap, −70 LUFS absolute and −10 LU relative gates. The loop is gained to −16 LUFS, and a
look-ahead limiter (10 ms minimum, 10 ms smoothing, circular so the seam stays continuous)
keeps the sample peak ≤ −1 dBFS; this repeats until within 0.2 LU.

**Key.**
- `fit`: Krumhansl–Kessler correlation of the harmonic chroma from C3 up (each frame scaled to its
  strongest pitch, then averaged), 0.7 × the whole loop + 0.3 × the mean over its three thirds.
- Chroma can't tell a key from its relative (A minor and C major share every note), so the bass
  decides the tonic. Each frame's bass note is the lowest strong peak (within −9 dB) from C2 to G3
  in the harmonic part of the long frames. Below C2 a kick's pitched tail would pass for a bass
  note, and a lower bass still shows by its octave.
- When one note holds at least 40 % of the first bar's bass, the major and minor keys on that note
  get a bonus of 0.5 × its share, but only if their fit is within 0.3 of the best fit. A loop
  starts on its tonic far more often than not, and this is what separates A minor from C major in
  an Am–F–C–G loop whose chords last equally long.
- The keys are ranked by fit + bonus.

## Tests

```sh
python3 -m unittest lib/user_tracks/test_track_post.py
# or, without a system Python:
uv run --with numpy --with soundfile python -m unittest lib/user_tracks/test_track_post.py
```

The tests generate their audio (clicks, hats and sustained triads at a known tempo and key), so
there are no fixture files. Check the syntax floor with
`uvx vermin --target=3.7- --no-tips --violations lib/user_tracks/`.

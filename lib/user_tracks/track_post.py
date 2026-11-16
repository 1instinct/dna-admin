#!/usr/bin/env python3
"""Turn a generated track into a seamless whole-bar loop and measure it.

    python3 track_post.py --in in.flac --out loop.flac --bpm 100 --bars 16 \
        --beats-per-bar 4 --key A --scale minor

prints one JSON object to stdout (see README.md for every field). An unusable track is
`{"ok": false, "reason": ...}` with exit code 0; the exit code is non-zero only on a crash.

Also importable: post(in_path, out_path, bpm, bars, beats_per_bar, key, scale) -> dict.

Runs on Python 3.7 with numpy 1.16 and soundfile (libsndfile 1.0.28: FLAC and WAV in, FLAC out).
Memory stays flat: the analysis holds one float32 mono copy of the input, the cut holds the
float32 stereo loop, and everything that walks the whole signal does it in chunks.
"""
from __future__ import division, print_function

import argparse
import json
import math
import sys

import numpy as np
import soundfile as sf

# ── constants ────────────────────────────────────────────────────────────

NAMES = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']
_PC = {'C': 0, 'B#': 0, 'C#': 1, 'DB': 1, 'D': 2, 'D#': 3, 'EB': 3, 'E': 4, 'FB': 4, 'F': 5,
       'E#': 5, 'F#': 6, 'GB': 6, 'G': 7, 'G#': 8, 'AB': 8, 'A': 9, 'A#': 10, 'BB': 10, 'B': 11,
       'CB': 11}

# Krumhansl–Kessler key profiles (C major, C minor).
KK_MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
KK_MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])

SEAM_SEC = 0.030          # equal-power crossfade of the window's tail into its head
TARGET_LUFS = -16.0
PEAK_DBFS = -1.0
EDGE_TOL_SEC = 0.05       # a window may overhang the file by this much (an exact loop as input)
SILENCE_REL_DB = 40.0     # 50 ms quieter than the track's loud level by this much is a gap
SILENCE_FLOOR_DB = -70.0  # ... and anything below this is a gap whatever the track's level
START_BONUS = 1.0         # downbeat evidence for the grid position the music starts on
PHRASE_PENALTY = 0.25     # window cost of starting off a 4-bar phrase line
BAR_DROP_DB = 10.0        # a bar this much under the track's median bar level is not steady
BPM_TOL = 0.01            # tempo match tolerance at x0.5, x1 or x2

# Key (see README "Key").
CHROMA_LO_MIDI = 48       # chroma from C3 up: the harmony, clear of kick and bass smear
KEY_THIRDS = 0.3          # weight of the mean over the loop's thirds (a key that holds throughout)
KEY_ROOT_BONUS = 0.5      # bonus x share for the keys on the first bar's bass note
KEY_ROOT_MIN_SHARE = 0.4  # ... only when that note leads the first bar this clearly,
KEY_ROOT_RANGE = 0.3      # ... and only for keys whose fit is within this of the best fit
BASS_LO_MIDI = 36         # bass notes are read from C2 ...
BASS_HI_MIDI = 55         # ... to G3
BASS_REL = 0.35           # a bass peak within -9 dB of the strongest pitch in that range

CHUNK = 1 << 18           # samples per chunk for anything that walks the whole signal


# Every key of the printed object, in order (README "Output").
RESULT_KEYS = ('ok', 'reason', 'bpm', 'bpmMeasured', 'bpmMatch', 'loopBpm', 'driftMs', 'loopStartSec',
               'loopSamples', 'sampleRate', 'loopStartBar', 'seam', 'key', 'keyPc', 'scale',
               'keyMatch', 'keyScore', 'keyMargin', 'keyMarginNonRelative', 'keyTop3', 'bassRoot',
               'bassPcs', 'lufs', 'peakDb', 'lowNote', 'medianNote', 'highNote', 'timbre')


# ── small helpers ────────────────────────────────────────────────────────

def _pow2(x):
    return int(2 ** int(round(math.log(max(x, 2.0), 2))))


def _fast_len(n):
    """Smallest 2^a 3^b 5^c >= n (numpy 1.16's fftpack is slow on large prime factors)."""
    best = 1 << int(math.ceil(math.log(max(n, 1), 2)))
    p5 = 1
    while p5 < best:
        p35 = p5
        while p35 < best:
            p = p35
            while p < n:
                p *= 2
            if p < best:
                best = p
            p35 *= 3
        p5 *= 5
    return best


def _db(x, floor=1e-12):
    return 10.0 * np.log10(np.maximum(x, floor))


def _corr(a, b):
    a = a - a.mean()
    b = b - b.mean()
    d = math.sqrt(float(np.dot(a, a)) * float(np.dot(b, b)))
    return float(np.dot(a, b)) / d if d > 0 else 0.0


def _to127(x):
    return int(min(1.0, max(0.0, x)) * 127 + 0.5)


def _stft_reduce(x, n_fft, hop, reducer, n_frames):
    """Hann-windowed power spectra of mono x, frames centred on t * hop (zeros beyond its ends),
    handed to `reducer(power[chunk, n_fft // 2 + 1]) -> array[chunk, k]` in chunks; returns the
    stacked results. Memory stays flat for long inputs: each chunk copies only its own samples."""
    pad = n_fft // 2
    n = len(x)
    win = np.hanning(n_fft + 1)[:-1].astype(np.float32)
    chunk = max(4, (1 << 19) // n_fft)
    out = []
    for i in range(0, n_frames, chunk):
        m = min(chunk, n_frames - i)
        a = i * hop - pad
        b = a + (m - 1) * hop + n_fft
        seg = np.zeros(b - a, np.float32)
        lo, hi = max(a, 0), min(b, n)
        if hi > lo:
            seg[lo - a:hi - a] = x[lo:hi]
        frames = np.lib.stride_tricks.as_strided(
            seg, shape=(m, n_fft), strides=(seg.strides[0] * hop, seg.strides[0]))
        spec = np.fft.rfft(frames * win, axis=1)
        out.append(reducer((spec.real ** 2 + spec.imag ** 2).astype(np.float32)))
        del spec, frames, seg
    return np.concatenate(out, axis=0)


def _block_ms(x, blk, nb):
    """Mean square of x (1-D, or 2-D averaged over channels first) in nb blocks of blk samples."""
    out = np.empty(nb)
    step = max(1, CHUNK // blk)
    for i in range(0, nb, step):
        j = min(nb, i + step)
        seg = x[i * blk:j * blk]
        if seg.ndim == 2:
            seg = seg.mean(axis=1)
        seg = seg.astype(np.float64).reshape(j - i, blk)
        out[i:j] = (seg * seg).mean(axis=1)
    return out


def _mean_square(x):
    """Mean of x ** 2 over every element, in chunks."""
    tot = 0.0
    for a in range(0, len(x), CHUNK):
        seg = x[a:a + CHUNK].astype(np.float64)
        tot += float(np.sum(seg * seg))
    return tot / max(1, x.size)


def _semitone_reducer(sr, n_fft, midi_lo, midi_hi):
    """Power spectrum -> magnitude per semitone (MIDI midi_lo..midi_hi): the strongest bin within a
    quarter tone of each pitch, or the interpolated value at its centre where the bins are coarser
    than a semitone."""
    bin_hz = sr / float(n_fft)
    groups = []
    for m in range(midi_lo, midi_hi + 1):
        f = 440.0 * 2 ** ((m - 69) / 12.0)
        lo = int(math.ceil(f * 2 ** (-1 / 24.0) / bin_hz))
        hi = int(math.floor(f * 2 ** (1 / 24.0) / bin_hz))
        c = f / bin_hz
        k0 = int(math.floor(c))
        groups.append((lo, hi, k0, c - k0))

    def reduce(power):
        mag = np.sqrt(power)
        out = np.empty((power.shape[0], len(groups)), np.float32)
        for j, (lo, hi, k0, fr) in enumerate(groups):
            v = mag[:, k0] * (1 - fr) + mag[:, k0 + 1] * fr
            if hi >= lo:
                v = np.maximum(v, mag[:, lo:hi + 1].max(axis=1))
            out[:, j] = v
        return out
    return reduce


def _median_filter(a, k, axis):
    """Median over a centred window of k (odd) along axis (edges repeat), for 2-D a."""
    if axis == 1:
        return _median_filter(a.T, k, 0).T
    h = k // 2
    ap = np.concatenate([np.repeat(a[:1], h, axis=0), a, np.repeat(a[-1:], h, axis=0)], axis=0)
    ap = np.ascontiguousarray(ap)
    n = a.shape[0]
    out = np.empty_like(a)
    step = max(1, (1 << 22) // max(1, a.shape[1] * k))
    for i in range(0, n, step):
        j = min(n, i + step)
        view = np.lib.stride_tricks.as_strided(
            ap[i:], shape=(j - i, k, a.shape[1]),
            strides=(ap.strides[0], ap.strides[0], ap.strides[1]))
        out[i:j] = np.median(view, axis=1)
    return out


def _harmonic(S, k_time, k_pitch):
    """Soft-mask harmonic part of a (frames, pitches) magnitude array (median-filter HPSS)."""
    H = _median_filter(S, k_time, 0)
    P = _median_filter(S, k_pitch, 1)
    mask = H * H / (H * H + P * P + 1e-12)
    return S * mask


# ── loudness (ITU-R BS.1770-4) ───────────────────────────────────────────

def _k_weight_power(freqs, sr):
    """|H(f)|^2 of the BS.1770 K-weighting (high shelf + high pass) at any sample rate."""
    def biquad(b, a):
        w = 2 * np.pi * freqs / sr
        z1 = np.exp(-1j * w)
        z2 = z1 * z1
        h = (b[0] + b[1] * z1 + b[2] * z2) / (a[0] + a[1] * z1 + a[2] * z2)
        return np.abs(h) ** 2

    g, q, fc = 4.0, 1 / math.sqrt(2), 1500.0
    A = 10 ** (g / 40.0)
    w0 = 2 * math.pi * fc / sr
    al = math.sin(w0) / (2 * q)
    c = math.cos(w0)
    sa = 2 * math.sqrt(A) * al
    shelf = biquad((A * ((A + 1) + (A - 1) * c + sa), -2 * A * ((A - 1) + (A + 1) * c),
                    A * ((A + 1) + (A - 1) * c - sa)),
                   ((A + 1) - (A - 1) * c + sa, 2 * ((A - 1) - (A + 1) * c),
                    (A + 1) - (A - 1) * c - sa))
    q, fc = 0.5, 38.0
    w0 = 2 * math.pi * fc / sr
    al = math.sin(w0) / (2 * q)
    c = math.cos(w0)
    hp = biquad(((1 + c) / 2, -(1 + c), (1 + c) / 2), (1 + al, -2 * c, 1 - al))
    return shelf * hp


def _k_energy(x, sr, gain=None):
    """K-weighted energy per 100 ms step (summed over channels) of the circular signal x
    (samples, channels), or of x * gain(indices) when a per-sample gain is given. Filtered in the
    frequency domain chunk by chunk, each with the 170 ms before it (circularly: the loop is
    circular) to settle the filter, so memory stays flat."""
    n = x.shape[0]
    step = int(round(0.1 * sr))
    margin = _pow2(0.17 * sr)
    core = max(1 << 17, 4 * margin) - margin
    e = np.zeros((n + step - 1) // step)
    cache = {}
    for a in range(0, n, core):
        b = min(n, a + core)
        idx = np.arange(a - margin, b) % n
        seg = x[idx].astype(np.float64)
        if gain is not None:
            seg *= gain(idx)[:, None]
        nf = _fast_len(len(idx))
        if nf not in cache:
            cache[nf] = np.sqrt(_k_weight_power(np.fft.rfftfreq(nf, 1.0 / sr), sr))[:, None]
        y = np.fft.irfft(np.fft.rfft(seg, nf, axis=0) * cache[nf], nf, axis=0)
        y = y[margin:margin + b - a]
        sq = (y * y).sum(axis=1)
        k = np.arange(a, b) // step
        e[k[0]:k[-1] + 1] += np.bincount(k - k[0], weights=sq)
    return e


def _gated_lufs(e, n, sr):
    """BS.1770 gating of 100 ms step energies: 400 ms blocks (4 steps, 75 % overlap) inside the
    n samples, absolute gate -70 LUFS, relative gate -10 LU."""
    step = int(round(0.1 * sr))
    full = n // step
    if full < 4:
        return float('-inf')
    e = e[:full]
    z = (e[:-3] + e[1:-2] + e[2:-1] + e[3:]) / (4.0 * step)
    z = z[-0.691 + _db(z, 1e-20) > -70.0]
    if len(z) == 0:
        return float('-inf')
    rel = -0.691 + _db(z.mean(), 1e-20) - 10.0
    z = z[(-0.691 + _db(z, 1e-20)) > rel]
    if len(z) == 0:
        return float('-inf')
    return float(-0.691 + _db(z.mean(), 1e-20))


def integrated_lufs(x, sr):
    """Integrated loudness (LUFS) of a (samples, channels) array: K-weighted, 400 ms blocks with
    75 % overlap, absolute gate -70 LUFS, relative gate -10 LU."""
    x = np.asarray(x)
    if x.ndim == 1:
        x = x[:, None]
    if x.shape[0] == 0:
        return float('-inf')
    return _gated_lufs(_k_energy(x, sr), x.shape[0], sr)


def _sliding_min_circular(r, w):
    """min(r[i - w // 2 ... i - w // 2 + w - 1]) for every i, circularly."""
    m = r.copy()
    span = 1
    while span * 2 <= w:
        m = np.minimum(m, np.roll(m, -span))
        span *= 2
    if span < w:
        m = np.minimum(m, np.roll(m, -(w - span)))
    return np.roll(m, w // 2)


def _block_peaks(x, blk):
    """Peak |x| over channels in each blk-sample block (the last one may be short)."""
    n = x.shape[0]
    nb = (n + blk - 1) // blk
    pk = np.zeros(nb, np.float32)
    step = max(1, CHUNK // blk)
    for i in range(0, nb, step):
        j = min(nb, i + step)
        seg = np.abs(x[i * blk:min(n, j * blk)]).max(axis=1)
        if len(seg) < (j - i) * blk:
            seg = np.concatenate([seg, np.zeros((j - i) * blk - len(seg), seg.dtype)])
        pk[i:j] = seg.reshape(j - i, blk).max(axis=1)
    return pk


def _limiter(pk, blk, n, level, ceiling, sr):
    """The gain, as a function of sample indices, that scales a circular signal by `level` and
    keeps it under the ceiling: the gain each 1 ms block (peaks `pk`) needs, min-filtered over
    12 ms and box-smoothed over 10 ms, then interpolated between block centres. The min reaches
    one block past the smoothing on each side, so no sample gets more gain than it needs."""
    need = np.minimum(1.0, ceiling / np.maximum(level * pk.astype(np.float64), 1e-12))
    nb = len(need)
    h = max(1, int(round(0.005 * sr / blk)))
    if need.min() >= 1.0 or nb < 2 * h + 4:
        flat = level * float(need.min())
        return lambda idx: np.full(len(idx), flat)
    m = _sliding_min_circular(need, 2 * (h + 1) + 1)
    mp = np.concatenate([m[-h:], m, m[:h]])
    cs = np.concatenate([[0.0], np.cumsum(mp)])
    g = np.minimum((cs[2 * h + 1:] - cs[:-2 * h - 1]) / (2 * h + 1), 1.0)
    centres = np.arange(nb) * blk + (blk - 1) / 2.0
    centres[-1] = ((nb - 1) * blk + n - 1) / 2.0
    xp = np.concatenate([[centres[-1] - n], centres, [centres[0] + n]])
    fp = level * np.concatenate([[g[-1]], g, [g[0]]])
    return lambda idx: np.interp(idx, xp, fp)


def _normalise(loop, sr):
    """Gain the loop (float32, in place) to TARGET_LUFS under a circular look-ahead limiter at
    PEAK_DBFS. Returns its loudness."""
    ceiling = 10 ** (PEAK_DBFS / 20.0) * 0.985  # margin for 16-bit rounding
    n = loop.shape[0]
    lufs = integrated_lufs(loop, sr)
    if not np.isfinite(lufs):
        return lufs
    blk = max(1, int(round(0.001 * sr)))
    pk = _block_peaks(loop, blk)
    level = 10 ** ((TARGET_LUFS - lufs) / 20.0)
    for i in range(3):
        gain = _limiter(pk, blk, n, level, ceiling, sr)
        lufs = _gated_lufs(_k_energy(loop, sr, gain), n, sr)
        if abs(lufs - TARGET_LUFS) <= 0.2 or i == 2:
            break
        level *= 10 ** ((TARGET_LUFS - lufs) / 20.0)
    for a in range(0, n, CHUNK):
        b = min(n, a + CHUNK)
        loop[a:b] *= gain(np.arange(a, b)).astype(np.float32)[:, None]
    return lufs


def _write_pcm16(path, y, sr):
    """y (float, samples x channels) as 16-bit FLAC, in chunks. Returns the sample peak (0-1)."""
    peak = 0
    with sf.SoundFile(path, 'w', sr, y.shape[1], 'PCM_16', format='FLAC') as fh:
        for a in range(0, y.shape[0], CHUNK):
            pcm = np.clip(np.round(y[a:a + CHUNK] * 32767.0), -32768, 32767).astype(np.int16)
            if len(pcm):
                peak = max(peak, int(np.abs(pcm.astype(np.int32)).max()))
            fh.write(pcm)
    return peak / 32768.0


# ── analysis ─────────────────────────────────────────────────────────────

class _Features(object):
    """Frame-level features of the whole input."""

    def __init__(self, mono, sr):
        self.sr = sr
        self.n = len(mono)
        # level: 10 ms blocks
        self.blk = int(round(0.01 * sr))
        nb = self.n // self.blk
        self.blk_ms = _block_ms(mono, self.blk, nb)

        # onsets: ~21 ms frames, ~5 ms hop, 36 log bands from 30 Hz
        n_fft = _pow2(0.0213 * sr)
        self.o_hop = n_fft // 4
        self.o_fps = sr / float(self.o_hop)
        self.o_bias = (n_fft / 2.0 - self.o_hop) / sr  # a flux peak trails its attack by about this
        nyq = sr / 2.0
        edges_hz = np.geomspace(30.0, min(16000.0, nyq * 0.95), 37)
        edges = np.unique(np.clip(np.round(edges_hz * n_fft / sr).astype(int), 1, n_fft // 2))
        self.n_bands = len(edges) - 1
        self.low_bands = int(np.sum(edges[1:] * sr / float(n_fft) <= 160.0))
        frames = 1 + self.n // self.o_hop

        def bands(power):
            return np.add.reduceat(power, edges, axis=1)[:, :-1]
        be = _stft_reduce(mono, n_fft, self.o_hop, bands, frames)
        ref = max(float(be.max()), 1e-12)
        self.band_db = _db(be / ref, 1e-8)  # 0 dB at the loudest band, floor -80
        d = np.diff(self.band_db, axis=0)
        d = np.vstack([np.zeros((1, d.shape[1]), np.float32), np.maximum(d, 0)])
        self.flux = d.mean(axis=1)
        self.flux_low = d[:, :max(1, self.low_bands)].mean(axis=1)
        self.onset = self._detrend(self.flux)
        self.onset_low = self._detrend(self.flux_low)

        # tonal: ~170 ms frames for MIDI 48..100, ~680 ms frames for MIDI 24..79, same ~43 ms hop
        nt = _pow2(0.17 * sr)
        self.t_hop = nt // 4
        self.t_fps = sr / float(self.t_hop)
        tf = 1 + self.n // self.t_hop
        hi = _stft_reduce(mono, nt, self.t_hop, self._tonal_reducer(sr, nt), tf)
        self.centroid = hi[:, -3]
        self.flatness = hi[:, -2]
        self.t_ms = hi[:, -1]
        lo = _stft_reduce(mono, nt * 4, self.t_hop, _semitone_reducer(sr, nt * 4, 24, 79), tf)
        # MIDI 24..47 from the long frames, 48..100 (the chroma) from the short ones
        self.semi = np.hstack([lo[:, :24], hi[:, :53]])  # MIDI 24..100
        k_time = int(round(0.7 * self.t_fps)) | 1
        self.semi_h = _harmonic(self.semi, k_time, 13)
        self.bass_h = _harmonic(lo, k_time, 13)  # MIDI 24..79, for the bass salience

    def _detrend(self, f):
        h = max(1, int(round(0.1 * self.o_fps)))
        cs = np.concatenate([[0.0], np.cumsum(f.astype(np.float64))])
        idx = np.arange(len(f))
        a = np.maximum(0, idx - h)
        b = np.minimum(len(f), idx + h + 1)
        return np.maximum(0.0, f - (cs[b] - cs[a]) / (b - a))

    @staticmethod
    def _tonal_reducer(sr, n_fft):
        semi = _semitone_reducer(sr, n_fft, 48, 100)
        bin_hz = sr / float(n_fft)
        k8 = min(n_fft // 2, int(8000 / bin_hz))
        f_lo, f_hi = max(1, int(31 / bin_hz)), min(n_fft // 2, int(7000 / bin_hz))
        kk = np.arange(n_fft // 2 + 1, dtype=np.float64) * bin_hz
        win_power = (np.hanning(n_fft + 1)[:-1] ** 2).sum()

        def reduce(power):
            p = power.astype(np.float64)
            s = p[:, 1:k8 + 1].sum(axis=1)
            cen = (p[:, 1:k8 + 1] * kk[1:k8 + 1]).sum(axis=1) / np.maximum(s, 1e-20)
            band = p[:, f_lo:f_hi + 1]
            mean = band.mean(axis=1)
            lflat = np.log10(band / np.maximum(mean, 1e-20)[:, None] + 1e-7).mean(axis=1)
            ms = 2 * p.sum(axis=1) / (n_fft * win_power)
            return np.hstack([semi(power), cen[:, None], lflat[:, None], ms[:, None]]).astype(np.float32)
        return reduce

    # time <-> frames
    def o_time(self, frame):
        return frame / self.o_fps - self.o_bias

    def o_frame(self, t):
        return (t + self.o_bias) * self.o_fps


def _comb(ac, lags, K):
    """Mean autocorrelation at 1..K multiples of each (fractional) lag."""
    s = np.zeros(len(lags))
    x = np.arange(len(ac))
    for k in range(1, K + 1):
        s += np.interp(lags * k, x, ac, right=0.0)
    return s / K


def _tempo(onset, fps, bpm_req):
    """(measured bpm, match label or None, strength 0..1)."""
    o = onset - onset.mean()
    n = len(o)
    nf = _fast_len(2 * n)
    spec = np.fft.rfft(o, nf)
    ac = np.fft.irfft(spec.real ** 2 + spec.imag ** 2, nf)[:n]
    if ac[0] <= 0:
        return None, None, 0.0
    ac = ac / ac[0]
    ac = ac * n / np.maximum(1, n - np.arange(n))  # unbiased
    max_lag = n * 0.5

    def strength(bpms, K):
        lags = fps * 60.0 / bpms
        K = int(max(1, min(K, max_lag // max(lags.max(), 1))))
        return _comb(ac, lags, K)

    grid = np.arange(40.0, 250.0, 0.05)
    s = strength(grid, 4)
    prior = np.exp(-0.5 * (np.log2(grid / 120.0) / 1.0) ** 2)
    i = int(np.argmax(s * prior))

    def refine(center, span):
        """(bpm, strength, at_edge) of the strongest periodicity within +-span of center."""
        g = np.arange(center * (1 - span), center * (1 + span), center * 0.0005)
        v = strength(g, 8)
        j = int(np.argmax(v))
        if 0 < j < len(g) - 1:
            a, b, c = v[j - 1], v[j], v[j + 1]
            den = a - 2 * b + c
            off = 0.5 * (a - c) / den if den < 0 else 0.0
            return g[j] + off * (g[1] - g[0]), float(b), False
        return g[j], float(v[j]), True  # the peak is at the search edge: not a local peak

    best, best_s, _ = refine(grid[i], 0.03)

    def label(b):
        for name, mult in (('x1', 1.0), ('x2', 2.0), ('x0.5', 0.5)):
            if abs(b / (bpm_req * mult) - 1) <= BPM_TOL:
                return name
        return None

    match = label(best)
    if match is None:
        # The strongest periodicity can sit at a non-octave ratio (a dotted or triplet feel) while
        # the requested tempo is just as present: accept it only as a true local peak, within
        # tolerance and nearly as strong.
        for mult in (1.0, 2.0, 0.5):
            c = bpm_req * mult
            if not 40 <= c <= 250:
                continue
            b, sb, edge = refine(c, 0.02)
            if not edge and label(b) and sb >= 0.85 * best_s:
                best, best_s, match = b, sb, label(b)
                break
    return float(best), match, float(max(0.0, best_s))


def _fold_phase(onset, period, lo, hi):
    """Beat phase (fractional frame in [0, period)) of onset[lo:hi] at a fixed period."""
    t = np.arange(lo, hi)
    nb = max(8, int(round(period)))
    idx = (np.floor(((t % period) / period) * nb).astype(int)) % nb
    hist = np.bincount(idx, weights=onset[lo:hi], minlength=nb)
    sm = hist + 0.5 * (np.roll(hist, 1) + np.roll(hist, -1))
    j = int(np.argmax(sm))
    a, b, c = sm[(j - 1) % nb], sm[j], sm[(j + 1) % nb]
    den = a - 2 * b + c
    off = 0.5 * (a - c) / den if den < 0 else 0.0
    return ((j + 0.5 + off) / nb * period) % period


def _peak_near(arr, pos, half):
    a = max(0, int(round(pos - half)))
    b = min(len(arr), int(round(pos + half)) + 1)
    return float(arr[a:b].max()) if b > a else 0.0


def _chroma_frames(semi_h, midi_lo=CHROMA_LO_MIDI, base=24):
    """(frames, 12) chroma: each frame's harmonic semitone magnitudes from midi_lo up, scaled to
    the frame's strongest pitch, folded into pitch classes."""
    S = semi_h[:, midi_lo - base:]
    S = S / np.maximum(S.max(axis=1), 1e-12)[:, None]
    C = np.zeros((S.shape[0], 12))
    for j in range(S.shape[1]):
        C[:, (midi_lo + j) % 12] += S[:, j]
    return C


def _norm_mean(C, weights=None):
    mx = C.max(axis=1)
    keep = mx > 0
    if weights is not None:
        keep &= weights
    if not np.any(keep):
        return np.zeros(12)
    return (C[keep] / mx[keep, None]).mean(axis=0)


def _key_scores(vec):
    """Correlation with the 24 K-K profiles, index pc (major) and 12 + pc (minor)."""
    out = np.zeros(24)
    if not np.any(vec > 0):
        return out
    for r in range(12):
        out[r] = _corr(vec, np.roll(KK_MAJOR, r))
        out[12 + r] = _corr(vec, np.roll(KK_MINOR, r))
    return out


def _bass(bass_h, active, base=24):
    """Bass note per frame (MIDI, -1 when none): the lowest local peak from C2 to G3 within
    -9 dB of the strongest pitch there, in the harmonic part of the long frames. Below C2 the
    kick's pitched tail would pass for a bass note; a lower bass still shows by its octave."""
    S = bass_h[:, BASS_LO_MIDI - base:BASS_HI_MIDI - base + 1]
    m = S.max(axis=1)
    peak = (S >= BASS_REL * m[:, None]) & (S >= np.roll(S, 1, axis=1)) & (S >= np.roll(S, -1, axis=1))
    peak[:, 0] &= S[:, 0] >= S[:, 1]
    peak[:, -1] &= S[:, -1] >= S[:, -2]
    has = peak.any(axis=1) & active & (m > 0)
    return np.where(has, BASS_LO_MIDI + np.argmax(peak, axis=1), -1)


def _active(f, a, b):
    ms = f.t_ms[a:b]
    return ms > max(1e-10, float(np.percentile(ms, 90)) * 1e-4) if b > a else np.zeros(0, bool)


def _measure_key(f, a, b, bars):
    """Key over tonal frames [a, b) (the loop).

    fit: K-K correlation of the harmonic chroma (C3 up), 0.7 x the whole loop + 0.3 x the mean
    over its thirds. The chroma alone can't tell a key from its relative (A minor and C major share
    every note), so the bass in the loop's first bar, when one note clearly leads it, adds a bonus to
    the keys on that tonic. Ranked by fit + bonus; keyScore is the winner's fit and keyMargin its
    lead after the bonus."""
    active = _active(f, a, b)
    C = _chroma_frames(f.semi_h[a:b])
    n = b - a
    whole = _key_scores(C[active].mean(axis=0)) if active.any() else np.zeros(24)
    thirds = []
    for i in range(3):
        lo, hi = i * n // 3, (i + 1) * n // 3
        sel = active[lo:hi]
        thirds.append(_key_scores(C[lo:hi][sel].mean(axis=0)) if sel.any() else whole)
    fit = (1 - KEY_THIRDS) * whole + KEY_THIRDS * np.mean(thirds, axis=0)

    notes = _bass(f.bass_h[a:b], active)
    pcs = notes[notes >= 0] % 12
    hist = np.bincount(pcs, minlength=12).astype(float)
    if hist.sum() > 0:
        hist /= hist.sum()
    first = notes[:max(1, n // max(1, bars))]
    first = first[first >= 0] % 12
    bonus = np.zeros(24)
    root = None
    if len(first):
        fh = np.bincount(first, minlength=12) / float(len(first))
        r = int(np.argmax(fh))
        if fh[r] >= KEY_ROOT_MIN_SHARE:
            root = r
            for j in (r, 12 + r):
                if fit[j] >= fit.max() - KEY_ROOT_RANGE:
                    bonus[j] = KEY_ROOT_BONUS * fh[r]
    score = fit + bonus

    order = np.argsort(-score)
    k = int(order[0])
    relative = (k + 9) % 12 + 12 if k < 12 else (k - 12 + 3) % 12
    other = [j for j in order[1:] if j != relative]

    def name(j):
        return NAMES[j % 12], 'major' if j < 12 else 'minor'

    top3 = []
    for j in order[:3]:
        kn, sc = name(j)
        top3.append({'key': kn, 'scale': sc, 'score': round(float(score[j]), 3),
                     'fit': round(float(fit[j]), 3)})
    kn, sc = name(k)
    return {
        'keyPc': k % 12, 'key': kn, 'scale': sc,
        'keyScore': round(float(fit[k]), 3),
        'keyMargin': round(float(score[k] - score[order[1]]), 3),
        'keyMarginNonRelative': round(float(score[k] - score[other[0]]), 3),
        'keyTop3': top3,
        'bassRoot': NAMES[root] if root is not None else None,
        'bassPcs': [round(float(v), 3) for v in hist],
    }, notes


def _range(f, a, b, bass_notes):
    """lowNote / medianNote / highNote (MIDI): the 10th, 50th and 90th percentiles of the bass
    notes (taken an octave down where that octave sounds) and the top voice (the highest pitch
    within -10 dB of each frame's strongest, C3 to C7)."""
    S = f.semi_h[a:b]
    active = _active(f, a, b)
    tops = []
    upper = S[:, 48 - 24:97 - 24]
    for i in np.nonzero(active)[0]:
        row = upper[i]
        m = row.max()
        if m <= 0:
            continue
        pk = np.nonzero((row >= 0.3 * m) & (row >= np.roll(row, 1)) & (row >= np.roll(row, -1)))[0]
        if len(pk):
            tops.append(48 + int(pk[-1]))
    lows = []
    for i, v in enumerate(bass_notes):
        if v < 0:
            continue
        below = v - 12 - 24
        if below >= 0 and f.bass_h[a + i, below] >= 0.5 * f.bass_h[a + i, v - 24]:
            v -= 12
        lows.append(int(v))
    if len(lows) + len(tops) < 10:
        return None, None, None
    allp = np.array(lows + tops)
    low = int(np.percentile(lows, 10)) if len(lows) >= 5 else int(np.percentile(allp, 10))
    high = int(np.percentile(tops, 90)) if len(tops) >= 5 else int(np.percentile(allp, 90))
    return low, int(np.median(allp)), high


def _timbre(f, loop, sr, oa, ob, ta, tb):
    """The 0-127 descriptors of the app's analysis, from the normalised loop (level-dependent
    parts) and the input's frames over the window (spectral parts)."""
    gate = 1e-6  # -60 dBFS
    # frames active in the normalised loop: the input frames, rescaled to its level
    scale = _mean_square(loop) / max(1e-20, float(f.t_ms[ta:tb].mean()))
    act = f.t_ms[ta:tb] * scale > gate
    if act.sum() < 10:
        return None
    centroid = max(1.0, float(f.centroid[ta:tb][act].mean()))
    brightness = _to127(math.log(centroid / 200.0, 2) / math.log(25, 2))
    noisiness = _to127((float(f.flatness[ta:tb][act].mean()) + 3) / 2.75)

    # density: onset peaks (local max over +-32 ms, >= 64 ms apart, above mean + sd/2)
    o = f.onset[oa:ob]
    seconds = len(o) / f.o_fps
    half = max(1, int(round(0.032 * f.o_fps)))
    gap = max(1, int(round(0.064 * f.o_fps)))
    thr = o.mean() + 0.5 * o.std()
    onsets, last = 0, -gap
    for t in np.nonzero(o > thr)[0]:
        if o[t] >= o[max(0, t - half):t + half + 1].max() and t - last >= gap:
            onsets += 1
            last = t
    density = _to127(onsets / seconds / 8.0) if seconds > 0 else 0

    # attack slope and decay on a 4 ms level envelope (12 ms mean square, 0.5 dB steps)
    blk = int(round(0.004 * sr))
    nb = len(loop) // blk
    e = _block_ms(loop, blk, nb)  # of the mono mix
    e3 = (e + np.concatenate([[0.0], e[:-1]]) + np.concatenate([[0.0, 0.0], e[:-2]])) / 3.0
    env = np.clip(2 * (_db(e3) + 100), 0, 255).astype(int)
    g = int(2 * (-60 + 100))
    attacks, slope_sum = [], 0.0
    for i in range(1, nb):
        v = env[i]
        if v < g:
            continue
        lo, hi = max(0, i - 2), min(nb, i + 3)
        w = env[lo:hi]
        if w.max() > v or np.any(env[lo:i] == v):
            continue
        back = env[max(0, i - 12):i]
        if not len(back):
            continue
        lo_v = back.min()
        lo_i = i
        for j in range(i - 1, max(-1, i - 13), -1):
            if env[j] <= lo_v + 2:
                lo_i = j
                break
        if v - lo_v >= 18 and lo_i < i:
            slope_sum += 0.5 * (v - lo_v) / (i - lo_i)
            attacks.append(i)
    percussive = _to127(math.log(slope_sum / len(attacks), 2) / 4.0) if attacks else 0
    rates = []
    for n_, pk in enumerate(attacks):
        end = pk + 25
        if n_ + 1 < len(attacks) and end > attacks[n_ + 1] - 6:
            end = attacks[n_ + 1] - 6
        end = min(end, nb - 1)
        if end - pk >= 5:
            drop = 0.5 * (env[pk] - env[end])
            rates.append(min(200.0, max(0.0, drop)) / ((end - pk) * 0.004))
    if rates:
        rate = float(np.mean(rates))
        sustain = 127 if rate <= 5 else _to127(1 - math.log(rate / 5.0, 2) / math.log(60, 2))
    else:
        sustain = 127
    return {'brightness': brightness, 'noisiness': noisiness, 'percussiveness': percussive,
            'sustain': sustain, 'density': density}


# ── the window ───────────────────────────────────────────────────────────

def _runs(mask):
    """Lengths of the runs of True in a boolean array."""
    if not len(mask):
        return np.zeros(0, int)
    d = np.diff(np.concatenate([[0], mask.astype(int), [0]]))
    return np.nonzero(d == -1)[0] - np.nonzero(d == 1)[0]


def _downbeat(f, phase, P, bpb, beat_sec, start):
    """Bar-line offset (frames, a multiple of half a beat from phase) where low-band attacks and
    harmonic change gather, with a bonus for the position the music starts on (frame `start`,
    after any intro silence: generated tracks start on a downbeat). Half beats are candidates
    because the strongest pulse can be the off-beat (off-beat bass and hats)."""
    step = P / 2.0
    first = phase - step * math.floor(phase / step)
    pos = np.arange(first, len(f.onset), step)
    if len(pos) < 4 * bpb:
        return phase
    low = np.array([_peak_near(f.onset_low, p, 2) for p in pos])
    full = np.array([_peak_near(f.onset, p, 2) for p in pos])
    chroma = _chroma_frames(f.semi_h)
    span = max(1, int(round(f.t_fps * beat_sec)))
    nov = np.zeros(len(pos))
    for i, p in enumerate(pos):
        tf = int(round(f.o_time(p) * f.t_fps))
        if span <= tf <= len(chroma) - span:
            nov[i] = 1 - _corr(chroma[tf - span:tf].mean(axis=0), chroma[tf:tf + span].mean(axis=0))
    halves = 2 * bpb
    score = np.zeros(halves)
    for d in range(halves):
        sel = np.arange(d, len(pos), halves)
        score[d] = (low[sel].mean() / max(1e-9, low.mean())
                    + nov[sel].mean() / max(1e-9, nov.mean())
                    + 0.5 * full[sel].mean() / max(1e-9, full.mean()))
        bar = halves * step
        off = (start - (first + d * step)) % bar
        if min(off, bar - off) <= P / 8.0:
            score[d] += START_BONUS
    return first + int(np.argmax(score)) * step


def _find_window(f, bpm, bars, bpb, n):
    """(start sample, details) of the best bars-long window that starts on a downbeat, or
    (None, {})."""
    sr = f.sr
    beat_sec = 60.0 / bpm
    L = int(round(bars * bpb * beat_sec * sr))
    ms = f.blk_ms
    if L > n or len(ms) < 5:
        return None, {}

    # gaps: 50 ms windows (10 ms steps) this far under the track's loud level
    cs = np.concatenate([[0.0], np.cumsum(ms)])
    db50 = _db((cs[5:] - cs[:-5]) / 5.0)  # the 50 ms starting at block i
    loud = float(np.percentile(db50, 95))
    if loud < SILENCE_FLOOR_DB + 10:
        return None, {}
    silent_db = max(SILENCE_FLOOR_DB, loud - SILENCE_REL_DB)
    gap = db50 < silent_db
    beat_blocks = max(1, int(beat_sec / 0.01))

    def gaps_ok(s):
        # The seam (first and last beat) must sound throughout; inside, a musical stop of up to a
        # beat is fine. Intro silence and the trailing fade fall on the seam or run longer.
        g = gap[s // f.blk:max(s // f.blk + 1, (s + L) // f.blk - 4)]
        if g[:beat_blocks].any() or g[-beat_blocks:].any():
            return False
        r = _runs(g)
        return not len(r) or r.max() <= beat_blocks

    P = f.o_fps * beat_sec
    sounding = np.nonzero(~gap)[0]
    if len(sounding) == 0:
        return None, {}
    oa = max(0, int(f.o_frame(sounding[0] * 0.01)))
    ob = min(len(f.onset), int(f.o_frame((sounding[-1] + 5) * 0.01)) + 1)
    if ob - oa < 4 * P:
        oa, ob = 0, len(f.onset)
    phase = _fold_phase(f.onset, P, oa, ob)

    if n - L <= 2 * EDGE_TOL_SEC * sr:
        # the input is already the loop (or within a hair of it): the whole file is the window
        return (0, {'L': L, 'bar': 0, 'whole': True}) if gaps_ok(0) else (None, {})

    # bar lines from the downbeat
    down = _downbeat(f, phase, P, bpb, beat_sec, f.o_frame(sounding[0] * 0.01))
    bar_frames = P * bpb
    first = down - bar_frames * math.ceil((down + f.o_bias * f.o_fps) / bar_frames)
    count = int((len(f.onset) - first) / bar_frames) + 2
    bar_s = np.round(np.array([f.o_time(first + k * bar_frames) for k in range(count)]) * sr).astype(int)
    bar_len = int(round(bar_frames / f.o_fps * sr))
    chroma = _chroma_frames(f.semi_h)

    def bar_stats(k):
        a, b = bar_s[k], bar_s[k] + bar_len
        if a < -EDGE_TOL_SEC * sr or b > n + EDGE_TOL_SEC * sr:
            return None
        a, b = max(0, a), min(n, b)
        ba, bb = a // f.blk, min(len(ms), b // f.blk)
        fa, fb = int(f.o_frame(a / float(sr))), min(len(f.onset), int(f.o_frame(b / float(sr))))
        ta, tb = int(a / float(sr) * f.t_fps), min(len(chroma), int(b / float(sr) * f.t_fps))
        if bb - ba < 2 or fb - fa < 2 or tb - ta < 1:
            return None
        return (float(_db(ms[ba:bb].mean())), f.band_db[max(0, fa):fb].mean(axis=0),
                _norm_mean(chroma[ta:tb]))

    stats = [bar_stats(k) for k in range(count)]
    levels = [st[0] for st in stats if st is not None and st[0] > silent_db]
    if not levels:
        return None, {}
    med_level = float(np.median(levels))
    first_sounding = next(k for k, st in enumerate(stats) if st is not None and st[0] > silent_db)

    def distance(p, q):
        return (float(np.sqrt(((p[1] - q[1]) ** 2).mean())) / 3.0 + (1 - _corr(p[2], q[2]))
                + abs(p[0] - q[0]) / 3.0)

    edge = max(2, int(round(0.1 * f.o_fps)))

    def spectrum(t0):
        a = int(round(f.o_frame(t0)))
        g0, g1 = int(t0 / 0.01), int(t0 / 0.01 + edge / f.o_fps / 0.01)
        if a < 0 or a + edge > len(f.band_db) or g0 < 0 or gap[g0:max(g0 + 1, g1)].any():
            return None  # outside the track, or silence (an intro or the tail): nothing to match
        return f.band_db[a:a + edge].mean(axis=0)

    def local_seam(s):
        # the 100 ms before the loop's end should sound like the 100 ms that lead into its start
        # in the track, and the 100 ms after its end like its first 100 ms (where they sound)
        t0, t1, w = s / float(sr), (s + L) / float(sr), edge / f.o_fps
        d = []
        for p, q in ((spectrum(t1 - w), spectrum(t0 - w)), (spectrum(t1), spectrum(t0))):
            if p is not None and q is not None:
                d.append(float(np.sqrt(((p - q) ** 2).mean())) / 3.0)
        return float(np.mean(d)) if d else 0.0

    cands = []
    for k in range(count):
        s = bar_s[k]
        if s < -EDGE_TOL_SEC * sr or s + L > n + EDGE_TOL_SEC * sr:
            continue
        s = min(max(s, 0), n - L)
        win = stats[k:k + bars]
        if len(win) < bars or any(w is None or w[0] < med_level - BAR_DROP_DB for w in win):
            continue
        if not gaps_ok(s):
            continue
        # steadiness: bar levels and bar spectra close to the window's own mean
        lv = np.array([w[0] for w in win])
        tim = np.array([w[1] for w in win])
        cost = lv.std() / 3.0 + float(np.sqrt(((tim - tim.mean(axis=0)) ** 2).mean(axis=1)).mean()) / 3.0
        # seam: the bar that follows the window in the track should resemble its first bar (or the
        # bar before it its last), so the jump back sounds like the track going on
        nxt = stats[k + bars] if k + bars < count else None
        prv = stats[k - 1] if k >= 1 else None
        if nxt is not None and nxt[0] > silent_db:
            seam = distance(nxt, win[0])
        elif prv is not None and prv[0] > silent_db:
            seam = distance(prv, win[-1])
        else:
            seam = 0.0
        seam += local_seam(s)
        cands.append((k, s, cost, seam, 0.0 if (k - first_sounding) % 4 == 0 else 1.0))
    if not cands:
        return None, {}
    # each term relative to its median over the candidates, so none swamps the others; a window on
    # a 4-bar phrase line (counted from the first sounding bar) is preferred
    mc = max(1e-9, float(np.median([c[2] for c in cands])))
    ms_ = max(1e-9, float(np.median([c[3] for c in cands])))
    totals = [c[2] / mc + 0.5 * c[3] / ms_ + PHRASE_PENALTY * c[4] for c in cands]
    k, s = cands[int(np.argmin(totals))][:2]

    # refine the start on the window's own beat phase (the grid can drift over a long track)
    fa = max(0, int(f.o_frame(s / float(sr))))
    fb = min(len(f.onset), int(f.o_frame((s + L) / float(sr))))
    if fb - fa > 2 * P:
        lp = _fold_phase(f.onset, P, fa, fb)
        pos = f.o_frame(s / float(sr))
        cand = lp + P * round((pos - lp) / P)
        if abs(cand - pos) <= P / 4:
            s2 = int(round(f.o_time(cand) * sr))
            if s2 >= -EDGE_TOL_SEC * sr and s2 + L <= n + EDGE_TOL_SEC * sr:
                s2 = min(max(s2, 0), n - L)
                if gaps_ok(s2):
                    s = s2
    return s, {'L': L, 'bar': k - first_sounding, 'whole': False}


def _fine_onsets(mono, sr, a, b, hop):
    """Log-band spectral flux of mono[a:b] on a `hop`-sample grid (frame i centred on a + i * hop):
    the onset signal of _Features at a finer hop, for placing beats to a fraction of a millisecond."""
    n_fft = _pow2(0.0213 * sr)
    edges_hz = np.geomspace(30.0, min(16000.0, sr * 0.475), 37)
    edges = np.unique(np.clip(np.round(edges_hz * n_fft / sr).astype(int), 1, n_fft // 2))

    def bands_db(power):
        return _db(np.add.reduceat(power, edges, axis=1)[:, :-1], 1e-30).astype(np.float32)
    seg = mono[max(0, a):b]
    db = _stft_reduce(seg, n_fft, hop, bands_db, 1 + len(seg) // hop)
    db -= max(float(db.max()), -120.0)  # 0 dB at the loudest band, floor -80
    np.maximum(db, -80.0, out=db)
    lag = max(1, int(round(0.005 * sr / hop)))
    o = np.zeros(len(db))
    rows = max(1, CHUNK // db.shape[1])
    for i in range(lag, len(db), rows):
        j = min(len(db), i + rows)
        o[i:j] = np.maximum(db[i:j] - db[i - lag:j - lag], 0).mean(axis=1)
    # less its +-50 ms mean, so a busy mix's steady flux doesn't swamp the beats
    h = max(1, int(round(0.05 * sr / hop)))
    cs = np.concatenate([[0.0], np.cumsum(o)])
    idx = np.arange(len(o))
    lo, hi = np.maximum(0, idx - h), np.minimum(len(o), idx + h + 1)
    return np.maximum(0.0, o - (cs[hi] - cs[lo]) / (hi - lo))


def _align(o, centre, tmpl, pre, search):
    """(offset, strength): where `tmpl` (starting `pre` frames before its beat) best matches `o`
    within +-search frames of `centre`, to a fraction of a frame (parabolic peak)."""
    c = int(round(centre))
    a, b = c - pre - search, c - pre + len(tmpl) + search
    if a < 0 or b > len(o):
        return None, 0.0
    cc = np.correlate(o[a:b], tmpl, 'valid')
    i = int(np.argmax(cc))
    frac = 0.0
    if 0 < i < len(cc) - 1:
        y0, y1, y2 = cc[i - 1], cc[i], cc[i + 1]
        den = y0 - 2 * y1 + y2
        if den < 0:
            frac = 0.5 * (y0 - y2) / den
    return a + i + frac + pre - centre, float(cc[i])


def _beat_period(mono, sr, start, period, count):
    """Beat period in samples from a line fitted to the beat times after `start` (beats -1 to
    count + 1, about `period` apart), or None when the beats don't hold a steady line (soft or
    smeared attacks). Each beat is placed by matching a 1 ms onset signal to the window's average
    beat; on clean beats the line pins the loop length to a few samples, so a loop cut from it
    lands on the beat at the seam."""
    hop = max(1, int(round(0.001 * sr)))
    a = int(start - 2 * period)
    o = _fine_onsets(mono, sr, a, int(start + (count + 3) * period), hop)
    a = max(0, a)
    pre, post = int(0.02 * sr / hop), int(0.08 * sr / hop)
    search = int(period / 6 / hop)
    ks = np.arange(-1, count + 2)
    times = (start - a + ks * period) / float(hop)  # beat k in onset frames

    slope = icpt = None
    for _ in range(2):
        segs = [o[int(round(t)) - pre:int(round(t)) + post] for t in times
                if int(round(t)) - pre >= 0 and int(round(t)) + post <= len(o)]
        if not segs:
            return None
        tmpl = np.mean(segs, axis=0)
        tmpl -= tmpl.mean()
        if not np.any(tmpl > 0):
            return None
        got = [(k, t) + _align(o, t, tmpl, pre, search) for k, t in zip(ks, times)]
        got = [g for g in got if g[2] is not None]
        if len(got) < 8:
            return None
        kk = np.array([g[0] for g in got], float)
        tt = np.array([g[1] + g[2] for g in got], float)
        ww = np.array([g[3] for g in got], float)
        keep = ww >= 0.25 * np.median(ww)
        for _ in range(4):
            if keep.sum() < 8:
                return None
            slope, icpt = np.polyfit(kk[keep], tt[keep], 1)
            res = tt - (icpt + slope * kk)
            mad = float(np.median(np.abs(res[keep])))
            new = keep & (np.abs(res) <= max(3 * 1.4826 * mad, 0.5))
            if (new == keep).all():
                break
            keep = new
        if keep.sum() < max(8, count // 3) or mad * hop > 0.01 * period:
            return None
        times = icpt + slope * ks
        search = max(2, int(0.01 * sr / hop))
    slope *= hop
    if abs(slope / period - 1) > 0.005:
        return None
    return float(slope)


def _read_mono(path):
    """(float32 mono mix of the first two channels, sample rate), read in blocks so the whole
    stereo file is never held."""
    with sf.SoundFile(path) as fh:
        sr, ch = fh.samplerate, fh.channels
        mono = np.empty(max(0, fh.frames), np.float32)
        i = 0
        while True:
            blk = fh.read(CHUNK, dtype='float32', always_2d=True)
            if not len(blk):
                break
            m = blk[:, :2].mean(axis=1) if ch >= 2 else blk[:, 0]
            if i + len(m) > len(mono):
                mono = np.concatenate([mono[:i], np.empty(i + len(m) - len(mono), np.float32)])
            mono[i:i + len(m)] = m
            i += len(m)
    return mono[:i], sr


def _read_stereo(path, a, b):
    """Samples a..b of the file as float32 stereo (mono duplicated, extra channels dropped)."""
    with sf.SoundFile(path) as fh:
        fh.seek(a)
        x = fh.read(b - a, dtype='float32', always_2d=True)
    if x.shape[1] == 1:
        return np.repeat(x, 2, axis=1)
    return np.ascontiguousarray(x[:, :2]) if x.shape[1] > 2 else x


def _cut(x, s, L, sr):
    """x[s:s+L] with an equal-power crossfade at the seam. The audio that follows the window fades
    out over its head, so the last sample flows into the first; when the track ends there (the
    music stops), the audio before the window fades into its tail instead; when neither
    neighbour sounds, the window already starts and ends on silence and is left as it is."""
    F = int(round(SEAM_SEC * sr))
    loop = x[s:s + L]  # a view: x is this call's own copy of the region, crossfaded in place
    if F >= L:
        return loop, 'none'

    def rms(a):
        return float(np.sqrt(np.mean(np.square(a, dtype=np.float64)))) if len(a) else 0.0

    t = (np.arange(F) + 0.5) / F
    fin = np.sin(0.5 * np.pi * t)[:, None]
    fout = np.cos(0.5 * np.pi * t)[:, None]
    post = x[s + L:s + L + F]
    pre = x[max(0, s - F):s]
    if len(post) == F and rms(post) >= 0.1 * rms(loop[:F]):
        loop[:F] = loop[:F] * fin + post * fout
        return loop, 'after'
    if len(pre) == F and rms(pre) >= 0.1 * rms(loop[L - F:]):
        loop[L - F:] = loop[L - F:] * fout + pre * fin
        return loop, 'before'
    return loop, 'none'


# ── entry points ─────────────────────────────────────────────────────────

def _empty(bpm, reason):
    """The failure answer: the same keys as a success, unmeasured ones null."""
    out = dict.fromkeys(RESULT_KEYS)
    out.update({'ok': False, 'reason': reason, 'bpm': bpm, 'keyTop3': []})
    return out


def pitch_class(key):
    """'A', 'Bb', 'C#' or '0'..'11' -> 0..11."""
    s = str(key).strip()
    if s.isdigit() and 0 <= int(s) <= 11:
        return int(s)
    k = s[:1].upper() + s[1:].upper().replace('♭', 'B').replace('♯', '#')
    if k not in _PC:
        raise ValueError('unknown key: %r' % (key,))
    return _PC[k]


def post(in_path, out_path, bpm, bars, beats_per_bar, key, scale):
    """Cut in_path into a bars-long loop at out_path (FLAC, 16-bit, stereo, the input's rate) and
    measure it. Returns the dict the CLI prints."""
    bpm = float(bpm)
    bars, bpb = int(bars), int(beats_per_bar)
    if not 20 <= bpm <= 300 or bars < 1 or bpb < 1:
        raise ValueError('bad bpm, bars or beats per bar')
    req_pc = pitch_class(key)
    scale = str(scale).lower()
    if scale not in ('major', 'minor'):
        raise ValueError('scale must be major or minor')
    bpm_out = int(bpm) if bpm == int(bpm) else bpm

    mono, sr = _read_mono(in_path)
    n = len(mono)
    if n < sr:
        return _empty(bpm_out, 'no_loop_window')
    f = _Features(mono, sr)

    s, info = _find_window(f, bpm, bars, bpb, n)
    measured, match, _ = _tempo(f.onset, f.o_fps, bpm)
    if s is None:
        res = _empty(bpm_out, 'no_loop_window')
        res['bpmMeasured'] = round(measured, 2) if measured else None
        res['bpmMatch'] = match
        return res
    L = info['L']
    beats = bars * bpb
    if match is not None:
        # tempo measured over the loop itself
        oa = max(0, int(f.o_frame(s / float(sr))))
        ob = min(len(f.onset), int(f.o_frame((s + L) / float(sr))))
        m2, match2, _ = _tempo(f.onset[oa:ob], f.o_fps, bpm)
        if match2 is not None:
            measured, match = m2, match2
    mult = {'x1': 1.0, 'x2': 2.0, 'x0.5': 0.5}.get(match)
    if mult:
        # Cut on the track's own beat, not the requested one: a 0.1 % tempo error is 17 ms at an
        # 8-bar seam. The period is fitted to the window's beats on the requested grid (so the
        # octave is the request's); loopBpm is the tempo the cut loop plays at. An input that is
        # already the loop keeps its length, and its drift says how far it is off its own beat.
        period = _beat_period(mono, sr, s, 60.0 * sr / (measured / mult), beats)
        if period is not None and abs(60.0 * sr / period / bpm - 1) <= BPM_TOL:
            measured = 60.0 * sr / period * mult
        L_meas = int(round(beats * 60.0 / (measured / mult) * sr))
        if not info['whole'] and s + L_meas <= n:
            L = L_meas

    del mono
    F = int(round(SEAM_SEC * sr))
    ra, rb = max(0, s - F), min(n, s + L + F)
    loop, seam = _cut(_read_stereo(in_path, ra, rb), s - ra, L, sr)
    lufs = _normalise(loop, sr)  # in place
    peak = _write_pcm16(out_path, loop, sr)

    ta, tb = int(s / float(sr) * f.t_fps), max(int((s + L) / float(sr) * f.t_fps), int(s / float(sr) * f.t_fps) + 3)
    tb = min(tb, len(f.t_ms))
    key_info, bass_notes = _measure_key(f, ta, tb, bars)
    low, med, high = _range(f, ta, tb, bass_notes)
    oa = max(0, int(f.o_frame(s / float(sr))))
    ob = min(len(f.onset), int(f.o_frame((s + L) / float(sr))))
    timbre = _timbre(f, loop, sr, oa, ob, ta, tb)

    drift_ms = None
    if mult:
        true_len = beats * 60.0 / (measured / mult)
        drift_ms = round((true_len - L / float(sr)) * 1000.0, 1)
    return {
        'ok': True,
        'reason': None,
        'bpm': bpm_out,
        'bpmMeasured': round(measured, 3) if measured else None,
        'bpmMatch': match,
        'loopBpm': round(beats * 60.0 * sr / L, 3),
        'driftMs': drift_ms,
        'loopStartSec': round(s / float(sr), 4),
        'loopSamples': L,
        'sampleRate': sr,
        'loopStartBar': info['bar'],
        'seam': seam,
        'key': key_info['key'],
        'keyPc': key_info['keyPc'],
        'scale': key_info['scale'],
        'keyMatch': key_info['keyPc'] == req_pc and key_info['scale'] == scale,
        'keyScore': key_info['keyScore'],
        'keyMargin': key_info['keyMargin'],
        'keyMarginNonRelative': key_info['keyMarginNonRelative'],
        'keyTop3': key_info['keyTop3'],
        'bassRoot': key_info['bassRoot'],
        'bassPcs': key_info['bassPcs'],
        'lufs': round(lufs, 2) if np.isfinite(lufs) else None,
        'peakDb': round(20 * math.log10(max(peak, 1e-9)), 2),
        'lowNote': low,
        'medianNote': med,
        'highNote': high,
        'timbre': timbre,
    }


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('--in', dest='in_path', required=True)
    p.add_argument('--out', dest='out_path', required=True)
    p.add_argument('--bpm', type=float, required=True)
    p.add_argument('--bars', type=int, required=True)
    p.add_argument('--beats-per-bar', type=int, default=4)
    p.add_argument('--key', required=True)
    p.add_argument('--scale', required=True)
    a = p.parse_args(argv)
    res = post(a.in_path, a.out_path, a.bpm, a.bars, a.beats_per_bar, a.key, a.scale)
    sys.stdout.write(json.dumps(res) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())

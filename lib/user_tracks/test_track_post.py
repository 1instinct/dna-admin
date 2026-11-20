"""Tests for track_post.py on synthetic audio (stdlib unittest, numpy and soundfile only).

Run from the repo root:
    python3 -m unittest lib/user_tracks/test_track_post.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import track_post  # noqa: E402

SR = 48000


def _midi_hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def _tone(midi, n, amp, sr=SR, harmonics=(1.0, 0.5, 0.25)):
    t = np.arange(n) / float(sr)
    f = _midi_hz(midi)
    y = np.zeros(n)
    for h, a in enumerate(harmonics):
        y += a * np.sin(2 * np.pi * f * (h + 1) * t)
    return amp * y


def _click(n, sr=SR, low=True):
    """A kick-like thump (low=True) or a short noise hat."""
    t = np.arange(n) / float(sr)
    if low:
        f = 55.0 + 90.0 * np.exp(-t / 0.02)
        return np.sin(2 * np.pi * np.cumsum(f) / sr) * np.exp(-t / 0.09)
    rs = np.random.RandomState(3)
    return rs.uniform(-1, 1, n) * np.exp(-t / 0.012)


def make_track(bpm, bars, chords, lead=1.0, tail=2.0, beats_per_bar=4, hats=False,
               accent=True, chord_amp=0.12, bass=True, sr=SR):
    """Beats (a low thump on every beat, louder on the downbeat), optional eighth-note hats, and a
    sustained chord per bar (cycling through `chords`, lists of MIDI notes) with its first note an
    octave down as a bass. Returns (stereo float array, click times in seconds)."""
    beat = 60.0 / bpm
    music = int(round(bars * beats_per_bar * beat * sr))
    n0 = int(round(lead * sr))
    total = n0 + music + int(round(tail * sr))
    y = np.zeros(total)
    clicks = []
    kick_n = int(0.25 * sr)
    for j in range(bars * beats_per_bar):
        p = n0 + int(round(j * beat * sr))
        clicks.append(p / float(sr))
        amp = 0.8 if (accent and j % beats_per_bar == 0) else 0.45
        seg = _click(min(kick_n, total - p), sr)
        y[p:p + len(seg)] += amp * seg
        if hats:
            for half in (0.0, 0.5):
                q = n0 + int(round((j + half) * beat * sr))
                hseg = _click(min(int(0.04 * sr), total - q), sr, low=False)
                y[q:q + len(hseg)] += 0.12 * hseg
    bar_n = beat * beats_per_bar * sr
    for b in range(bars):
        a = n0 + int(round(b * bar_n))
        e = n0 + int(round((b + 1) * bar_n))
        notes = chords[b % len(chords)]
        seg = np.zeros(e - a)
        for m in notes:
            seg += _tone(m, e - a, chord_amp, sr)
        if bass:
            seg += _tone(notes[0] - 12, e - a, chord_amp * 1.5, sr)
        ramp = min(int(0.01 * sr), (e - a) // 2)
        env = np.ones(e - a)
        env[:ramp] = np.linspace(0, 1, ramp)
        env[-ramp:] = np.linspace(1, 0, ramp)
        y[a:e] += seg * env
    y = y / max(1e-9, np.max(np.abs(y))) * 0.5
    return np.stack([y, y], axis=1), clicks


C_MAJOR = [[60, 64, 67], [65, 69, 72], [67, 71, 74], [60, 64, 67]]  # I IV V I
A_MINOR = [[57, 60, 64], [62, 65, 69], [64, 68, 71], [57, 60, 64]]  # i iv V i


class TrackPostTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def _write(self, name, data, sr=SR):
        path = os.path.join(self.dir, name)
        sf.write(path, data, sr, subtype='PCM_16')
        return path

    def _post(self, data, bpm, bars, key='C', scale='major', beats_per_bar=4):
        src = self._write('in.wav', data)
        out = os.path.join(self.dir, 'loop.flac')
        res = track_post.post(src, out, bpm, bars, beats_per_bar, key, scale)
        return res, out

    def test_cuts_whole_bars(self):
        data, clicks = make_track(100, 10, C_MAJOR, lead=1.0, tail=2.0)
        res, out = self._post(data, 100, 8)
        self.assertTrue(res['ok'], res)
        # cut on the measured beat: within 0.2 ms of the rendered 8 bars (chord changes bias the
        # beat placement by a sample or two)
        self.assertAlmostEqual(res['loopSamples'], 8 * 4 * 60.0 / 100 * SR, delta=10)
        self.assertEqual(res['sampleRate'], SR)
        after = [c for c in clicks if c >= 1.0]
        nearest = min(abs(res['loopStartSec'] - c) for c in after)
        self.assertLessEqual(nearest, 0.6, res['loopStartSec'])
        self.assertGreaterEqual(res['loopStartSec'], 1.0 - 0.6)
        audio, sr = sf.read(out, always_2d=True)
        self.assertEqual(sr, SR)
        self.assertEqual(audio.shape, (res['loopSamples'], 2))

    def test_loop_follows_the_tracks_own_tempo(self):
        # clicks over a held chord rendered at 100.1 bpm, asked for 100: a loop cut at 100 would be
        # 17 ms long at the seam
        data, _ = make_track(100.1, 10, [A_MINOR[0]], lead=1.0, tail=2.0, hats=True)
        res, out = self._post(data, 100, 8, 'A', 'minor')
        self.assertTrue(res['ok'], res)
        self.assertEqual(res['bpm'], 100)
        self.assertEqual(res['bpmMatch'], 'x1')
        self.assertAlmostEqual(res['loopSamples'], 8 * 4 * 60.0 / 100.1 * SR, delta=1.0)
        self.assertAlmostEqual(res['loopBpm'], 100.1, delta=0.002)
        self.assertLess(abs(res['driftMs']), 0.1)
        audio, _ = sf.read(out, always_2d=True)
        self.assertEqual(audio.shape[0], res['loopSamples'])

    def test_seam_is_continuous(self):
        data, _ = make_track(100, 10, C_MAJOR, lead=1.0, tail=2.0)
        res, out = self._post(data, 100, 8)
        self.assertTrue(res['ok'], res)
        audio, sr = sf.read(out, always_2d=True)
        jump = np.max(np.abs(audio[-1] - audio[0]))
        self.assertLess(jump, 0.05)
        mono = audio.mean(axis=1)
        win = int(0.05 * sr)
        n = len(mono) // win
        rms = np.sqrt(np.mean(mono[:n * win].reshape(n, win) ** 2, axis=1))
        db = 20 * np.log10(rms + 1e-12)
        self.assertGreater(db.min(), -50.0)

    def test_key_c_major_triads(self):
        data, _ = make_track(100, 10, C_MAJOR)
        res, _ = self._post(data, 100, 8, 'C', 'major')
        self.assertTrue(res['ok'], res)
        self.assertEqual((res['key'], res['scale']), ('C', 'major'), res['keyTop3'])
        self.assertGreaterEqual(res['keyScore'], 0.75)

    def test_key_a_minor_triads(self):
        data, _ = make_track(100, 10, A_MINOR)
        res, _ = self._post(data, 100, 8, 'A', 'minor')
        self.assertTrue(res['ok'], res)
        self.assertEqual((res['key'], res['scale']), ('A', 'minor'), res['keyTop3'])
        self.assertGreaterEqual(res['keyScore'], 0.75)

    def test_tempo_match_octaves(self):
        data, _ = make_track(84, 10, C_MAJOR, hats=True)
        res, _ = self._post(data, 84, 8)
        self.assertTrue(res['ok'], res)
        self.assertIn(res['bpmMatch'], ('x1', 'x2'), res['bpmMeasured'])
        data, _ = make_track(100, 14, C_MAJOR)
        res, _ = self._post(data, 124, 8)
        self.assertIsNone(res['bpmMatch'], res['bpmMeasured'])

    def test_silent_input(self):
        src = self._write('silence.wav', np.zeros((30 * SR, 2)))
        out = os.path.join(self.dir, 'loop.flac')
        proc = subprocess.run(
            [sys.executable, os.path.join(HERE, 'track_post.py'), '--in', src, '--out', out,
             '--bpm', '100', '--bars', '8', '--beats-per-bar', '4', '--key', 'A', '--scale', 'minor'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        res = json.loads(proc.stdout.decode('utf-8'))
        self.assertFalse(res['ok'])
        self.assertEqual(res['reason'], 'no_loop_window')

    def test_too_short_input(self):
        data, _ = make_track(100, 4, C_MAJOR, lead=0.5, tail=0.5)
        res, _ = self._post(data, 100, 8)
        self.assertFalse(res['ok'])
        self.assertEqual(res['reason'], 'no_loop_window')
        self.assertEqual(sorted(res), sorted(track_post.RESULT_KEYS))

    def test_success_has_every_key(self):
        data, _ = make_track(100, 10, C_MAJOR)
        res, _ = self._post(data, 100, 8)
        self.assertTrue(res['ok'], res)
        self.assertEqual(sorted(res), sorted(track_post.RESULT_KEYS))

    def test_input_that_is_already_the_loop(self):
        # an exact 8-bar file (a finished loop) is cut whole
        data, _ = make_track(100, 8, C_MAJOR, lead=0.0, tail=0.0)
        res, out = self._post(data, 100, 8)
        self.assertTrue(res['ok'], res)
        self.assertEqual(res['loopStartSec'], 0.0)
        self.assertEqual(res['loopSamples'], len(data))

    def test_loudness(self):
        data, _ = make_track(100, 10, C_MAJOR)
        res, out = self._post(data * 0.1, 100, 8)
        self.assertTrue(res['ok'], res)
        audio, sr = sf.read(out, always_2d=True)
        lufs = track_post.integrated_lufs(audio, sr)
        self.assertLessEqual(abs(lufs + 16.0), 1.5, lufs)
        peak_db = 20 * np.log10(np.max(np.abs(audio)))
        self.assertLessEqual(peak_db, -1.0 + 1e-3)
        self.assertLessEqual(abs(res['lufs'] - lufs), 0.2)

    def test_lufs_reference_sine(self):
        # BS.1770: a 997 Hz sine at 0 dBFS in one channel reads -3.01 LUFS, so -20 dBFS in both
        # channels reads -20 LUFS.
        t = np.arange(10 * SR) / float(SR)
        y = 0.1 * np.sin(2 * np.pi * 997 * t)
        lufs = track_post.integrated_lufs(np.stack([y, y], axis=1), SR)
        self.assertAlmostEqual(lufs, -20.0, delta=0.3)

    def test_cli_prints_one_json_object(self):
        data, _ = make_track(100, 10, C_MAJOR)
        src = self._write('in.wav', data)
        out = os.path.join(self.dir, 'loop.flac')
        proc = subprocess.run(
            [sys.executable, os.path.join(HERE, 'track_post.py'), '--in', src, '--out', out,
             '--bpm', '100', '--bars', '8', '--beats-per-bar', '4', '--key', 'C', '--scale', 'major'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        res = json.loads(proc.stdout.decode('utf-8'))
        for k in ('ok', 'bpm', 'bpmMeasured', 'bpmMatch', 'loopStartSec', 'loopSamples', 'sampleRate',
                  'key', 'scale', 'keyScore', 'keyMargin', 'keyTop3', 'lufs', 'peakDb', 'lowNote',
                  'highNote', 'timbre'):
            self.assertIn(k, res)
        self.assertEqual(res['bpm'], 100)
        self.assertEqual(len(res['keyTop3']), 3)
        self.assertTrue(os.path.exists(out))
        timbre = res['timbre']
        self.assertIsNotNone(timbre)
        for k in ('brightness', 'noisiness', 'percussiveness', 'sustain', 'density'):
            self.assertTrue(0 <= timbre[k] <= 127, (k, timbre[k]))


if __name__ == '__main__':
    unittest.main()

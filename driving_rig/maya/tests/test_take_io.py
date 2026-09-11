"""Contract tests for take_io — plain Python or mayapy, no Maya scene needed.

    mayapy -m unittest discover -s maya/tests -v          (from the project root)
    python  -m unittest discover -s maya/tests -v

fixture_take.json.gz was written by the Godot project (TakeFormat.write_take), and
fixture_expected.json holds what Godot's own decoder reads back from it. If these pass,
Python and Godot agree on the format, bit for bit.
"""
import gzip
import json
import math
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from driving_rig import take_io  # noqa: E402

FIXTURE = os.path.join(HERE, "fixture_take.json.gz")
EXPECTED = os.path.join(HERE, "fixture_expected.json")


class TakeIoContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.take = take_io.load(FIXTURE)
        with open(EXPECTED) as f:
            cls.expected = json.load(f)

    def test_header(self):
        t = self.take
        self.assertEqual(t.format_version, 2)
        self.assertEqual(t.n, 400)
        self.assertEqual(t.tick_hz, 240.0)
        self.assertEqual((t.in_index, t.out_index), (80, 320))
        self.assertAlmostEqual(t.duration, 1.0)
        self.assertEqual(len(t.meta["hardpoints"]), 4)

    def test_matches_godot_decoder(self):
        """Every channel, every component, every wheel, at several samples."""
        t = self.take
        checked = 0
        for name, per_sample in self.expected["values"].items():
            group, comps, _ = take_io.CHANNELS[name]
            per_wheel = group == "wheel"
            for k, i in enumerate(self.expected["samples"]):
                for w, comp_vals in enumerate(per_sample[k]):
                    for c, want in enumerate(comp_vals):
                        ch = t[name][w] if per_wheel else t[name]
                        got = (ch if comps == 1 else ch[c])[i]
                        self.assertEqual(float(got), float(want), "%s w%d c%d @%d" % (name, w, c, i))
                        checked += 1
        self.assertGreater(checked, 250)

    def test_times(self):
        ts = self.take.times()
        self.assertEqual(ts[80], 0.0)
        self.assertAlmostEqual(ts[0], -80 / 240.0)
        self.assertAlmostEqual(ts[320], 1.0)

    def test_frame_grid_has_handles(self):
        frames, times = self.take.frame_grid(24, in_frame=1001)
        self.assertIn(1001, frames)
        self.assertLessEqual(frames[0], 1001 - 8)   # ≥ 8 frames of pre-roll at 24 fps
        self.assertEqual(frames.index(1001), [round(x, 9) for x in times].index(0.0))

    def test_resample_exact_on_samples(self):
        t = self.take
        x = t["chassis.p"][0]
        src = t.times()
        self.assertEqual(t.resample(x, [src[100], src[101]]), [x[100], x[101]])
        mid = t.resample(x, [(src[100] + src[101]) / 2])[0]
        self.assertAlmostEqual(mid, (x[100] + x[101]) / 2)

    def test_spin_monotonic_forward(self):
        """Car drives forward in this take: cumulative spin must never wrap back."""
        for w in take_io.WHEELS:
            s = self.take.wheel(w, "wheels.spin_cumulative")
            drops = sum(1 for a, b in zip(s, s[1:]) if b < a - 0.5)
            self.assertEqual(drops, 0, "spin wrapped on %s" % w)

    def test_quaternions_unit(self):
        q = self.take["chassis.q"]
        for i in range(0, self.take.n, 37):
            self.assertAlmostEqual(math.sqrt(sum(q[c][i] ** 2 for c in range(4))), 1.0, places=5)

    def test_plain_json_same_as_gzip(self):
        root = take_io.read_root(FIXTURE)
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(root, f)
        try:
            self.assertEqual(take_io.load(f.name).channels, self.take.channels)
        finally:
            os.remove(f.name)

    def test_rejects_v1_with_guidance(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"meta": {"take": 1}, "samples": []}, f)
        try:
            with self.assertRaises(take_io.TakeError) as cm:
                take_io.load(f.name)
            self.assertIn("Export", str(cm.exception))
        finally:
            os.remove(f.name)

    def test_validate_catches_corruption(self):
        root = take_io.read_root(FIXTURE)
        root["channels"]["wheels.grounded"][2][5] = 2
        root["channels"]["vel"][0].append(0.0)
        errs = take_io.validate(root)
        self.assertTrue(any("grounded" in e for e in errs), errs)
        self.assertTrue(any("vel" in e for e in errs), errs)

    def test_numpy_optional(self):
        try:
            import numpy  # noqa: F401
        except ImportError:
            self.skipTest("numpy not installed — optional")
        arrs = self.take.as_numpy()
        self.assertEqual(arrs["wheels.contact_p"].shape, (4, 3, 400))
        self.assertEqual(arrs["chassis.q"].shape, (4, 400))

    def test_old_take_has_no_camera_set(self):
        """The fixture predates per-camera recording: optional channels simply absent."""
        self.assertEqual(self.take.camera_names, [])
        self.assertNotIn("cams.p", self.take)


if __name__ == "__main__":
    unittest.main()

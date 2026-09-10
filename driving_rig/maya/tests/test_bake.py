"""Tests for the pure-Python importer core (mathutil, bake). No Maya needed.

    mayapy -m unittest discover -s maya/tests -v
"""
import copy
import math
import os
import random
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from driving_rig import bake, mathutil as mu, take_io  # noqa: E402

FIXTURE = os.path.join(HERE, "fixture_take.json.gz")


def q_axis(axis, ang):
    s = math.sin(ang / 2)
    return (axis[0] * s, axis[1] * s, axis[2] * s, math.cos(ang / 2))


def q_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def mat_err(a, b):
    return max(abs(a[r][c] - b[r][c]) for r in range(3) for c in range(3))


class EulerZXY(unittest.TestCase):
    def test_reconstructs_random_rotations(self):
        rnd = random.Random(7)
        for _ in range(2000):
            q = mu.q_norm(tuple(rnd.uniform(-1, 1) for _ in range(4)))
            e = mu.matrix_to_euler_zxy(mu.q_to_matrix(q))
            self.assertLess(mat_err(mu.q_to_matrix(q), mu.euler_zxy_to_matrix(e)), 1e-9)

    def test_order_is_y_outermost(self):
        """zxy: pure heading must land entirely in ry, pure pitch in rx, pure roll in rz."""
        self.assertAlmostEqual(mu.matrix_to_euler_zxy(mu.q_to_matrix(q_axis((0, 1, 0), 1.2)))[1], 1.2)
        self.assertAlmostEqual(mu.matrix_to_euler_zxy(mu.q_to_matrix(q_axis((1, 0, 0), 0.4)))[0], 0.4)
        self.assertAlmostEqual(mu.matrix_to_euler_zxy(mu.q_to_matrix(q_axis((0, 0, 1), -0.3)))[2], -0.3)

    def _check_sequence(self, quats, max_step_deg):
        eul = mu.quats_to_euler_zxy(quats)
        for q, e in zip(quats, eul):
            self.assertLess(mat_err(mu.q_to_matrix(q), mu.euler_zxy_to_matrix(e)), 1e-9)
        steps = [max(abs(math.degrees(a[k] - b[k])) for k in range(3)) for a, b in zip(eul[1:], eul)]
        self.assertLess(max(steps), max_step_deg, "Euler flip: max per-frame step %.1f°" % max(steps))
        return eul

    def test_donuts_heading_unrolls(self):
        """Three full turns of heading with some roll: heading accumulates to ~1080°, no flips."""
        quats = [q_mul(q_axis((0, 1, 0), 3 * mu.TAU * i / 300), q_axis((0, 0, 1), 0.1)) for i in range(301)]
        eul = self._check_sequence(quats, 5.0)
        self.assertAlmostEqual(math.degrees(eul[-1][1] - eul[0][1]), 1080.0, delta=0.5)

    def test_no_flips_through_90_pitch(self):
        """Spec 3.2: a loop — pitch through +90°, over the top, back through −90° — while
        heading 40° off-axis and slightly rolled. Continuous curves, exact rotations."""
        base = q_mul(q_axis((0, 1, 0), math.radians(40)), q_axis((0, 0, 1), 0.05))
        quats = [q_mul(base, q_axis((1, 0, 0), mu.TAU * i / 720)) for i in range(721)]
        self._check_sequence(quats, 12.0)

    def test_loop_exactly_through_singularity(self):
        """Pure pitch loop, no roll: passes exactly through rx = ±90° (the degenerate branch).
        Pitch should simply run 0 → 360° in even steps."""
        base = q_axis((0, 1, 0), math.radians(40))
        quats = [q_mul(base, q_axis((1, 0, 0), mu.TAU * i / 720)) for i in range(721)]
        eul = self._check_sequence(quats, 0.6)
        self.assertAlmostEqual(math.degrees(eul[-1][0] - eul[0][0]), 360.0, delta=0.01)

    def test_hemisphere_flip_in_input_is_harmless(self):
        q = q_axis((0, 1, 0), 0.5)
        eul = mu.quats_to_euler_zxy([q, tuple(-c for c in q), q])
        self.assertAlmostEqual(eul[0][1], eul[1][1])


class Resampling(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.take = take_io.load(FIXTURE)

    def test_exact_on_tick_times(self):
        t = self.take
        rs = bake.Resampler(t, [0.0, 10 / 240.0])
        x = t["chassis.p"][0]
        self.assertEqual(rs.lin(x), [x[t.in_index], x[t.in_index + 10]])

    def test_step_holds_last_tick(self):
        t = self.take
        rs = bake.Resampler(t, [(0.5) / 240.0])
        s = [0] * t.n
        s[t.in_index + 1] = 1
        self.assertEqual(rs.step(s), [0])

    def test_slerp_midpoint(self):
        a, b = q_axis((0, 1, 0), 0.0), q_axis((0, 1, 0), 0.2)
        m = mu.q_slerp(a, b, 0.5)
        self.assertAlmostEqual(mu.matrix_to_euler_zxy(mu.q_to_matrix(m))[1], 0.1)


class BakeFixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.take = take_io.load(FIXTURE)
        cls.b = bake.bake(cls.take, fps=24, in_frame=1001)

    def test_frames_and_handles(self):
        b = self.b
        self.assertIn(1001, b.frames)
        self.assertEqual(b.frames[0], 1001 - 8)
        self.assertEqual(len(b.frames), len(b.chassis_t[0]))

    def test_chassis_at_in_frame_is_take_sample(self):
        i = self.b.frames.index(1001)
        for k in range(3):
            self.assertAlmostEqual(self.b.chassis_t[k][i], self.take["chassis.p"][k][self.take.in_index] * 100.0, places=6)

    def test_chassis_rotation_matches_take(self):
        rs = bake.Resampler(self.take, self.b.times)
        quats = rs.quat(*self.take["chassis.q"])
        for i, q in enumerate(quats):
            e = tuple(self.b.chassis_r[k][i] for k in range(3))
            self.assertLess(mat_err(mu.q_to_matrix(q), mu.euler_zxy_to_matrix(e)), 1e-9)

    def test_spin_solve_matches_recorded(self):
        for w, r in self.b.spin_report.items():
            self.assertLess(r["max_drift_deg"], 1.0, "%s drifted %.2f°" % (w, r["max_drift_deg"]))
            self.assertLess(abs(r["radius_error_percent"]), bake.RADIUS_WARN_PERCENT, w)
        self.assertEqual(self.b.radius_warn, [])

    def test_spin_sign_forward_roll(self):
        """Car drives forward (−Z): spin_cumulative increases, so rotateX (= −spin) decreases."""
        rx = self.b.wheels["FL"]["spin_rx"]
        self.assertLess(rx[-1], rx[0])

    def test_check_catches_wrong_radius(self):
        take = copy.copy(self.take)
        take.meta = dict(self.take.meta, wheel_radius=0.36)   # true radius is 0.34
        b = bake.bake(take, fps=24)
        self.assertEqual(sorted(b.radius_warn), sorted(take_io.WHEELS))
        self.assertAlmostEqual(b.spin_report["FL"]["radius_effective"], 0.34, delta=0.003)

    def test_retime_whole_rig_shifts_spin(self):
        """Spec 3.3: retime everything 8 frames later → re-solved spin is the same curve, 8 frames later."""
        w = self.b.wheels["RL"]
        c, sd = w["centers_cm"], w["slip_distance"]
        fw = [(0, 0, -1)] * len(c)   # straight-ish run; forward only needs to be consistent
        a = bake.solve_spin(c, fw, sd, 0.0, 34.0)
        shifted = bake.solve_spin([c[0]] * 8 + c, fw[:1] * 8 + fw, [sd[0]] * 8 + sd, 0.0, 34.0)
        for i in range(len(a)):
            self.assertAlmostEqual(shifted[i + 8], a[i], places=9)

    def test_offset_chassis_changes_spin_by_travel(self):
        """Animator pushes the car 1 m further along forward over the take → wheels roll
        exactly 1 m / r more."""
        w = self.b.wheels["FR"]
        c, sd = w["centers_cm"], w["slip_distance"]
        n = len(c)
        fw = [(0, 0, -1)] * n
        a = bake.solve_spin(c, fw, sd, 0.0, 34.0)
        pushed = [(p[0], p[1], p[2] - 100.0 * i / (n - 1)) for i, p in enumerate(c)]
        b = bake.solve_spin(pushed, fw, sd, 0.0, 34.0)
        self.assertAlmostEqual(b[-1] - a[-1], 100.0 / 34.0, places=6)

    def test_camera_focal(self):
        self.assertAlmostEqual(mu.vfov_to_focal_mm(60.0, 0.945), 0.945 * 25.4 / 2 / math.tan(math.radians(30)))
        self.assertIsNotNone(self.b.camera)
        self.assertEqual(len(self.b.camera["focal"]), len(self.b.frames))

    def test_other_rates(self):
        for fps in (23.976, 25, 30, 48, 60):
            b = bake.bake(self.take, fps=fps)
            self.assertIn(1001, b.frames)
            for w, r in b.spin_report.items():
                self.assertLess(r["max_drift_deg"], 1.0, "%s @ %s fps" % (w, fps))


if __name__ == "__main__":
    unittest.main()

"""Maya-side tests. Need mayapy (headless Maya); skipped under plain Python.

    "C:\\Program Files\\Autodesk\\Maya2026\\bin\\mayapy.exe" -m unittest discover -s maya/tests -v

These are the spec's Phase 3 acceptance tests, measured inside real Maya:
  3.1  rig builds from meta at the right proportions, clean hierarchy
  3.2  chassis in Maya == the take (world matrix vs quaternion: proves the zxy convention);
       keys are one-per-frame; scene units don't matter
  3.3  re-solve reproduces the import; retiming the whole rig 8 frames keeps spin correct;
       a root offset doesn't change the spin
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

try:
    import maya.standalone
    HAVE_MAYA = True
except ImportError:
    HAVE_MAYA = False

from driving_rig import bake, mathutil as mu, take_io  # noqa: E402

FIXTURE = os.path.join(HERE, "fixture_take.json.gz")
SCENE = os.path.join(HERE, "fixture_scene")
_started = []


def setUpModule():
    if HAVE_MAYA:
        maya.standalone.initialize(name="python")
        _started.append(True)


def tearDownModule():
    if _started:
        try:
            maya.standalone.uninitialize()
        except Exception:
            pass


def maya_rot(m16):
    """Maya worldMatrix (row vectors) → column-vector 3×3 rotation, normalised (drop scale)."""
    cols = [(m16[0], m16[1], m16[2]), (m16[4], m16[5], m16[6]), (m16[8], m16[9], m16[10])]
    cols = [mu.v_norm(c) for c in cols]
    return tuple(tuple(cols[c][r] for c in range(3)) for r in range(3))


def q_axis(axis, ang):
    ax = mu.v_norm(axis)
    s = math.sin(ang / 2)
    return (ax[0] * s, ax[1] * s, ax[2] * s, math.cos(ang / 2))


def q_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def write_tumbling_take(path):
    """The fixture with its chassis rotation replaced by large simultaneous rotations —
    1.5 turns of heading, ±35° pitch, ±25° roll, plus a tilted-axis offset — so a rotate
    order or axis-convention mistake can't hide in small angles."""
    root = take_io.read_root(FIXTURE)
    n = root["meta"]["n"]
    q = [[], [], [], []]
    prev = None
    for i in range(n):
        u = i / float(n - 1)
        r = q_mul(q_axis((0, 1, 0), 3 * math.pi * u), q_axis((1, 0, 0), math.radians(35) * math.sin(5 * u)))
        r = q_mul(r, q_axis((0, 0, 1), math.radians(25) * math.sin(7 * u + 1)))
        r = q_mul(r, q_axis((1, 1, 0), 0.3))
        if prev and sum(a * b for a, b in zip(r, prev)) < 0:
            r = tuple(-c for c in r)
        prev = r
        for k in range(4):
            q[k].append(round(r[k], 6))
    root["channels"]["chassis.q"] = q
    with gzip.open(path, "wt") as f:
        json.dump(root, f)
    return take_io.load(path)


def _string_constants(src):
    import ast
    return [n.value for n in ast.walk(ast.parse(src)) if isinstance(n, ast.Constant) and isinstance(n.value, str)]


def mat_err(a, b):
    return max(abs(a[r][c] - b[r][c]) for r in range(3) for c in range(3))


@unittest.skipUnless(HAVE_MAYA, "needs mayapy (Maya's Python)")
class MayaImport(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from maya import cmds
        from driving_rig import importer
        cls.cmds = cmds
        cls.importer = importer
        cls.take = take_io.load(FIXTURE)
        cls.bk = bake.bake(cls.take, fps=24.0, in_frame=1001)

    def setUp(self):
        self.cmds.file(new=True, force=True)
        self.cmds.upAxis(axis="y", rotateView=False)
        self.cmds.currentUnit(linear="cm", angle="deg", time="film")

    def _import(self, **kw):
        kw.setdefault("verbose", False)
        return self.importer.import_take(FIXTURE, fps=24, in_frame=1001, **kw)

    def _ns(self, root):
        return root.split("|")[-1].rsplit(":", 1)[0]

    # --- 3.1 ---------------------------------------------------------------

    def test_hierarchy_and_proportions(self):
        c = self.cmds
        root = self._import()
        ns = self._ns(root)
        self.assertEqual(ns, "drv_fixture_take")
        self.assertEqual(c.getAttr(ns + ":chassis.rotateOrder"), mu.ROTATE_ORDER_ZXY)
        for w in take_io.WHEELS:
            chain = ["chassis", "wheel_%s_steer" % w, "wheel_%s_susp" % w, "wheel_%s_spin" % w, "wheel_%s_geo" % w]
            for parent, child in zip(chain, chain[1:]):
                self.assertEqual(c.listRelatives("%s:%s" % (ns, child), parent=True)[0], "%s:%s" % (ns, parent))
            self.assertTrue(c.objExists("%s:contact_%s" % (ns, w)))
        bb = c.exactWorldBoundingBox(ns + ":wheel_FL_geo", calculateExactly=True)
        radius_cm = self.take.meta["wheel_radius"] * 100.0
        self.assertAlmostEqual((bb[4] - bb[1]) / 2.0, radius_cm, delta=radius_cm * 0.02)
        self.assertTrue(c.objExists(ns + ":take_cam"))

    # --- 3.2 ---------------------------------------------------------------

    def test_chassis_matches_take(self):
        """World matrix in Maya vs the take's quaternion at IN: proves the zxy mapping."""
        c = self.cmds
        root = self._import()
        ns = self._ns(root)
        worst_r = worst_t = 0.0
        for fr in (993, 1001, 1010, 1025, 1032):
            i = self.bk.frames.index(fr)
            j = self.take.in_index + (fr - 1001) * 10          # 240 / 24 = 10 ticks per frame
            m = c.getAttr(ns + ":chassis.worldMatrix[0]", time=fr)
            q = tuple(self.take["chassis.q"][k][j] for k in range(4))
            worst_r = max(worst_r, mat_err(maya_rot(m), mu.q_to_matrix(q)))
            p = tuple(self.take["chassis.p"][k][j] * 100.0 for k in range(3))
            worst_t = max(worst_t, mu.v_len(mu.v_sub((m[12], m[13], m[14]), p)))
            self.assertEqual(i, fr - self.bk.frames[0])
        self.assertLess(worst_r, 1e-5)
        self.assertLess(worst_t, 1e-3)

    def test_large_rotations_every_frame(self):
        """Convention proof: big rotations in all three axes, compared at every frame."""
        c = self.cmds
        path = os.path.join(tempfile.mkdtemp(), "tumble.json.gz")
        take = write_tumbling_take(path)
        root = self.importer.import_take(path, fps=24, in_frame=1001, verbose=False, camera=False)
        ns = self._ns(root)
        b = bake.bake(take, fps=24, in_frame=1001)
        worst = 0.0
        for i, fr in enumerate(b.frames):
            j = take.in_index + int(round((fr - 1001) * 10))
            m = c.getAttr(ns + ":chassis.worldMatrix[0]", time=fr)
            q = tuple(take["chassis.q"][k][j] for k in range(4))
            worst = max(worst, mat_err(maya_rot(m), mu.q_to_matrix(mu.q_norm(q))))
        self.assertLess(worst, 1e-4, "chassis rotation in Maya differs from the take by %.2e" % worst)
        ry = [c.getAttr(ns + ":chassis.rotateY", time=fr) for fr in b.frames]
        self.assertGreater(max(ry) - min(ry), 400.0)      # heading unrolled past a full turn
        steps = [abs(a - b_) for a, b_ in zip(ry[1:], ry)]
        self.assertLess(max(steps), 30.0)                 # no 180° / 360° flips

    def test_wheel_chain_positions(self):
        c = self.cmds
        root = self._import()
        ns = self._ns(root)
        for w in take_io.WHEELS:
            for fr in (1001, 1030):
                m = c.getAttr("%s:wheel_%s_susp.worldMatrix[0]" % (ns, w), time=fr)
                want = self.bk.wheels[w]["centers_cm"][self.bk.frames.index(fr)]
                self.assertLess(mu.v_len(mu.v_sub((m[12], m[13], m[14]), want)), 1e-3, "%s @%d" % (w, fr))

    def test_one_key_per_frame(self):
        c = self.cmds
        root = self._import()
        ns = self._ns(root)
        times = c.keyframe(ns + ":chassis.translateX", query=True, timeChange=True)
        self.assertEqual(len(times), len(self.bk.frames))
        self.assertEqual((times[0], times[-1]), (self.bk.frames[0], self.bk.frames[-1]))
        self.assertEqual(c.playbackOptions(query=True, minTime=True), self.bk.frames[0])

    def test_spin_values(self):
        c = self.cmds
        root = self._import()
        ns = self._ns(root)
        for fr in (1001, 1015, 1030):
            got = c.getAttr(ns + ":wheel_RR_spin.rotateX", time=fr)
            want = math.degrees(self.bk.wheels["RR"]["spin_rx"][self.bk.frames.index(fr)])
            self.assertAlmostEqual(got, want, places=3)

    def test_scene_in_metres(self):
        """UI units must not matter: same car, and the user's units are restored."""
        c = self.cmds
        c.currentUnit(linear="m")
        root = self._import()
        self.assertEqual(c.currentUnit(query=True, linear=True), "m")
        c.currentUnit(linear="cm")
        ns = self._ns(root)
        m = c.getAttr(ns + ":chassis.worldMatrix[0]", time=1001)
        want = tuple(self.take["chassis.p"][k][self.take.in_index] * 100.0 for k in range(3))
        self.assertLess(mu.v_len(mu.v_sub((m[12], m[13], m[14]), want)), 1e-3)
        # static offsets (hardpoints, suspension rest) and geometry size are where UI units bite
        for w in take_io.WHEELS:
            ms = c.getAttr("%s:wheel_%s_susp.worldMatrix[0]" % (ns, w), time=1001)
            want = self.bk.wheels[w]["centers_cm"][self.bk.frames.index(1001)]
            self.assertLess(mu.v_len(mu.v_sub((ms[12], ms[13], ms[14]), want)), 1e-3, w)
        bb = c.exactWorldBoundingBox(ns + ":wheel_FL_geo", calculateExactly=True)
        self.assertAlmostEqual((bb[4] - bb[1]) / 2.0, self.take.meta["wheel_radius"] * 100.0, delta=1.0)

    def test_other_frame_rate(self):
        c = self.cmds
        root = self.importer.import_take(FIXTURE, fps=30, in_frame=1001, verbose=False)
        self.assertEqual(c.currentUnit(query=True, time=True), "ntsc")
        n = len(c.keyframe(self._ns(root) + ":chassis.translateX", query=True, timeChange=True))
        self.assertEqual(n, len(bake.bake(self.take, fps=30).frames))

    def test_camera_focal(self):
        c = self.cmds
        root = self._import()
        f = c.getAttr(self._ns(root) + ":take_camShape.focalLength", time=1001)
        self.assertAlmostEqual(f, self.bk.camera["focal"][self.bk.frames.index(1001)], places=3)

    def test_z_up_scene(self):
        c = self.cmds
        c.upAxis(axis="z", rotateView=False)
        root = self._import()
        m = c.getAttr(self._ns(root) + ":chassis.worldMatrix[0]", time=1001)
        x, y, z = (self.take["chassis.p"][k][self.take.in_index] * 100.0 for k in range(3))
        self.assertLess(mu.v_len(mu.v_sub((m[12], m[13], m[14]), (x, -z, y))), 1e-3)

    # --- 3.3 ---------------------------------------------------------------

    def _spin_curve(self, ns, w, frames):
        return [self.cmds.getAttr("%s:wheel_%s_spin.rotateX" % (ns, w), time=f) for f in frames]

    def test_resolve_reproduces_import(self):
        """Scene-sampled re-solve (world matrices) == the import-time solve (pure Python)."""
        root = self._import()
        ns = self._ns(root)
        frames = self.bk.frames
        before = {w: self._spin_curve(ns, w, frames) for w in take_io.WHEELS}
        reps = self.importer.resolve_spin(root, verbose=False)
        for w in take_io.WHEELS:
            after = self._spin_curve(ns, w, frames)
            self.assertLess(max(abs(a - b) for a, b in zip(before[w], after)), 0.01, w)
            self.assertLess(abs(reps[w]["radius_error_percent"]), bake.RADIUS_WARN_PERCENT, w)

    def test_retime_8_frames(self):
        """Spec 3.3: move the whole take 8 frames later, re-solve → spin is the same curve, later."""
        c = self.cmds
        root = self._import()
        ns = self._ns(root)
        frames = self.bk.frames
        before = {w: self._spin_curve(ns, w, frames) for w in take_io.WHEELS}
        c.keyframe(c.ls(ns + ":*", type="animCurve"), edit=True, relative=True, timeChange=8)
        self.importer.resolve_spin(root, verbose=False)
        for w in take_io.WHEELS:
            after = self._spin_curve(ns, w, [f + 8 for f in frames])
            self.assertLess(max(abs(a - b) for a, b in zip(before[w], after)), 0.01, w)

    def test_root_offset_keeps_spin(self):
        c = self.cmds
        root = self._import()
        ns = self._ns(root)
        frames = self.bk.frames
        before = self._spin_curve(ns, "FL", frames)
        c.setAttr(root + ".translate", 250.0, 0.0, -1000.0)
        c.setAttr(root + ".rotateY", 30.0)
        reps = self.importer.resolve_spin(root, verbose=False)
        after = self._spin_curve(ns, "FL", frames)
        self.assertLess(max(abs(a - b) for a, b in zip(before, after)), 0.01)
        self.assertLess(abs(reps["FL"]["radius_error_percent"]), bake.RADIUS_WARN_PERCENT)

    def test_check_accepts_scaled_rig(self):
        """Scaling the whole rig scales the wheels with it — the check must not complain."""
        c = self.cmds
        root = self._import()
        c.setAttr(root + ".scale", 2.0, 2.0, 2.0)
        reps = self.importer.check_spin(root, verbose=False)
        self.assertLess(abs(reps["RL"]["radius_error_percent"]), bake.RADIUS_WARN_PERCENT)

    # --- scene geometry ------------------------------------------------------

    def _scene(self, **kw):
        kw.setdefault("verbose", False)
        return self.importer.import_scene(SCENE, **kw)

    def _vtx(self, node, i):
        return tuple(self.cmds.pointPosition("%s.vtx[%d]" % (node, i), world=True))

    def test_scene_vertices_in_take_space(self):
        from driving_rig import scene_io
        c = self.cmds
        grp = self._scene()
        ns = self._ns(grp)
        sc = scene_io.load(SCENE)
        for name in ("Ground", "Ramp", "SpeedBump1"):
            obj = sc[name]
            for i in (0, len(obj.points) // 2, len(obj.points) - 1):
                self.assertLess(mu.v_len(mu.v_sub(self._vtx("%s:%s" % (ns, name), i), obj.points[i])), 1e-3, name)
        self.assertEqual(c.getAttr(ns + ":Mark0.drvCollides"), False)
        self.assertEqual(c.getAttr(ns + ":Ground.drvCollides"), True)

    def test_scene_faces_point_up(self):
        """Winding survives into Maya: the ground's faces face the sky."""
        import maya.api.OpenMaya as om
        grp = self._scene()
        sel = om.MSelectionList()
        sel.add(self._ns(grp) + ":Ground")
        fn = om.MFnMesh(sel.getDagPath(0))
        for f in (0, 100, fn.numPolygons - 1):
            self.assertGreater(fn.getPolygonNormal(f, om.MSpace.kWorld).y, 0.99)

    def test_scene_in_metres_and_z_up(self):
        from driving_rig import scene_io
        c = self.cmds
        p = scene_io.load(SCENE)["Ramp"].points[3]
        c.currentUnit(linear="m")
        grp = self._scene()
        self.assertEqual(c.currentUnit(query=True, linear=True), "m")
        c.currentUnit(linear="cm")
        self.assertLess(mu.v_len(mu.v_sub(self._vtx(self._ns(grp) + ":Ramp", 3), p)), 1e-3)
        c.file(new=True, force=True)
        c.upAxis(axis="z", rotateView=False)
        grp = self._scene()
        self.assertLess(mu.v_len(mu.v_sub(self._vtx(self._ns(grp) + ":Ramp", 3), (p[0], -p[2], p[1]))), 1e-3)

    def test_wheels_touch_the_imported_ground(self):
        """End to end in Maya: take rig + scene geo. Each contact locator sits on the ground
        mesh, and each wheel's bottom is one radius below its centre, on that same surface."""
        import maya.api.OpenMaya as om
        c = self.cmds
        grp = self._scene()
        root = self._import()
        sel = om.MSelectionList()
        sel.add(self._ns(grp) + ":Ground")
        ground = om.MFnMesh(sel.getDagPath(0))
        ns = self._ns(root)
        r = self.take.meta["wheel_radius"] * 100.0
        worst_c = worst_w = 0.0
        for fr in (1001, 1010, 1020):
            for w in take_io.WHEELS:
                if not c.getAttr("%s:contact_%s.grounded" % (ns, w), time=fr):
                    continue
                m = c.getAttr("%s:contact_%s.worldMatrix[0]" % (ns, w), time=fr)
                p = om.MPoint(m[12], m[13], m[14])
                q = ground.getClosestPoint(p, om.MSpace.kWorld)[0]
                worst_c = max(worst_c, abs(p.y - q.y))
                ms = c.getAttr("%s:wheel_%s_susp.worldMatrix[0]" % (ns, w), time=fr)
                worst_w = max(worst_w, abs((ms[13] - r) - q.y))
        self.assertLess(worst_c, 0.01)   # 0.1 mm
        self.assertLess(worst_w, 0.5)    # wheel bottom on the ground within 5 mm (sphere contact ahead/behind)

    def test_ground_mismatch_is_reported(self):
        c = self.cmds
        self._scene()                    # fixture scene: 80 m pad; fixture take: 800 m terrain
        root = self._import()
        self.assertIn("Ground mismatch", c.getAttr(root + ".drvLastCheck"))
        c.file(new=True, force=True)
        grp = self._scene()
        c.setAttr(grp + ".drvCollisionSource", self.take.meta["collision_source"], type="string")
        root = self._import()
        self.assertNotIn("Ground mismatch", c.getAttr(root + ".drvLastCheck"))

    def test_delete_scene(self):
        c = self.cmds
        grp = self._scene()
        ns = self._ns(grp)
        c.select(ns + ":Ramp")
        self.assertTrue(self.importer.delete_rig())
        self.assertFalse(c.namespace(exists=":" + ns))

    # --- housekeeping ------------------------------------------------------

    def test_curves_live_in_namespace_and_delete_cleans_up(self):
        c = self.cmds
        root = self._import()
        ns = self._ns(root)
        self.assertGreater(len(c.ls(ns + ":*", type="animCurve")), 50)
        self.assertEqual([x for x in c.ls(type="animCurve") if ":" not in x], [])
        self.assertTrue(self.importer.delete_rig(root))
        self.assertFalse(c.namespace(exists=":" + ns))
        self.assertEqual(c.ls(type="animCurve"), [])

    def test_install_block_roundtrip(self):
        """install() twice + uninstall() must leave an existing userSetup.py byte-identical —
        including non-ASCII content, and with a non-ASCII install path. (Regression: on
        Windows the locale default cp1252 couldn't encode the block and the file was
        truncated.)"""
        from driving_rig import menu
        path = os.path.join(tempfile.mkdtemp(), "userSetup.py")
        original = u"import os\n# Kommentar: Stra\u00dfe, caf\u00e9 \u25b8 \u2014 \u6f22\nprint('my studio setup')\n".encode("utf-8")
        with open(path, "wb") as f:
            f.write(original)
        real = menu._user_setup_path
        menu._user_setup_path = lambda: path
        try:
            pkg = u"C:\\Users\\Chris M\u00fcller\\Documents\\driving_rig\\maya"
            menu.install(pkg)
            menu.install(pkg)
            with open(path, "rb") as f:
                data = f.read()
            self.assertTrue(data.startswith(original))
            text = data.decode("utf-8")            # Maya reads userSetup.py as UTF-8
            self.assertEqual(text.count(menu.BEGIN), 1)
            compile(text, path, "exec")                              # Maya can run it
            self.assertIn(pkg, _string_constants(text))              # path survives exactly
            menu.uninstall()
            with open(path, "rb") as f:
                self.assertEqual(f.read(), original)
            self.assertFalse(os.path.exists(path + ".driving_rig.tmp"))
        finally:
            menu._user_setup_path = real

    def test_second_import_gets_own_namespace(self):
        a = self._import()
        b = self._import()
        self.assertNotEqual(self._ns(a), self._ns(b))
        self.assertEqual(len(self.importer.list_rigs()), 2)


if __name__ == "__main__":
    unittest.main()

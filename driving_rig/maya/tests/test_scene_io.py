"""Scene-export contract tests — plain Python or mayapy, no Maya scene needed.

fixture_scene/ was written by the Godot project (SceneGeoExporter) from an 80 m terrain
with the standard props, so these check Godot's writer and this reader agree.
"""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from driving_rig import scene_io, take_io  # noqa: E402

FIXTURE = os.path.join(HERE, "fixture_scene")
TAKE = os.path.join(HERE, "fixture_take.json.gz")


class SceneIo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scene = scene_io.load(FIXTURE)

    def test_manifest(self):
        m = self.scene.manifest
        self.assertEqual((m["units"], m["up_axis"], m["winding"], m["space"]), ("cm", "Y", "ccw", "world"))
        self.assertEqual([o.name for o in self.scene.objects],
                         ["Ground", "SpeedBump0", "SpeedBump1", "SpeedBump2", "Ramp", "Mark0", "Mark1"])

    def test_accepts_folder_manifest_or_obj(self):
        for p in (FIXTURE, os.path.join(FIXTURE, "scene.json"), os.path.join(FIXTURE, "Ground.obj")):
            self.assertEqual(len(scene_io.load(p).objects), 7)

    def test_every_face_front_facing(self):
        """Godot winds front faces clockwise; the export must flip them for Maya."""
        for o in self.scene.objects:
            self.assertEqual(scene_io.winding_agreement(o), 1.0, o.name)

    def test_ground_is_the_80m_pad_in_cm(self):
        g = self.scene["Ground"]
        lo, hi = g.bounds()
        self.assertEqual((lo[0], lo[2], hi[0], hi[2]), (-4000.0, -4000.0, 4000.0, 4000.0))
        self.assertEqual((lo[1], hi[1]), (0.0, 0.0))           # inside the 150 m flat radius

    def test_props_transforms_baked(self):
        """Speed bump: 8 cm tall, centred on z = -30 m. Ramp: rotated 90 deg, rises toward -Z
        to 1.4 m at z = -34.5 m, low edge at z = -25.5 m — a wrong transform can't pass this."""
        b = self.scene["SpeedBump0"]
        lo, hi = b.bounds()
        self.assertAlmostEqual(hi[1], 8.0, places=3)
        self.assertAlmostEqual((lo[2] + hi[2]) / 2.0, -3000.0, places=2)
        r = self.scene["Ramp"]
        top = max(r.points, key=lambda p: p[1])
        self.assertAlmostEqual(top[1], 140.0, places=3)
        self.assertAlmostEqual(top[2], -3450.0, places=2)
        lo, hi = r.bounds()
        self.assertAlmostEqual(hi[2], -2550.0, places=2)
        self.assertAlmostEqual(lo[0] + hi[0], 2 * 1800.0, places=2)

    def test_take_contacts_sit_on_surfaces(self):
        """The fixture take was driven over this pad and its speed bumps: every grounded
        contact lands on the exported surface. Flat ground exactly; on the bumps within
        0.6 mm, because this fixture take predates bumps colliding against their own render
        mesh (they used an analytic cylinder vs the exported 64-sided mesh)."""
        take = take_io.load(TAKE)
        surf = scene_io.Surface(self.scene.colliding())
        flat = bump = 0.0
        n_bump = 0
        for w in range(4):
            cp, g = take.wheel(w, "wheels.contact_p"), take.wheel(w, "wheels.grounded")
            for i in range(take.n):
                if g[i]:
                    h = surf.height_at(cp[0][i] * 100, cp[2][i] * 100)
                    self.assertIsNotNone(h)
                    e = abs(cp[1][i] * 100 - h)
                    if h > 0.01:
                        bump = max(bump, e)
                        n_bump += 1
                    else:
                        flat = max(flat, e)
        self.assertLess(flat, 0.001)    # 0.01 mm
        self.assertGreater(n_bump, 0)
        self.assertLess(bump, 0.07)     # 0.7 mm

    def test_paint_is_flagged_non_colliding(self):
        """Road marks have no collider: flagged so Maya/FX know wheels pass over them."""
        self.assertEqual({o.name: o.collides for o in self.scene.objects},
                         {"Ground": True, "SpeedBump0": True, "SpeedBump1": True, "SpeedBump2": True,
                          "Ramp": True, "Mark0": False, "Mark1": False})
        lo, hi = self.scene["Mark0"].bounds()
        self.assertAlmostEqual(hi[1] - lo[1], 0.2, places=3)   # 2 mm of paint

    def test_ground_mismatch_detected(self):
        """The fixture ground is 80 m; the fixture take was driven on the 800 m one."""
        self.assertFalse(scene_io.same_ground(take_io.load(TAKE).meta, self.scene))
        self.assertTrue(scene_io.same_ground({"collision_source": self.scene.collision_source}, self.scene))

    def test_validate_catches_truncated_obj(self):
        s = scene_io.load(FIXTURE)
        s.objects[0].faces.pop()
        self.assertTrue(any("triangles" in e for e in scene_io.validate(s)))


if __name__ == "__main__":
    unittest.main()

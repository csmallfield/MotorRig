"""Full car models (carmodel): glTF reading, the Arnold build, and one-click load onto a take.

    "C:\\Program Files\\Autodesk\\Maya2027\\bin\\mayapy.exe" -m unittest discover -s maya/tests -v

The fixture car is a small .glb written here from the fixture take's own numbers - the same
contract the game's models follow (chassis at ride height, wheel chains, steering column) - so
its wheels must land exactly on the bind car's. It has a caliper on wheel_FL_susp, a mesh used
by two nodes, two nodes with the same name, and textured / glass / decal materials.
"""
import json
import math
import os
import shutil
import struct
import sys
import tempfile
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

try:
    import maya.standalone
    HAVE_MAYA = True
except ImportError:
    HAVE_MAYA = False

from driving_rig import bake, mathutil as mu, take_io  # noqa: E402

CAMS = os.path.join(HERE, "fixture_take_cams.json.gz")   # has steering params
BUS = os.path.join(os.path.dirname(os.path.dirname(HERE)), "models", "vehicles", "city_bus",
                   "LINEA12_city_bus_v01.glb")


def setUpModule():
    if HAVE_MAYA:
        from maya import cmds
        try:
            cmds.about(version=True)
        except Exception:
            maya.standalone.initialize(name="python")   # test_maya uninitializes at the very end


# --- a tiny rig-shaped .glb ---------------------------------------------------------

def _png(rgba, w=2, h=2):
    raw = b"".join(b"\x00" + bytes(rgba) * w for _ in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


class _Writer(object):
    def __init__(self):
        self.bin = bytearray()
        self.j = {"asset": {"version": "2.0"}, "buffers": [], "bufferViews": [], "accessors": [],
                  "meshes": [], "materials": [], "nodes": [], "images": [], "textures": [],
                  "scenes": [{"nodes": [0]}], "scene": 0}

    def view(self, data):
        while len(self.bin) % 4:
            self.bin += b"\x00"
        self.j["bufferViews"].append({"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)})
        self.bin += data
        return len(self.j["bufferViews"]) - 1

    def acc(self, fmt, ctype, kind, rows):
        flat = [v for r in rows for v in (r if isinstance(r, (list, tuple)) else [r])]
        v = self.view(struct.pack("<%d%s" % (len(flat), fmt), *flat))
        a = {"bufferView": v, "componentType": ctype, "count": len(rows), "type": kind}
        if kind == "VEC3":
            a["min"] = [min(r[k] for r in rows) for k in range(3)]
            a["max"] = [max(r[k] for r in rows) for k in range(3)]
        self.j["accessors"].append(a)
        return len(self.j["accessors"]) - 1

    def box(self, sx, sy, sz, material):
        """Axis-aligned box centred on the origin, as one triangle primitive."""
        hx, hy, hz = sx / 2.0, sy / 2.0, sz / 2.0
        pos, nrm, uv, idx = [], [], [], []
        for axis in range(3):
            for sign in (-1.0, 1.0):
                n = [0.0, 0.0, 0.0]
                n[axis] = sign
                u, v = [(1, 2), (2, 0), (0, 1)][axis]
                b = len(pos)
                for cu, cv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    p = [0.0, 0.0, 0.0]
                    p[axis] = sign * (hx, hy, hz)[axis]
                    p[u] = cu * (hx, hy, hz)[u]
                    p[v] = cv * (hx, hy, hz)[v]
                    pos.append(p)
                    nrm.append(list(n))
                    uv.append([(cu + 1) / 2.0, (cv + 1) / 2.0])
                quad = [b, b + 1, b + 2, b, b + 2, b + 3]
                idx += quad if sign > 0 else [quad[0], quad[2], quad[1], quad[3], quad[5], quad[4]]
        prim = {"attributes": {"POSITION": self.acc("f", 5126, "VEC3", pos),
                               "NORMAL": self.acc("f", 5126, "VEC3", nrm),
                               "TEXCOORD_0": self.acc("f", 5126, "VEC2", uv)},
                "indices": self.acc("H", 5123, "SCALAR", idx), "material": material}
        self.j["meshes"].append({"primitives": [prim]})
        return len(self.j["meshes"]) - 1

    def image(self, rgba, name):
        self.j["images"].append({"bufferView": self.view(_png(rgba)), "mimeType": "image/png", "name": name})
        self.j["textures"].append({"source": len(self.j["images"]) - 1})
        return len(self.j["textures"]) - 1

    def node(self, name, parent=None, mesh=None, t=None, r=None):
        n = {"name": name}
        if mesh is not None:
            n["mesh"] = mesh
        if t:
            n["translation"] = list(t)
        if r:
            n["rotation"] = list(r)
        self.j["nodes"].append(n)
        i = len(self.j["nodes"]) - 1
        if parent is not None:
            self.j["nodes"][parent].setdefault("children", []).append(i)
        return i

    def save(self, path):
        self.j["buffers"] = [{"byteLength": len(self.bin)}]
        js = json.dumps(self.j).encode("utf-8")
        js += b" " * (-len(js) % 4)
        bn = bytes(self.bin) + b"\x00" * (-len(self.bin) % 4)
        with open(path, "wb") as fh:
            fh.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bn)))
            fh.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
            fh.write(struct.pack("<II", len(bn), 0x004E4942) + bn)


def write_car_glb(path, meta, relocated=False):
    """The fixture take's car as a model on the rig contract. Returns facts to check against.
    relocated: like the limo, the visible steering wheel sits 1 m behind the rig's column, under
    steering_visual_column > steering_visual_pivot, and the rig's own steering_wheel is empty."""
    w = _Writer()
    paint = w.image((200, 40, 40, 255), "paint")
    orm = w.image((255, 128, 64, 255), "orm")
    normal = w.image((128, 128, 255, 255), "normal")
    decal = w.image((255, 255, 255, 128), "decal")
    w.j["materials"] = [
        {"name": "Paint", "pbrMetallicRoughness": {"baseColorTexture": {"index": paint},
                                                   "baseColorFactor": [0.5, 0.5, 0.5, 1.0],
                                                   "metallicRoughnessTexture": {"index": orm},
                                                   "metallicFactor": 1.0, "roughnessFactor": 0.8},
         "normalTexture": {"index": normal, "scale": 0.7},
         "extensions": {"KHR_materials_clearcoat": {"clearcoatFactor": 0.3, "clearcoatRoughnessFactor": 0.1}}},
        {"name": "Glass", "alphaMode": "BLEND", "doubleSided": True,
         "pbrMetallicRoughness": {"baseColorFactor": [0.5, 0.75, 0.7, 0.1], "metallicFactor": 0.0,
                                  "roughnessFactor": 0.05}},
        {"name": "Decal", "alphaMode": "BLEND",
         "pbrMetallicRoughness": {"baseColorTexture": {"index": decal}}},
        {"name": "Lamp", "emissiveFactor": [1.0, 0.5, 0.0],
         "extensions": {"KHR_materials_emissive_strength": {"emissiveStrength": 4.0}}},
    ]
    ext = meta["body"]["extents"]
    r, width = float(meta["wheel_radius"]), float(meta["wheel_width"])
    rest = float(meta["susp_rest"])
    cf, cr = bake.static_compression(meta)
    bottoms = [meta["hardpoints"][i][1] - (rest - (cf if i < 2 else cr)) - r for i in range(4)]
    ride = -sum(bottoms) / 4.0
    root = w.node("root")
    chassis = w.node("chassis", root, t=(0.0, ride, 0.0))
    w.node("body_geo", chassis, w.box(ext[0], ext[1], ext[2], 0))
    w.node("glass_geo", chassis, w.box(ext[0] * 0.8, 0.01, ext[2] * 0.3, 1), t=(0.0, ext[1] * 0.5, 0.0))
    w.node("decal_geo", chassis, w.box(0.3, 0.2, 0.01, 2), t=(0.0, 0.0, -ext[2] * 0.5))
    mirror = w.box(0.1, 0.1, 0.1, 0)
    w.node("mirror", chassis, mirror, t=(-ext[0] * 0.55, 0.2, -0.5))          # one mesh, two nodes,
    w.node("mirror", chassis, mirror, t=(ext[0] * 0.55, 0.2, -0.5))           # and the same name
    w.node("lamp_geo", chassis, w.box(0.2, 0.1, 0.05, 3), t=(0.0, 0.0, -ext[2] * 0.5 - 0.03))
    tyre = w.box(width, 2 * r, 2 * r, 0)
    for i, wn in enumerate(take_io.WHEELS):
        hp = meta["hardpoints"][i]
        steer = w.node("wheel_%s_steer" % wn, chassis, t=hp)
        susp = w.node("wheel_%s_susp" % wn, steer, t=(0.0, -(rest - (cf if i < 2 else cr)), 0.0))
        spin = w.node("wheel_%s_spin" % wn, susp)
        w.node("wheel_%s_geo" % wn, spin, tyre)
        if wn == "FL":
            w.node("caliper_FL", susp, w.box(0.05, 0.1, 0.1, 0), t=(0.05, 0.0, 0.15))
    st = bake.steering_params(meta)
    tilt = math.radians(st["tilt_deg"])
    col = w.node("steering_column", chassis, t=[v / 100.0 for v in st["position_cm"]],
                 r=(-math.sin(tilt / 2), 0.0, 0.0, math.cos(tilt / 2)))
    sw = w.node("steering_wheel", col)
    rim = w.box(st["radius_cm"] / 50.0, st["radius_cm"] / 50.0, 0.03, 0)
    if relocated:
        w.node("steering_rim_geo", sw)                                    # an empty carrier
        vis = w.node("steering_visual_column", chassis,
                     t=[v / 100.0 + (1.0 if k == 2 else 0.0) for k, v in enumerate(st["position_cm"])],
                     r=(-math.sin(tilt / 2), 0.0, 0.0, math.cos(tilt / 2)))
        w.node("visual_rim", w.node("steering_visual_pivot", vis), rim, t=(0.0, 0.1, 0.0))
    else:
        w.node("steering_rim_geo", sw, rim)
    w.save(path)
    # unique mesh data, as the asset READMEs count it: 8 boxes (the mirror and tyre are instanced)
    return {"ride": ride, "tris": 12 * 8}


@unittest.skipUnless(HAVE_MAYA, "needs mayapy (Maya's Python)")
class CarModel(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from maya import cmds
        from driving_rig import carmodel, importer, bind
        cls.cmds, cls.carmodel, cls.importer, cls.bind = cmds, carmodel, importer, bind
        cls.tmp = tempfile.mkdtemp(prefix="drv_car_")
        cls.meta = take_io.load(CAMS).meta
        cls.glb = os.path.join(cls.tmp, "fixture_car.glb")
        cls.facts = write_car_glb(cls.glb, cls.meta)
        os.environ[carmodel.CACHE_ENV] = os.path.join(cls.tmp, "cache")

    @classmethod
    def tearDownClass(cls):
        os.environ.pop(cls.carmodel.CACHE_ENV, None)
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def setUp(self):
        self.cmds.file(new=True, force=True)
        self.cmds.upAxis(axis="y", rotateView=False)
        self.cmds.currentUnit(linear="cm", angle="deg", time="film")

    def _build(self, name="fixture_car"):
        out = self.carmodel.cache_dir(name)
        info = self.carmodel.build_scene(self.glb, out)
        return out, info

    # --- reading and sorting -----------------------------------------------------

    def test_part_of_nearest_chain_node_wins(self):
        p = self.carmodel.part_of
        self.assertEqual(p(["Tyre", "wheel_FL_geo", "wheel_FL_spin", "wheel_FL_susp", "chassis"]), "wheel_FL")
        self.assertEqual(p(["caliper", "wheel_RR_susp", "wheel_RR_steer", "chassis"]), "wheel_RR_susp")
        self.assertEqual(p(["knuckle", "wheel_FR_steer", "chassis"]), "wheel_FR_steer")
        self.assertEqual(p(["rim", "steering_wheel", "steering_column", "chassis"]), "steering_wheel")
        self.assertEqual(p(["rim", "steering_visual_pivot", "steering_visual_column", "chassis"]),
                         "steering_visual")                                          # the limo
        self.assertEqual(p(["wheel_FL__Brake__Caliper", "wheel_FL_susp"]), "wheel_FL_susp")  # sports car
        self.assertEqual(p(["seat", "body_geo", "chassis", "root"]), "chassis")

    def test_source_follows_the_profile(self):
        meta = {"car_profile": {"name": "City Bus", "path": "res://profiles/cars/city_bus.tres"},
                "car_params": {"chassis_scene": "res://models/vehicles/city_bus.glb"}}
        glb, name = self.carmodel.source_for_meta(meta)
        self.assertEqual(name, "city_bus")
        self.assertEqual(os.path.normcase(glb), os.path.normcase(os.path.abspath(BUS)))   # the profile's model, not the old proxy
        with self.assertRaises(self.carmodel.CarModelError):
            self.carmodel.source_for_meta({"car_profile": {"path": "user://profiles/cars/gone.tres"}})

    # --- the build ---------------------------------------------------------------

    def test_build_groups_meshes_and_units(self):
        c = self.cmds
        out, info = self._build()
        self.assertEqual(info["parts"], sorted(["chassis", "steering_wheel", "wheel_FL", "wheel_FR",
                                                "wheel_RL", "wheel_RR", "wheel_FL_susp"]))
        self.assertEqual(info["triangles"], self.facts["tris"])
        self.assertTrue(self.carmodel.is_fresh(self.glb, out))
        self.assertTrue(info["arnold"])
        # metres -> cm, at the file's own coordinates: the tyre's centre is the wheel centre
        bb = c.exactWorldBoundingBox("wheel_FL")
        hp = self.meta["hardpoints"][0]
        self.assertAlmostEqual((bb[0] + bb[3]) / 2.0, hp[0] * 100.0, places=3)
        self.assertAlmostEqual((bb[4] - bb[1]) / 2.0, self.meta["wheel_radius"] * 100.0, places=3)
        self.assertAlmostEqual(c.getAttr("caliper_FL.worldMatrix[0]")[12], (hp[0] + 0.05) * 100.0, places=3)
        # one mesh, two nodes: instanced, under unique names
        mirrors = c.ls("mirror*", type="transform")
        self.assertEqual(len(mirrors), 2)
        shapes = c.listRelatives(mirrors, shapes=True, fullPath=True)
        self.assertEqual(len(shapes), 2)                                  # one DAG path each...
        self.assertEqual(len(set(c.ls(shapes, uuid=True))), 1)            # ...to the same shape
        # glTF v is down from the top, Maya's up from the bottom
        uv = c.polyEditUV("body_geoShape.map[0]", query=True)
        self.assertTrue(0.0 <= uv[1] <= 1.0)

    def test_materials(self):
        c = self.cmds
        self._build()
        self.assertEqual(c.nodeType("M_Paint"), "aiStandardSurface")
        base = c.listConnections("M_Paint.baseColor", source=True)[0]
        self.assertEqual(c.getAttr(base + ".colorSpace"), "sRGB")
        self.assertAlmostEqual(c.getAttr(base + ".colorGainR"), 0.5, places=5)    # baseColorFactor
        orm = c.listConnections("M_Paint.specularRoughness", source=True, plugs=True)[0]
        self.assertTrue(orm.endswith(".outColorG"))
        self.assertTrue(c.listConnections("M_Paint.metalness", source=True, plugs=True)[0].endswith(".outColorB"))
        self.assertEqual(c.getAttr(orm.split(".")[0] + ".colorSpace"), "Raw")
        nm = c.listConnections("M_Paint.normalCamera", source=True)[0]
        self.assertEqual(c.nodeType(nm), "aiNormalMap")
        self.assertAlmostEqual(c.getAttr(nm + ".strength"), 0.7, places=5)
        self.assertAlmostEqual(c.getAttr("M_Paint.coat"), 0.3, places=5)
        # glass: 90 % transmitted, only lightly tinted, thin-walled
        self.assertAlmostEqual(c.getAttr("M_Glass.transmission"), 0.9, places=5)
        self.assertAlmostEqual(c.getAttr("M_Glass.transmissionColor")[0][0], 1.0 - 0.1 * 0.5, places=5)
        self.assertTrue(c.getAttr("M_Glass.thinWalled"))
        # decal: cut out by the texture's alpha
        self.assertTrue(c.listConnections("M_Decal.opacityR", source=True, plugs=True)[0].endswith(".outAlpha"))
        self.assertAlmostEqual(c.getAttr("M_Lamp.emissionColor")[0][1], 2.0, places=5)   # x strength
        self.assertEqual(c.listConnections(c.listRelatives("glass_geo", shapes=True)[0], type="shadingEngine"),
                         ["M_GlassSG"])

    def test_stale_when_the_glb_changes(self):
        out, _info = self._build()
        st = os.stat(self.glb)
        os.utime(self.glb, ns=(st.st_atime_ns, st.st_mtime_ns + 10 ** 9))
        try:
            self.assertFalse(self.carmodel.is_fresh(self.glb, out))
        finally:
            os.utime(self.glb, ns=(st.st_atime_ns, st.st_mtime_ns))

    # --- one click ----------------------------------------------------------------

    def _load(self):
        out, _info = self._build("fixture_car")
        self.cmds.file(new=True, force=True)
        real = self.carmodel.source_for_meta
        self.carmodel.source_for_meta = lambda meta: (self.glb, "fixture_car")
        try:
            root = self.importer.import_take(CAMS, fps=24, in_frame=1001, verbose=False, audio=False)
            top = self.carmodel.load_for_take(root, verbose=False)
        finally:
            self.carmodel.source_for_meta = real
        return root, top

    def test_load_attaches_every_part_and_it_follows(self):
        c = self.cmds
        root, top = self._load()
        ns = self.importer.namespace_of(root)
        parts = {p.split("|")[-1].split(":")[-1]: p for p in self.bind.attached_parts(root)}
        self.assertEqual(sorted(parts), sorted(["chassis", "steering_wheel", "wheel_FL", "wheel_FR",
                                                "wheel_RL", "wheel_RR", "wheel_FL_susp"]))
        self.assertTrue(c.referenceQuery(top, isNodeReferenced=True))
        follows = dict(self.bind.PARTS)
        lo, hi = c.playbackOptions(q=True, min=True), c.playbackOptions(q=True, max=True)
        frames = [lo + (hi - lo) * k / 5.0 for k in range(6)]
        worst = drift = 0.0
        first = {}
        for fr in frames:
            for part, n in parts.items():
                rig_w = c.getAttr("%s:%s.worldMatrix[0]" % (ns, follows[part]), time=fr)
                off = mu.m4_mul(c.getAttr(n + ".worldMatrix[0]", time=fr), mu.m4_inverse_affine(rig_w))
                first.setdefault(part, off)
                drift = max(drift, max(abs(a - b) for a, b in zip(off, first[part])))
            for w in take_io.WHEELS:     # the tyre sits on the rig's wheel, not just near it
                c.currentTime(fr)
                bb = c.exactWorldBoundingBox(parts["wheel_" + w])
                ctr = [(bb[0] + bb[3]) / 2.0, (bb[1] + bb[4]) / 2.0, (bb[2] + bb[5]) / 2.0]
                worst = max(worst, mu.v_len(mu.v_sub(ctr, c.xform("%s:wheel_%s_spin" % (ns, w), q=True, ws=True, t=True))))
        self.assertLess(drift, 1e-6)
        self.assertLess(worst, 1e-3)
        self.assertFalse(c.getAttr(root + ".proxyVisibility"))

    def test_unload_and_delete_remove_the_reference(self):
        c = self.cmds
        root, _top = self._load()
        with self.assertRaises(self.carmodel.CarModelError):
            self.carmodel.load_for_take(root, verbose=False)        # already loaded
        self.assertTrue(self.carmodel.unload_for_take(root))
        self.assertEqual(self._car_refs(), [])
        self.assertEqual(self.bind.attached_parts(root), [])
        self.assertTrue(c.getAttr(root + ".proxyVisibility"))
        root, _top = self._load()
        self.importer.delete_rig(root)                          # takes the car's reference with it
        self.assertEqual(self._car_refs(), [])
        self.assertFalse(c.objExists(root))

    def _car_refs(self):
        return [r for r in self.cmds.ls(type="reference") if r != "sharedReferenceNode"]

    def test_relocated_steering_wheel_turns_in_place(self):
        """The limo's case: the visible wheel 1 m behind the rig's column. It must stay where the
        model put it and turn as the rig's wheel turns - not swing round the rig's column."""
        c = self.cmds
        glb = os.path.join(self.tmp, "relocated.glb")
        write_car_glb(glb, self.meta, relocated=True)
        self.carmodel.build_scene(glb, self.carmodel.cache_dir("relocated"))
        self.assertEqual(sorted(c.listRelatives("car_model", children=True)),
                         sorted(["chassis", "steering_visual", "wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR",
                                 "wheel_FL_susp"]))
        c.file(new=True, force=True)
        real = self.carmodel.source_for_meta
        self.carmodel.source_for_meta = lambda meta: (glb, "relocated")
        try:
            root = self.importer.import_take(CAMS, fps=24, in_frame=1001, verbose=False, audio=False)
            self.carmodel.load_for_take(root, verbose=False)
        finally:
            self.carmodel.source_for_meta = real
        ns = self.importer.namespace_of(root)
        pivot = c.ls("%s_car:steering_visual_pivot" % ns, long=True)[0]
        group = c.listRelatives(pivot, parent=True, fullPath=True)[0]
        lo, hi = c.playbackOptions(q=True, min=True), c.playbackOptions(q=True, max=True)
        turned = drift = 0.0
        first = None
        for k in range(6):
            fr = lo + (hi - lo) * k / 5.0
            want = c.getAttr(ns + ":steering_wheel.rotateZ", time=fr)
            self.assertAlmostEqual(c.getAttr(pivot + ".rotateZ", time=fr), want, places=6)
            turned = max(turned, abs(want))
            off = mu.m4_mul(c.getAttr(group + ".worldMatrix[0]", time=fr),
                            mu.m4_inverse_affine(c.getAttr(ns + ":chassis.worldMatrix[0]", time=fr)))
            first = first or off
            drift = max(drift, max(abs(a - b) for a, b in zip(off, first)))
        self.assertGreater(turned, 5.0)                       # the fixture take does steer
        self.assertLess(drift, 1e-6)                          # rides on the chassis, in place
        self.bind.detach_model(root)
        self.assertFalse(c.listConnections(pivot + ".rotateZ", source=True, destination=False))
        self.assertAlmostEqual(c.getAttr(pivot + ".rotateZ"), 0.0, places=6)

    def test_build_cache_in_its_own_mayapy(self):
        """The one-click path: the build runs in a separate mayapy and the scene is untouched."""
        c = self.cmds
        c.polyCube(name="keep_me")
        out = os.path.join(self.tmp, "cache_subprocess")
        info = self.carmodel.build_cache(self.glb, out)
        self.assertTrue(c.objExists("keep_me"))
        self.assertFalse(c.objExists("car_model"))
        self.assertEqual(info["triangles"], self.facts["tris"])
        self.assertTrue(self.carmodel.is_fresh(self.glb, out))

    @unittest.skipUnless(os.path.isfile(BUS), "the bus model isn't in this checkout")
    def test_the_real_bus(self):
        out = os.path.join(self.tmp, "bus")
        info = self.carmodel.build_scene(BUS, out)
        self.assertEqual(info["triangles"], 329836)                  # the asset's README figure
        self.assertEqual(info["parts"], ["chassis", "steering_wheel", "wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"])
        self.assertEqual(info["notes"], [])
        bb = self.cmds.exactWorldBoundingBox("wheel_FL")
        self.assertAlmostEqual((bb[4] - bb[1]) / 2.0, 55.0, places=2)   # 0.55 m tyre


if __name__ == "__main__":
    unittest.main()

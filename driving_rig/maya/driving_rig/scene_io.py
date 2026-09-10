"""Read a Driving Rig scene export: scene.json + one OBJ per object. Standard library only.

    from driving_rig import scene_io
    scene = scene_io.load(r"D:/shots/scene_proc_heightmap_seed1234_800m_cell2_00_props")
    scene.manifest["collision_source"]
    ground = scene["Ground"]             # .points [(x,y,z) cm], .normals, .faces [(a,b,c) 0-based]
    surf = scene_io.Surface([ground])   # height lookup: surf.height_at(x, z) -> y or None

Coordinates are world space, centimetres, Y-up — the same space as the take rigs.
Faces are counter-clockwise (Maya/OBJ front faces).
"""
from __future__ import annotations

import json
import math
import os

FORMAT_NAME = "driving_rig_scene"
SUPPORTED_VERSIONS = (1,)


class SceneError(ValueError):
    pass


class SceneObject(object):
    def __init__(self, name, points, normals, faces, color=(0.5, 0.5, 0.5), collides=True):
        self.name = name
        self.collides = bool(collides)   # False = visual only (e.g. road paint): wheels pass over it
        self.points = points
        self.normals = normals
        self.faces = faces
        self.color = tuple(color)

    def bounds(self):
        xs, ys, zs = zip(*self.points)
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    def __repr__(self):
        return "<SceneObject %s: %d verts, %d tris>" % (self.name, len(self.points), len(self.faces))


class Scene(object):
    def __init__(self, manifest, folder, objects):
        self.manifest = manifest
        self.folder = folder
        self.objects = objects

    def __getitem__(self, name):
        for o in self.objects:
            if o.name == name:
                return o
        raise KeyError(name)

    def colliding(self):
        """The objects the wheels actually drive on."""
        return [o for o in self.objects if o.collides]

    @property
    def collision_source(self):
        return self.manifest.get("collision_source", "")

    @property
    def name(self):
        return os.path.basename(os.path.normpath(self.folder))


def manifest_path(path):
    """Accept the folder, scene.json, or any OBJ inside the folder."""
    if os.path.isdir(path):
        return os.path.join(path, "scene.json")
    if path.lower().endswith(".obj"):
        return os.path.join(os.path.dirname(path), "scene.json")
    return path


def read_obj(path):
    """Minimal OBJ reader for this exporter's output (v, vn, f with v//vn or v)."""
    pts, nrm, faces = [], [], []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("v "):
                x, y, z = line.split()[1:4]
                pts.append((float(x), float(y), float(z)))
            elif line.startswith("vn "):
                x, y, z = line.split()[1:4]
                nrm.append((float(x), float(y), float(z)))
            elif line.startswith("f "):
                idx = [int(tok.split("/")[0]) - 1 for tok in line.split()[1:]]
                for k in range(1, len(idx) - 1):          # fan-triangulate, just in case
                    faces.append((idx[0], idx[k], idx[k + 1]))
    return pts, nrm, faces


def load(path, validate_scene=True):
    mp = manifest_path(path)
    if not os.path.isfile(mp):
        raise SceneError("no scene.json at %s" % mp)
    with open(mp, "r", encoding="utf-8") as f:
        man = json.load(f)
    if man.get("format") != FORMAT_NAME or int(man.get("format_version", 0)) not in SUPPORTED_VERSIONS:
        raise SceneError("%s: not a Driving Rig scene export" % mp)
    folder = os.path.dirname(os.path.abspath(mp))
    objs = []
    for entry in man["objects"]:
        pts, nrm, faces = read_obj(os.path.join(folder, entry["file"]))
        objs.append(SceneObject(entry["name"], pts, nrm, faces, entry.get("color", (0.5, 0.5, 0.5)),
                                entry.get("collides", True)))
    scene = Scene(man, folder, objs)
    if validate_scene:
        errors = validate(scene)
        if errors:
            raise SceneError("%s failed validation:\n  %s" % (mp, "\n  ".join(errors[:10])))
    return scene


def validate(scene):
    e = []
    m = scene.manifest
    if m.get("units") != "cm" or m.get("up_axis") != "Y" or m.get("winding") != "ccw":
        e.append("manifest: expected units cm, up_axis Y, winding ccw")
    for entry, obj in zip(m["objects"], scene.objects):
        if len(obj.points) != entry["vertices"]:
            e.append("%s: %d vertices, manifest says %d" % (obj.name, len(obj.points), entry["vertices"]))
        if len(obj.faces) != entry["triangles"]:
            e.append("%s: %d triangles, manifest says %d" % (obj.name, len(obj.faces), entry["triangles"]))
        n = len(obj.points)
        if any(not (0 <= i < n) for f in obj.faces for i in f):
            e.append("%s: face index out of range" % obj.name)
        if obj.points:
            lo, hi = obj.bounds()
            for k in range(3):
                if abs(lo[k] - entry["bounds_min"][k]) > 0.01 or abs(hi[k] - entry["bounds_max"][k]) > 0.01:
                    e.append("%s: bounds differ from manifest" % obj.name)
                    break
    return e


def same_ground(take_meta, scene):
    """True if the take was driven on exactly this ground. Mismatched ground reads instantly
    as floating or sunken wheels."""
    return str(take_meta.get("collision_source", "")) == str(scene.collision_source)


def face_normal(obj, face):
    a, b, c = (obj.points[i] for i in face)
    u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    ln = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
    return (n[0] / ln, n[1] / ln, n[2] / ln) if ln > 1e-12 else None


def winding_agreement(obj):
    """Fraction of faces whose CCW (right-hand) normal points the same way as their vertex
    normals. ~1.0 = faces are front-facing in Maya; ~0.0 = the whole mesh is inside out."""
    if not obj.normals:
        return float("nan")
    good = total = 0
    for f in obj.faces:
        n = face_normal(obj, f)
        if n is None:
            continue
        vn = [obj.normals[i] for i in f]
        s = (sum(x[0] for x in vn), sum(x[1] for x in vn), sum(x[2] for x in vn))
        total += 1
        if n[0] * s[0] + n[1] * s[1] + n[2] * s[2] > 0:
            good += 1
    return good / float(total) if total else float("nan")


class Surface(object):
    """Vertical ray lookup over one or more objects: height_at(x, z) = highest surface y at
    (x, z), or None. Bucketed, so 320k triangles are fine."""

    def __init__(self, objects, bucket=200.0):
        self.b = float(bucket)
        self.grid = {}
        self.tris = []
        for obj in objects:
            for f in obj.faces:
                a, b, c = (obj.points[i] for i in f)
                t = len(self.tris)
                self.tris.append((a, b, c))
                x0, x1 = min(a[0], b[0], c[0]), max(a[0], b[0], c[0])
                z0, z1 = min(a[2], b[2], c[2]), max(a[2], b[2], c[2])
                for gx in range(int(math.floor(x0 / self.b)), int(math.floor(x1 / self.b)) + 1):
                    for gz in range(int(math.floor(z0 / self.b)), int(math.floor(z1 / self.b)) + 1):
                        self.grid.setdefault((gx, gz), []).append(t)

    def height_at(self, x, z):
        best = None
        for t in self.grid.get((int(math.floor(x / self.b)), int(math.floor(z / self.b))), ()):
            a, b, c = self.tris[t]
            d = (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2])
            if abs(d) < 1e-12:
                continue
            l1 = ((b[2] - c[2]) * (x - c[0]) + (c[0] - b[0]) * (z - c[2])) / d
            l2 = ((c[2] - a[2]) * (x - c[0]) + (a[0] - c[0]) * (z - c[2])) / d
            l3 = 1.0 - l1 - l2
            if min(l1, l2, l3) >= -1e-9:
                y = l1 * a[1] + l2 * b[1] + l3 * c[1]
                best = y if best is None else max(best, y)
        return best

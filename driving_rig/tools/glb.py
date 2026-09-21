"""Minimal glTF 2.0 (.glb) writer and a box/frustum mesh builder.

Enough to build low-poly vehicle bodies: every shape is a hexahedron defined by two rectangles
(a cross-section at each end), which is all a car silhouette really needs - a tapered nose, a
raked screen, a cabin narrower than the body. Flat-shaded: each face gets its own vertices and
one normal, which is what "low poly" should look like.

Units are metres, Y up, -Z forward: Godot's convention and the rig's.
"""
from __future__ import annotations

import json
import struct


class Mesh:
    """Triangles grouped by material name."""

    def __init__(self):
        self.groups: dict[str, dict] = {}
        self._solid = 0          # which hexa each triangle came from, for the overlap check

    def _group(self, material: str) -> dict:
        return self.groups.setdefault(material, {"v": [], "n": [], "i": [], "s": []})

    def quad(self, material: str, a, b, c, d) -> None:
        """One flat quad. Corners are given counter-clockwise as seen from INSIDE the solid (the
        order hexa() lists them in), so they are reversed here: glTF wants counter-clockwise
        seen from outside, and its normal pointing out."""
        a, b, c, d = d, c, b, a
        # Two triangles, each with its own normal: a tapered solid's side can be twisted (not
        # flat), and one shared normal would be wrong for one of its halves.
        g = self._group(material)
        for tri in ((a, b, c), (a, c, d)):
            n = _normal(*tri)
            base = len(g["v"])
            for p in tri:
                g["v"].append(p)
                g["n"].append(n)
            g["i"] += [base, base + 1, base + 2]
            g["s"].append(self._solid)

    def hexa(self, material: str, front: tuple, back: tuple, x: float = 0.0) -> None:
        """A solid between two rectangular cross-sections.

        Each section is (z, half_width, y_bottom, y_top) - or
        (z, half_width_bottom, half_width_top, y_bottom, y_top) for a tapered one.
        """
        self._solid += 1
        fz, fwb, fwt, fyb, fyt = _section(front)
        bz, bwb, bwt, byb, byt = _section(back)
        # corners: front/back x bottom/top x left/right
        # x shifts the whole solid sideways (lights, mirrors); sections are symmetric about it
        flb, frb = (x - fwb, fyb, fz), (x + fwb, fyb, fz)
        flt, frt = (x - fwt, fyt, fz), (x + fwt, fyt, fz)
        blb, brb = (x - bwb, byb, bz), (x + bwb, byb, bz)
        blt, brt = (x - bwt, byt, bz), (x + bwt, byt, bz)
        first = len(self._group(material)["v"])
        self.quad(material, flb, frb, frt, flt)      # front  (-Z face, toward the nose)
        self.quad(material, brb, blb, blt, brt)      # back
        self.quad(material, flt, frt, brt, blt)      # roof
        self.quad(material, blb, brb, frb, flb)      # floor
        self.quad(material, blt, blb, flb, flt)      # left
        self.quad(material, frb, brb, brt, frt)      # right
        # Every face of a convex solid must point away from its middle. 0.15.0 shipped with all
        # of them pointing in - the cars rendered inside-out - so this refuses to build that.
        g = self._group(material)
        mid = [sum(p[i] for p in (flb, frb, flt, frt, blb, brb, blt, brt)) / 8 for i in range(3)]
        for t in range(12):                           # six faces, two triangles each
            tri = g["v"][first + t * 3:first + t * 3 + 3]
            centre = [sum(p[i] for p in tri) / 3 for i in range(3)]
            n = g["n"][first + t * 3]
            if sum(n[i] * (centre[i] - mid[i]) for i in range(3)) <= 0.0 and sum(x * x for x in n) > 0.5:
                raise ValueError("face %d of a hexa points inward" % (t // 2))

    def box(self, material: str, centre, size) -> None:
        cx, cy, cz = centre
        sx, sy, sz = size
        self.hexa(material,
                  (cz - sz / 2, sx / 2, cy - sy / 2, cy + sy / 2),
                  (cz + sz / 2, sx / 2, cy - sy / 2, cy + sy / 2), x=cx)

    def mirror_x(self, material: str, centre, size) -> None:
        """The same box on both sides (lights, mirrors, stacks)."""
        cx, cy, cz = centre
        self.box(material, (cx, cy, cz), size)
        self.box(material, (-cx, cy, cz), size)

    def coplanar_overlaps(self) -> list:
        """Pairs of triangles from different solids that lie in the same plane, face the same
        way and overlap - both visible from the same side at the same depth, which is exactly
        what z-fights. Faces back to back (one up, one down) are fine: one is always culled."""
        tris = []
        for g in self.groups.values():
            for t in range(0, len(g["i"]), 3):
                pts = [g["v"][g["i"][t + k]] for k in range(3)]
                n = g["n"][g["i"][t]]
                if sum(x * x for x in n) < 0.5:
                    continue
                d = sum(n[k] * pts[0][k] for k in range(3))
                tris.append((pts, n, d, g["s"][t // 3]))
        hits = []
        for a in range(len(tris)):
            pa, na, da, sa = tris[a]
            for b in range(a + 1, len(tris)):
                pb, nb, db, sb = tris[b]
                if sa == sb or sum(na[k] * nb[k] for k in range(3)) < 0.999 or abs(da - db) > 1e-4:
                    continue
                # project onto the plane's two largest axes and test 2D overlap
                ax = max(range(3), key=lambda k: abs(na[k]))
                u, v = [k for k in range(3) if k != ax]
                if _overlap_2d([(p[u], p[v]) for p in pa], [(p[u], p[v]) for p in pb]):
                    hits.append((sa, sb, [round(x, 3) for x in pa[0]]))
        return hits

    def bounds(self) -> tuple:
        pts = [p for g in self.groups.values() for p in g["v"]]
        lo = [min(p[i] for p in pts) for i in range(3)]
        hi = [max(p[i] for p in pts) for i in range(3)]
        return lo, hi

    def triangle_count(self) -> int:
        return sum(len(g["i"]) // 3 for g in self.groups.values())


def _overlap_2d(t1, t2, eps=1e-6) -> bool:
    """Two triangles overlap with real area (touching edges don't count): separating axes."""
    for tri in (t1, t2):
        for i in range(3):
            ex, ey = tri[(i + 1) % 3][0] - tri[i][0], tri[(i + 1) % 3][1] - tri[i][1]
            nx, ny = -ey, ex
            a = [nx * p[0] + ny * p[1] for p in t1]
            b = [nx * p[0] + ny * p[1] for p in t2]
            if max(a) <= min(b) + eps * (abs(nx) + abs(ny)) or max(b) <= min(a) + eps * (abs(nx) + abs(ny)):
                return False
    return True


def _section(s):
    if len(s) == 4:
        z, w, yb, yt = s
        return z, w, w, yb, yt
    return s


def _normal(a, b, c):
    u = [b[i] - a[i] for i in range(3)]
    v = [c[i] - a[i] for i in range(3)]
    n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
    ln = sum(x * x for x in n) ** 0.5 or 1.0
    return [x / ln for x in n]


def write_glb(path: str, mesh: Mesh, materials: dict, name: str) -> dict:
    """materials: {name: (r, g, b, a, metallic, roughness)}"""
    buf = bytearray()
    views, accessors, prims = [], [], []

    def view(data: bytes, target: int) -> int:
        while len(buf) % 4:
            buf.append(0)
        views.append({"buffer": 0, "byteOffset": len(buf), "byteLength": len(data), "target": target})
        buf.extend(data)
        return len(views) - 1

    # two pieces showing the same face at the same depth flicker: refuse to write that
    clash = mesh.coplanar_overlaps()
    if clash:
        raise ValueError("%s: %d overlapping coplanar faces (first near %s)" % (name, len(clash), clash[0][2]))
    for mat_name, g in mesh.groups.items():
        # glTF front faces are counter-clockwise: the right-hand normal of each triangle's
        # index order has to agree with the stored normal, or the renderer culls the wrong side
        for t in range(0, len(g["i"]), 3):
            a, b, c = (g["v"][g["i"][t + k]] for k in range(3))
            geo = _normal(a, b, c)
            if sum(geo[k] * g["n"][g["i"][t]][k] for k in range(3)) < 0.99:
                raise ValueError("%s: triangle %d winds against its normal" % (mat_name, t // 3))
        vb = b"".join(struct.pack("<3f", *p) for p in g["v"])
        nb = b"".join(struct.pack("<3f", *p) for p in g["n"])
        ib = b"".join(struct.pack("<I", i) for i in g["i"])
        lo = [min(p[i] for p in g["v"]) for i in range(3)]
        hi = [max(p[i] for p in g["v"]) for i in range(3)]
        vpos = len(accessors)
        accessors.append({"bufferView": view(vb, 34962), "componentType": 5126, "count": len(g["v"]),
                          "type": "VEC3", "min": lo, "max": hi})
        accessors.append({"bufferView": view(nb, 34962), "componentType": 5126, "count": len(g["n"]),
                          "type": "VEC3"})
        accessors.append({"bufferView": view(ib, 34963), "componentType": 5125, "count": len(g["i"]),
                          "type": "SCALAR"})
        prims.append({"attributes": {"POSITION": vpos, "NORMAL": vpos + 1}, "indices": vpos + 2,
                      "material": list(materials).index(mat_name)})

    gltf = {
        "asset": {"version": "2.0", "generator": "driving rig proxy builder"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": prims}],
        "materials": [
            {"name": m, "doubleSided": False,
             "pbrMetallicRoughness": {"baseColorFactor": list(v[:4]), "metallicFactor": v[4],
                                      "roughnessFactor": v[5]}}
            for m, v in materials.items()],
        "buffers": [{"byteLength": len(buf)}],
        "bufferViews": views,
        "accessors": accessors,
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    bn = bytes(buf)
    bn += b"\0" * (-len(bn) % 4)
    glb = b"glTF" + struct.pack("<II", 2, 12 + 8 + len(js) + 8 + len(bn))
    glb += struct.pack("<I", len(js)) + b"JSON" + js
    glb += struct.pack("<I", len(bn)) + b"BIN\0" + bn
    with open(path, "wb") as f:
        f.write(glb)
    lo, hi = mesh.bounds()
    return {"path": path, "tris": mesh.triangle_count(),
            "size": [round(hi[i] - lo[i], 3) for i in range(3)],
            "lo": [round(x, 3) for x in lo], "hi": [round(x, 3) for x in hi]}

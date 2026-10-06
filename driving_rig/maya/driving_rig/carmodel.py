"""The game's full car models on take rigs, with Arnold shaders - one click per take.

    from driving_rig import carmodel
    carmodel.load_for_take(root)      # build the cache if needed, reference it, attach it
    carmodel.unload_for_take(root)    # detach and remove the reference

The models in models/vehicles/<profile>/*.glb are authored on the rig's own bind car: a
`chassis` node at static ride height, the four wheel_XX_steer > _susp > _spin > _geo chains
and a steering_column > steering_wheel, in metres, Y up, -Z forward. That is exactly the pose
of the Maya bind car (bind.create_bind_car), so a model built from the file's own coordinates
lines up with it with no placement at all.

Cache: <project>/maya/cars/<profile>/car.mb with build.json beside it. Not in git (it is big
and it would go stale); rebuilt whenever the .glb changes, in a separate mayapy so the scene you
have open is never touched. Shot files reference it, so a new version of a car reaches every
shot. Textures are used where they are - the PNGs beside the .glb that it points at (Arnold's
.tx conversions land there too, git-ignored); only an image embedded in the .glb is written out
to the cache's textures/.

What gets built, under one top group `car_model` (at the bind car's frame):
    chassis           everything that isn't on a wheel chain or the steering wheel
    wheel_XX          what spins (follows the rig's wheel_XX_spin)
    wheel_XX_susp     on the suspension but not spinning: brake calipers (wheel_XX_susp)
    wheel_XX_steer    steers only (wheel_XX_steer)
    steering_wheel    turns with the rig's steering_wheel
    steering_visual   a steering wheel the model moved off the rig's column (the limo's sits in
                      the real cabin, 1.9 m back): rides on the chassis, and the
                      steering_visual_pivot inside it copies the rig wheel's rotateZ
Each mesh keeps its glTF node name and transform; meshes used by several nodes are instanced.

Materials (glTF metallic/roughness) become aiStandardSurface - standardSurface if Arnold isn't
loaded; the attributes are the same model and Arnold renders both:
    baseColor (+ factor as colorGain), roughness = ORM green, metalness = ORM blue (Raw),
    normal map through aiNormalMap (glTF and Arnold agree on +Y), emission (x emissive_strength),
    clearcoat -> coat, ior -> specularIOR, transmission -> transmission.
    Alpha-blended glass with no texture becomes thin-walled transmission (1 - alpha), which is
    what the game's "very clear" alpha stands in for. A textured alpha (decals) becomes opacity.
    Ambient occlusion maps are left out: they are neutral white in these assets, and Arnold
    computes its own.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time

from maya import cmds

from . import __version__
from .mayautil import find_rig_root, namespace_of, put_in_world, scene_units

BUILDER_VERSION = 3            # bump to rebuild every cache (a change in what gets built)
TOP = "car_model"
CAR_ATTR = "drvCarModel"
CACHE_ENV = "DRIVING_RIG_CAR_CACHE"       # override where caches go (tests use a temp dir)
PROJECT_ENV = "DRIVING_RIG_PROJECT"       # override the Godot project folder
WHEELS = ("FL", "FR", "RL", "RR")


class CarModelError(RuntimeError):
    pass


# === where things are ===========================================================

def project_root():
    """The Godot project folder (has project.godot). This package lives in <project>/maya/."""
    env = os.environ.get(PROJECT_ENV)
    cands = [env] if env else []
    cands.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    for c in cands:
        if c and os.path.isfile(os.path.join(c, "project.godot")):
            return os.path.normpath(c)
    raise CarModelError("Can't find the Godot project (project.godot) above %s.\nSet %s to its folder."
                        % (os.path.dirname(os.path.abspath(__file__)), PROJECT_ENV))


def res_path(res):
    """res://a/b -> <project>/a/b."""
    if not res.startswith("res://"):
        raise CarModelError("Not a project path: %s" % res)
    return os.path.normpath(os.path.join(project_root(), res[len("res://"):]))


def cache_root():
    return os.environ.get(CACHE_ENV) or os.path.join(project_root(), "maya", "cars")


def cache_dir(profile):
    return os.path.join(cache_root(), profile)


def chassis_of_profile(tres_path):
    """The res:// path of a car profile's model, read from the .tres text: chassis_path, or the
    scene itself (chassis_scene = ExtResource) in profiles saved before 0.27."""
    with open(tres_path, encoding="utf-8") as fh:
        text = fh.read()
    m = re.search(r'^chassis_path\s*=\s*"([^"]+)"', text, re.M)
    if m:
        return m.group(1)
    m = re.search(r'^chassis_scene\s*=\s*ExtResource\("([^"]+)"\)', text, re.M)
    if not m:
        return None
    for line in text.splitlines():
        if line.startswith("[ext_resource") and ('id="%s"' % m.group(1)) in line:
            p = re.search(r'path="([^"]+)"', line)
            return p.group(1) if p else None
    return None


def source_for_meta(meta):
    """(glb path, profile name) for the car a take was driven with. The profile's *current*
    model wins (so an old take gets the new car); the take's own record is the fallback."""
    prof = (meta.get("car_profile") or {})
    path = prof.get("path", "")
    name = os.path.splitext(os.path.basename(path))[0] if path else ""
    tried = []
    if path.startswith("res://") and os.path.isfile(res_path(path)):
        res = chassis_of_profile(res_path(path))
        if res:
            tried.append(res)
    res = (meta.get("car_params") or {}).get("chassis_scene", "")
    if res:
        tried.append(res)
    for res in tried:
        if res.lower().endswith(".glb") and os.path.isfile(res_path(res)):
            return res_path(res), name or os.path.splitext(os.path.basename(res))[0]
    raise CarModelError("No car model found for this take's car (%s).\nLooked for: %s"
                        % (prof.get("name", "unknown"), ", ".join(tried) or "nothing recorded"))


# === glTF reading ===============================================================

_COMP = {5120: "i1", 5121: "u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
_NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class Gltf(object):
    """Just enough glTF 2.0 (.glb) for these models: node tree, triangle meshes, PBR materials,
    embedded images."""

    def __init__(self, path):
        import numpy as np
        self.np = np
        self.path = path
        with open(path, "rb") as fh:
            data = fh.read()
        magic, version, _length = struct.unpack_from("<III", data, 0)
        if magic != 0x46546C67 or version != 2:
            raise CarModelError("Not a glTF 2.0 binary: %s" % path)
        off = 12
        self.json, self.bin = None, b""
        while off < len(data):
            clen, ctype = struct.unpack_from("<II", data, off)
            chunk = data[off + 8: off + 8 + clen]
            if ctype == 0x4E4F534A:
                self.json = json.loads(chunk.decode("utf-8"))
            elif ctype == 0x004E4942:
                self.bin = chunk
            off += 8 + clen
        if self.json is None:
            raise CarModelError("No JSON chunk in %s" % path)
        j = self.json
        self.nodes = j.get("nodes", [])
        self.meshes = j.get("meshes", [])
        self.materials = j.get("materials", [])
        self.textures = j.get("textures", [])
        self.images = j.get("images", [])
        self.parent = {}
        for i, n in enumerate(self.nodes):
            for c in n.get("children", []):
                self.parent[c] = i

    def accessor(self, i):
        np = self.np
        a = self.json["accessors"][i]
        if a.get("sparse"):
            raise CarModelError("Sparse accessors aren't supported (accessor %d)" % i)
        dt = np.dtype(_COMP[a["componentType"]])
        n = _NCOMP[a["type"]]
        count = a["count"]
        if "bufferView" not in a:
            return np.zeros((count, n), dt)
        bv = self.json["bufferViews"][a["bufferView"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", 0)
        if stride and stride != n * dt.itemsize:
            arr = np.ndarray((count, n), dt, buffer=self.bin, offset=off, strides=(stride, dt.itemsize))
        else:
            arr = np.frombuffer(self.bin, dt, count * n, off).reshape(count, n)
        return np.array(arr)              # own copy, native byte order

    def image_file(self, i):
        """Path of an external image (a `uri` beside the model), or None if it's embedded."""
        uri = self.images[i].get("uri")
        if uri is None:
            return None
        if uri.startswith("data:"):
            raise CarModelError("Image %d is a data URI - not supported" % i)
        from urllib.parse import unquote
        path = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(self.path)), unquote(uri)))
        if not os.path.isfile(path):
            raise CarModelError("Texture %s is missing (needed by %s)" % (path, os.path.basename(self.path)))
        return path

    def image_bytes(self, i):
        im = self.images[i]
        if "bufferView" not in im:
            raise CarModelError("Image %d isn't embedded" % i)
        bv = self.json["bufferViews"][im["bufferView"]]
        off = bv.get("byteOffset", 0)
        return self.bin[off: off + bv["byteLength"]], im.get("mimeType", "image/png")

    def local_matrix(self, i):
        """4x4, column vectors (p' = M p), metres."""
        np = self.np
        n = self.nodes[i]
        if "matrix" in n:
            return np.array(n["matrix"], float).reshape(4, 4).T
        t = n.get("translation", [0.0, 0.0, 0.0])
        x, y, z, w = n.get("rotation", [0.0, 0.0, 0.0, 1.0])
        s = n.get("scale", [1.0, 1.0, 1.0])
        r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                      [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                      [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        m = np.eye(4)
        m[:3, :3] = r * np.array(s, float)
        m[:3, 3] = t
        return m

    def world_matrix(self, i):
        m = self.local_matrix(i)
        while i in self.parent:
            i = self.parent[i]
            m = self.local_matrix(i) @ m
        return m

    def find_ancestor(self, i, name):
        """Index of the nearest node called `name` at or above i, or None."""
        while True:
            if self.nodes[i].get("name") == name:
                return i
            if i not in self.parent:
                return None
            i = self.parent[i]

    def ancestry(self, i):
        """Node names from i up to its scene root, i first."""
        out = [self.nodes[i].get("name", "")]
        while i in self.parent:
            i = self.parent[i]
            out.append(self.nodes[i].get("name", ""))
        return out


def part_of(names):
    """Which rig part a node rides on, from its own and its ancestors' names (nearest wins)."""
    for nm in names:
        for w in WHEELS:
            if nm == "wheel_%s_spin" % w:
                return "wheel_%s" % w
            if nm == "wheel_%s_susp" % w:
                return "wheel_%s_susp" % w
            if nm == "wheel_%s_steer" % w:
                return "wheel_%s_steer" % w
        if nm == "steering_visual_pivot":
            return "steering_visual"
        if nm == "steering_wheel":
            return "steering_wheel"
    return "chassis"


# === building the cache (runs in its own mayapy) ================================

def _name(s, fallback="node"):
    s = re.sub(r"[^A-Za-z0-9_]", "_", s or "") or fallback
    return ("n" + s) if s[0].isdigit() else s


def _maya_matrix(m):
    """glTF column-vector metres -> Maya row-major list, translation in cm."""
    mm = m.copy()
    mm[:3, 3] *= 100.0
    return [float(v) for v in mm.T.flatten()]


def _load_arnold():
    try:
        if not cmds.pluginInfo("mtoa", query=True, loaded=True):
            cmds.loadPlugin("mtoa", quiet=True)
        return True
    except Exception:
        return False


def _file_node(path, name, raw, gain=None, alpha_gain=None):
    f = cmds.shadingNode("file", asTexture=True, isColorManaged=True, name=name)
    p = cmds.shadingNode("place2dTexture", asUtility=True, name=name + "_p2d")
    for a in ("coverage", "translateFrame", "rotateFrame", "mirrorU", "mirrorV", "stagger", "wrapU",
              "wrapV", "repeatUV", "offset", "rotateUV", "noiseUV", "vertexUvOne", "vertexUvTwo",
              "vertexUvThree", "vertexCameraOne"):
        cmds.connectAttr("%s.%s" % (p, a), "%s.%s" % (f, a))
    cmds.connectAttr(p + ".outUV", f + ".uvCoord")
    cmds.connectAttr(p + ".outUvFilterSize", f + ".uvFilterSize")
    cmds.setAttr(f + ".fileTextureName", path.replace("\\", "/"), type="string")
    cmds.setAttr(f + ".ignoreColorSpaceFileRules", 1)
    cmds.setAttr(f + ".colorSpace", "Raw" if raw else "sRGB", type="string")
    if gain is not None:
        cmds.setAttr(f + ".colorGain", *gain)
    if alpha_gain is not None:
        cmds.setAttr(f + ".alphaGain", alpha_gain)
    return f


def _material(gl, i, images, arnold, report):
    """Shading group for glTF material i."""
    m = gl.materials[i]
    ext = m.get("extensions", {})
    pbr = m.get("pbrMetallicRoughness", {})
    nm = _name(m.get("name"), "material%d" % i)
    sh = cmds.shadingNode("aiStandardSurface" if arnold else "standardSurface", asShader=True, name="M_" + nm)
    sg = cmds.sets(renderable=True, noSurfaceShader=True, empty=True, name="M_%sSG" % nm)
    cmds.connectAttr(sh + ".outColor", sg + ".surfaceShader")

    def tex(info):
        t = gl.textures[info["index"]]
        if "source" not in t:
            raise CarModelError("Texture %d has no image" % info["index"])
        if info.get("texCoord", 0) != 0:
            report.append("%s: a texture uses a second UV set - shown with the first" % nm)
        if "KHR_texture_transform" in info.get("extensions", {}):
            report.append("%s: texture transform ignored" % nm)
        return images[t["source"]]

    base = list(pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0]))
    cmds.setAttr(sh + ".base", 1.0)
    base_tex = pbr.get("baseColorTexture")
    if base_tex:
        f = _file_node(tex(base_tex), nm + "_baseColor", False, base[:3], base[3])
        cmds.connectAttr(f + ".outColor", sh + ".baseColor")
    else:
        cmds.setAttr(sh + ".baseColor", *base[:3])

    rough = float(pbr.get("roughnessFactor", 1.0))
    metal = float(pbr.get("metallicFactor", 1.0))
    mr = pbr.get("metallicRoughnessTexture")
    if mr:
        f = _file_node(tex(mr), nm + "_ORM", True, (1.0, rough, metal))
        cmds.connectAttr(f + ".outColorG", sh + ".specularRoughness")
        cmds.connectAttr(f + ".outColorB", sh + ".metalness")
    else:
        cmds.setAttr(sh + ".specularRoughness", rough)
        cmds.setAttr(sh + ".metalness", metal)

    nt = m.get("normalTexture")
    if nt:
        f = _file_node(tex(nt), nm + "_normal", True)
        if arnold:
            n = cmds.shadingNode("aiNormalMap", asUtility=True, name=nm + "_normalMap")
            cmds.connectAttr(f + ".outColor", n + ".input")
            cmds.setAttr(n + ".strength", float(nt.get("scale", 1.0)))
            cmds.connectAttr(n + ".outValue", sh + ".normalCamera")
        else:
            b = cmds.shadingNode("bump2d", asUtility=True, name=nm + "_normalMap")
            cmds.setAttr(b + ".bumpInterp", 1)                      # tangent-space normals
            cmds.setAttr(b + ".bumpDepth", float(nt.get("scale", 1.0)))
            cmds.connectAttr(f + ".outAlpha", b + ".bumpValue")
            cmds.connectAttr(b + ".outNormal", sh + ".normalCamera")

    strength = float(ext.get("KHR_materials_emissive_strength", {}).get("emissiveStrength", 1.0))
    emit = [float(v) * strength for v in m.get("emissiveFactor", [0.0, 0.0, 0.0])]
    et = m.get("emissiveTexture")
    if et or max(emit) > 0.0:
        cmds.setAttr(sh + ".emission", 1.0)
        if et:
            f = _file_node(tex(et), nm + "_emissive", False, emit)
            cmds.connectAttr(f + ".outColor", sh + ".emissionColor")
        else:
            cmds.setAttr(sh + ".emissionColor", *emit)

    cc = ext.get("KHR_materials_clearcoat")
    if cc:
        cmds.setAttr(sh + ".coat", float(cc.get("clearcoatFactor", 0.0)))
        cmds.setAttr(sh + ".coatRoughness", float(cc.get("clearcoatRoughnessFactor", 0.0)))
    ior = ext.get("KHR_materials_ior")
    if ior:
        cmds.setAttr(sh + ".specularIOR", float(ior.get("ior", 1.5)))

    tr = ext.get("KHR_materials_transmission")
    mode = m.get("alphaMode", "OPAQUE")
    if tr or (mode == "BLEND" and not base_tex):
        # Glass. The game draws alpha x colour over (1 - alpha) x what's behind: a 10 % tint over
        # a clear view. So transmit (1 - alpha), and filter what passes by only alpha's share of
        # the colour - the full colour would tint every ray, twice through a cabin.
        a = float(base[3])
        amount = float(tr.get("transmissionFactor", 0.0)) if tr else 1.0 - a
        cmds.setAttr(sh + ".transmission", amount)
        cmds.setAttr(sh + ".transmissionColor", *[1.0 - a * (1.0 - c) for c in base[:3]])
        cmds.setAttr(sh + ".thinWalled", True)
    elif mode in ("BLEND", "MASK"):
        # a textured alpha (decals, labels): cut out by it
        if base_tex:
            fa = cmds.listConnections(sh + ".baseColor", source=True, destination=False)[0]
            for c in "RGB":
                cmds.connectAttr(fa + ".outAlpha", sh + ".opacity" + c)
        else:
            cmds.setAttr(sh + ".opacity", base[3], base[3], base[3])
    return sg


def build_scene(glb_path, out_dir, report=None):
    """New scene -> the car from glb_path -> out_dir/car.mb (+ textures/, build.json).
    Throws away the open scene: run it in its own mayapy (build_cache does)."""
    report = [] if report is None else report
    t0 = time.time()
    gl = Gltf(glb_path)
    np = gl.np
    cmds.file(new=True, force=True)
    arnold = _load_arnold()
    if not arnold:
        report.append("Arnold (mtoa) isn't available: built with standardSurface instead")
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)
    tex_dir = os.path.join(out_dir, "textures")      # only for images embedded in the .glb
    if os.path.isdir(tex_dir):
        shutil.rmtree(tex_dir)                         # last build's copies (and their .tx)
    images = []
    for i, im in enumerate(gl.images):
        ext_file = gl.image_file(i)
        if ext_file:                      # the game's models keep their PNGs beside the .glb
            images.append(ext_file)
            continue
        data, mime = gl.image_bytes(i)
        ext = {"image/png": ".png", "image/jpeg": ".jpg"}.get(mime, ".png")
        if not os.path.isdir(tex_dir):
            os.makedirs(tex_dir)
        p = os.path.join(tex_dir, "%02d_%s%s" % (i, _name(im.get("name"), "image"), ext))
        with open(p, "wb") as fh:
            fh.write(data)
        images.append(os.path.abspath(p))

    import maya.api.OpenMaya as om
    tris = 0
    with scene_units():
        top = cmds.createNode("transform", name=TOP, skipSelect=True)
        groups = {}

        def group(part):
            if part not in groups:
                groups[part] = cmds.createNode("transform", name=part, parent=top, skipSelect=True)
            return groups[part]

        shading = {}

        def sg_for(mi):
            if mi not in shading:
                shading[mi] = _material(gl, mi, images, arnold, report)
            return shading[mi]

        first_use = {}                    # glTF mesh -> transform that owns its shape
        # unique short names: glTF names repeat (sports car), and a mesh must never take a part
        # group's name before the group exists (Maya would rename the group, and attach misses it)
        used = set(cmds.ls() or []) | {"chassis", "steering_wheel", "steering_visual",
                                       "steering_visual_pivot"} | \
            {"wheel_%s%s" % (w, s) for w in WHEELS for s in ("", "_susp", "_steer")}
        for ni, node in enumerate(gl.nodes):
            if "mesh" not in node:
                continue
            part = part_of(gl.ancestry(ni))
            name = base = _name(node.get("name"), "mesh%d" % ni)
            k = 2
            while name in used or name + "Shape" in used:
                name = "%s_%d" % (base, k)
                k += 1
            used.update((name, name + "Shape"))
            world = gl.world_matrix(ni)
            holder = group(part)
            if part == "steering_visual":
                # a wheel moved off the rig's column (the limo): the group sits at its own pivot,
                # and steering_visual_pivot inside it is what turns (attach drives its rotateZ)
                pv = gl.find_ancestor(ni, "steering_visual_pivot")
                if not cmds.objExists("steering_visual_pivot"):
                    cmds.xform(holder, objectSpace=True, matrix=_maya_matrix(gl.world_matrix(pv)))
                    cmds.createNode("transform", name="steering_visual_pivot", parent=holder, skipSelect=True)
                holder = "steering_visual_pivot"
                world = np.linalg.inv(gl.world_matrix(pv)) @ world
            mat = _maya_matrix(world)
            mesh_i = node["mesh"]
            if mesh_i in first_use:
                xf = cmds.instance(first_use[mesh_i], name=name)[0]
                # instance() puts it beside the original; parent() returns None for "already there"
                if (cmds.listRelatives(xf, parent=True) or [None])[0] != holder:
                    xf = cmds.parent(xf, holder, relative=True)[0]
                cmds.xform(xf, objectSpace=True, matrix=mat)
                continue
            xf = cmds.createNode("transform", name=name, parent=holder, skipSelect=True)
            cmds.xform(xf, objectSpace=True, matrix=mat)
            first_use[mesh_i] = xf
            n_tri = _build_mesh(gl, mesh_i, xf, sg_for, om, np, report)
            tris += n_tri
        for part in sorted(groups):
            cmds.addAttr(groups[part], longName="drvPart", dataType="string")
            cmds.setAttr(groups[part] + ".drvPart", part, type="string")
        cmds.addAttr(top, longName=CAR_ATTR, dataType="string")
        cmds.setAttr(top + "." + CAR_ATTR, os.path.basename(glb_path), type="string")

    mb = os.path.join(out_dir, "car.mb")
    cmds.file(rename=mb)
    cmds.file(save=True, type="mayaBinary", force=True)
    st = os.stat(glb_path)
    info = {"source": os.path.abspath(glb_path), "size": st.st_size, "mtime_ns": st.st_mtime_ns,
            "builder": BUILDER_VERSION, "rig_version": __version__, "arnold": arnold,
            "triangles": tris, "parts": sorted(groups), "materials": len(shading),
            "textures": len(images), "seconds": round(time.time() - t0, 1), "notes": report}
    with open(os.path.join(out_dir, "build.json"), "w", encoding="utf-8") as fh:
        json.dump(info, fh, indent=1)
    return info


def _build_mesh(gl, mesh_i, xf, sg_for, om, np, report):
    """One Maya mesh under transform xf from every triangle primitive of glTF mesh mesh_i,
    each primitive's faces in its material's shading group. Returns the triangle count."""
    pos, nrm, uvs, idx, ranges = [], [], [], [], []
    base = faces = 0
    for prim in gl.meshes[mesh_i].get("primitives", []):
        if prim.get("mode", 4) != 4 or "POSITION" not in prim["attributes"]:
            report.append("%s: skipped a primitive that isn't triangles" % xf)
            continue
        a = prim["attributes"]
        p = gl.accessor(a["POSITION"]).astype(np.float64) * 100.0
        n = len(p)
        pos.append(p)
        nrm.append(gl.accessor(a["NORMAL"]).astype(np.float64) if "NORMAL" in a else None)
        uvs.append(gl.accessor(a["TEXCOORD_0"]).astype(np.float64) if "TEXCOORD_0" in a else np.zeros((n, 2)))
        ix = gl.accessor(prim["indices"]).reshape(-1).astype(np.int64) if "indices" in prim else np.arange(n)
        idx.append(ix + base)
        nf = len(ix) // 3
        ranges.append((faces, faces + nf - 1, prim.get("material")))
        base += n
        faces += nf
    if not faces:
        return 0
    p = np.concatenate(pos)
    uv = np.concatenate(uvs)
    ix = np.concatenate(idx)
    sel = om.MSelectionList()
    sel.add(xf)
    fn = om.MFnMesh()
    shape = fn.create(om.MFloatPointArray(p.tolist()), om.MIntArray([3] * faces),
                      om.MIntArray(ix.tolist()), parent=sel.getDependNode(0))
    fn.setUVs(om.MFloatArray(uv[:, 0].tolist()), om.MFloatArray((1.0 - uv[:, 1]).tolist()))
    fn.assignUVs(om.MIntArray([3] * faces), om.MIntArray(ix.tolist()))
    if all(n is not None for n in nrm):
        fn.setVertexNormals(om.MVectorArray(np.concatenate(nrm).tolist()), om.MIntArray(range(len(p))))
    om.MFnDependencyNode(shape).setName(xf.split("|")[-1] + "Shape")
    shape_path = cmds.listRelatives(xf, shapes=True, fullPath=True)[0]
    for f0, f1, mi in ranges:
        sg = "initialShadingGroup" if mi is None else sg_for(mi)
        comp = shape_path if len(ranges) == 1 else "%s.f[%d:%d]" % (shape_path, f0, f1)
        cmds.sets(comp, edit=True, forceElement=sg)
    return faces


def is_fresh(glb_path, out_dir):
    info = os.path.join(out_dir, "build.json")
    if not (os.path.isfile(info) and os.path.isfile(os.path.join(out_dir, "car.mb"))):
        return False
    try:
        with open(info, encoding="utf-8") as fh:
            b = json.load(fh)
        st = os.stat(glb_path)
        return (b.get("builder") == BUILDER_VERSION and b.get("size") == st.st_size
                and b.get("mtime_ns") == st.st_mtime_ns
                and os.path.normcase(b.get("source", "")) == os.path.normcase(os.path.abspath(glb_path)))
    except (OSError, ValueError):
        return False


_CHILD = r"""
import os, sys, traceback
sys.path.insert(0, sys.argv[1])
import maya.standalone
maya.standalone.initialize(name="python")
code = 1
try:
    from driving_rig import carmodel
    info = carmodel.build_scene(sys.argv[2], sys.argv[3])
    print("DRIVING_RIG_CAR_BUILT %s" % info["triangles"])
    code = 0
except Exception:
    traceback.print_exc()
sys.stdout.flush()
sys.stderr.flush()
os._exit(code)
"""


def mayapy():
    here = os.path.dirname(sys.executable)
    for n in ("mayapy.exe", "mayapy"):
        p = os.path.join(here, n)
        if os.path.isfile(p):
            return p
    raise CarModelError("Can't find mayapy next to %s" % sys.executable)


def build_cache(glb_path, out_dir, progress=None):
    """Build out_dir from glb_path in a separate mayapy (your scene stays as it is). Returns
    build.json's contents. progress(seconds) is called while it runs; return False to cancel."""
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)
    log = os.path.join(out_dir, "build.log")
    pkg_parent = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    env = dict(os.environ)
    env["MAYA_SKIP_USERSETUP_PY"] = "1"           # the menu-building startup block has no UI here
    kw = {}
    if os.name == "nt":
        kw["creationflags"] = 0x08000000                     # CREATE_NO_WINDOW
    t0 = time.time()
    with open(log, "w", encoding="utf-8") as out:
        proc = subprocess.Popen([mayapy(), "-c", _CHILD, pkg_parent, glb_path, out_dir],
                                stdout=out, stderr=subprocess.STDOUT, env=env, **kw)
        while proc.poll() is None:
            time.sleep(0.25)
            if progress is not None and progress(time.time() - t0) is False:
                proc.kill()
                raise CarModelError("Cancelled.")
    if proc.returncode != 0 or not is_fresh(glb_path, out_dir):
        with open(log, encoding="utf-8", errors="replace") as fh:
            tail = fh.read()[-1500:]
        raise CarModelError("Building the car model failed (log: %s):\n%s" % (log, tail))
    with open(os.path.join(out_dir, "build.json"), encoding="utf-8") as fh:
        return json.load(fh)


# === one click: load / unload for a take ========================================

def car_namespace(rig_ns):
    return rig_ns + "_car"


def find_car(root):
    """(reference node, top group) of the car loaded for this rig, or (None, None)."""
    ns = car_namespace(namespace_of(root))
    for rn in cmds.ls(type="reference") or []:
        try:
            if cmds.referenceQuery(rn, namespace=True).lstrip(":") != ns:
                continue
        except RuntimeError:
            continue
        tops = [n for n in (cmds.referenceQuery(rn, nodes=True, dagPath=True) or [])
                if cmds.attributeQuery(CAR_ATTR, node=n, exists=True)]
        return rn, (cmds.ls(tops[0], long=True)[0] if tops else None)
    return None, None


def load_for_take(root=None, progress=None, verbose=True):
    """Build the cache if it's stale, reference the car, line it up with the bind car and
    attach it to the take. Returns the car's top group."""
    from . import bind
    root = find_rig_root(root)
    if not root:
        raise CarModelError("Select a Driving Rig (any node of it) first.")
    if find_car(root)[0]:
        raise CarModelError("This take already has its car model loaded.\n"
                            "Use Unload Car Model first to load it again.")
    if bind.attached_parts(root):
        raise CarModelError("A model is already attached to this rig - detach it first.")
    glb, profile = source_for_meta(bind._meta_for(root))
    out = cache_dir(profile)
    built = None
    if not is_fresh(glb, out):
        if verbose:
            print("Driving Rig: building the %s car model from %s (first time only)..." % (profile, glb))
        built = build_cache(glb, out, progress)
    bind_root = bind.find_bind_car(root) or bind.create_bind_car(root)
    ns = car_namespace(namespace_of(root))
    new = cmds.file(os.path.join(out, "car.mb"), reference=True, namespace=ns,
                    returnNewNodes=True, mergeNamespacesOnClash=False) or []
    tops = [n for n in cmds.ls(new, type="transform", long=True) or []
            if cmds.attributeQuery(CAR_ATTR, node=n, exists=True)]
    if not tops:
        raise CarModelError("The cached car has no %s group: %s" % (TOP, out))
    with scene_units():
        top = put_in_world(tops[0])
        # the model is in the bind car's frame: put it where the bind car is
        cmds.xform(top, worldSpace=True, matrix=cmds.getAttr(bind_root + ".worldMatrix[0]"))
    top = cmds.ls(top, long=True)[0]
    bind.attach_model(top, root)
    if verbose:
        print("Driving Rig: %s car model on %s%s" % (profile, root.split("|")[-1],
              " (built in %ss)" % built["seconds"] if built else ""))
    cmds.select(root)
    return cmds.ls(top, long=True)[0]


def unload_for_take(root=None):
    """Detach the take's car model and remove its reference. Returns True if there was one."""
    from . import bind
    root = find_rig_root(root)
    if not root:
        raise CarModelError("Select a Driving Rig (any node of it) first.")
    rn, _top = find_car(root)
    if not rn:
        return False
    if bind.attached_parts(root):
        bind.detach_model(root)
    path = cmds.referenceQuery(rn, filename=True)
    cmds.file(path, removeReference=True)
    return True

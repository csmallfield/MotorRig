"""Import a take onto a proxy rig (spec 3.1-3.3), re-solve spin from the scene, check it.

    from driving_rig import importer
    root = importer.import_take(r"D:/takes/hero_pass_A.json.gz", fps=24, in_frame=1001)
    importer.resolve_spin(root)      # after retiming / offsetting the car
    importer.check_spin(root)        # effective-radius diagnostic

Not undoable as a whole (keys are written through the API for speed) - use
delete_rig(root) to remove an import; everything lives in its own namespace.
"""
from __future__ import annotations

import math
import os

from maya import cmds

import maya.api.OpenMaya as om

from . import __version__, bake, mathutil as mu, rig, scene_io, take_io
from .mayautil import (RIG_ATTR, SCENE_ATTR, add_attr, all_rig_roots, all_scene_roots, exact_fps,
                       find_rig_root, mtime_unit, namespace_of, put_in_world, scene_units,
                       set_scene_fps, world_matrix, write_curve)
from .take_io import WHEELS


def take_stem(path):
    b = os.path.basename(path)
    for ext in (".json.gz", ".json"):
        if b.endswith(ext):
            return b[: -len(ext)]
    return os.path.splitext(b)[0]


def import_take(path, fps=24.0, in_frame=1001, name=None, set_fps=True, set_range=True,
                camera=True, contacts=True, solve=True, all_cameras=True, steering_wheel=True,
                world_scale=None, verbose=True):
    """Build a rig for the take at `path` and key it. Returns the rig root node.
    world_scale: set DrivingRig_world.worldScale (None = leave it as it is)."""
    take = take_io.load(path)
    rate = exact_fps(fps)
    b = bake.bake(take, fps=rate, in_frame=in_frame, solve=solve)
    unit = mtime_unit(fps)
    frames = b.frames
    name = name or take_stem(path)

    with scene_units():
        if set_fps:
            set_scene_fps(fps)
        ns = rig.unique_namespace(name)
        cam_names = [c["name"] for c in b.cameras] if all_cameras else []
        nodes = rig.build(take.meta, ns, camera=camera and b.camera is not None,
                          contacts=contacts, version=__version__, camera_names=cam_names,
                          steering=b.steering if steering_wheel else None)
        root = nodes["root"]
        ch = nodes["chassis"]

        def key(node, attr, values, tangent="auto"):
            write_curve(node, attr, frames, values, tangent, unit)

        for k, ax in enumerate("XYZ"):
            key(ch, "translate" + ax, b.chassis_t[k])
            key(ch, "rotate" + ax, b.chassis_r[k])
        for w in WHEELS:
            n = nodes["wheels"][w]
            d = b.wheels[w]
            key(n["steer"], "rotateY", d["steer_ry"])
            key(n["susp"], "translateY", d["susp_ty"])
            key(n["spin"], "rotateX", d["spin_rx"], "linear")          # monotonic: linear
            key(n["spin"], "drvSpinRecorded", d["spin_recorded"], "linear")
            key(n["spin"], "drvSlipDistance", d["slip_distance"], "linear")
            if "contact" in n:
                loc = n["contact"]
                for k, ax in enumerate("XYZ"):
                    key(loc, "translate" + ax, d["contact_t"][k], "linear")
                key(loc, "grounded", d["grounded"], "step")
                key(loc, "slipLong", d["slip_long"])
                key(loc, "slipLat", d["slip_lat"])
        if "steering" in nodes:
            key(nodes["steering"], "rotateZ", b.steering["angle"])
        for (cam_t, cam_s), c in zip(nodes.get("cams", []), b.cameras):
            for k, ax in enumerate("XYZ"):
                key(cam_t, "translate" + ax, c["t"][k])
                key(cam_t, "rotate" + ax, c["r"][k])
            key(cam_s, "focalLength", c["focal"])
        if b.active_camera is not None:
            names = [c["name"] for c in b.cameras] or list(take.meta.get("camera_names", []))
            if names:
                cmds.addAttr(root, longName="activeCamera", attributeType="enum",
                             enumName=":".join(["none"] + names), keyable=True)
                key(root, "activeCamera", [int(v) + 1 for v in b.active_camera], "step")
        if "camera" in nodes:
            cam = nodes["camera"]
            for k, ax in enumerate("XYZ"):
                key(cam, "translate" + ax, b.camera["t"][k])
                key(cam, "rotate" + ax, b.camera["r"][k])
            key(nodes["camera_shape"], "focalLength", b.camera["focal"])

        add_attr(root, "drvTakePath", os.path.abspath(path), "string")
        add_attr(root, "drvTakeName", name, "string")
        add_attr(root, "drvFps", float(fps))
        add_attr(root, "drvInFrame", float(in_frame))
        add_attr(root, "drvOutFrame", float(in_frame) + round(take.duration * rate, 3))
        add_attr(root, "drvWheelRadius", float(take.meta["wheel_radius"]) * take.unit_scale)
        add_attr(root, "drvUnitScale", take.unit_scale)
        add_attr(root, "drvSpinMode", "solved" if solve else "recorded", "string")
        add_attr(root, "drvCollisionSource", str(take.meta.get("collision_source", "")), "string")
        if set_range:
            cmds.playbackOptions(minTime=frames[0], maxTime=frames[-1],
                                 animationStartTime=frames[0], animationEndTime=frames[-1])
        root = put_in_world(root, world_scale)

    report = _format_report(name, b.spin_report, b.radius_warn)
    warn = _ground_mismatch(str(take.meta.get("collision_source", "")), SCENE_ATTR)
    if warn:
        report += "\n" + warn
    add_attr(root, "drvLastCheck", report, "string")
    if verbose:
        print("Driving Rig: imported %s -> %s  (%d frames @ %s fps, IN %d, OUT %.0f, handles %d/%d)"
              % (os.path.basename(path), root, len(frames), fps, in_frame,
                 cmds.getAttr(root + ".drvOutFrame"), in_frame - frames[0],
                 frames[-1] - cmds.getAttr(root + ".drvOutFrame")))
        print(report)
    cmds.select(root)
    return root


def _rig_nodes(root):
    ns = namespace_of(root)
    w = {}
    for name in WHEELS:
        w[name] = {k: "%s:wheel_%s_%s" % (ns, name, k) for k in ("steer", "susp", "spin")}
        loc = "%s:contact_%s" % (ns, name)
        if cmds.objExists(loc):
            w[name]["contact"] = loc
    return ns, "%s:chassis" % ns, w


def _frame_range(chassis):
    ks = cmds.keyframe(chassis, query=True, timeChange=True) or []
    if not ks:
        raise RuntimeError("%s has no animation" % chassis)
    return list(range(int(math.ceil(min(ks) - 1e-6)), int(math.floor(max(ks) + 1e-6)) + 1))


def _sample_scene(root):
    """Per wheel, per frame: world wheel centre, wheel forward (post-steer, pre-spin),
    the keyed slip distance and recorded spin, grounded/slip flags - all evaluated from the
    scene, so animator retimes, root offsets and constraints are respected."""
    ns, chassis, wheels = _rig_nodes(root)
    frames = _frame_range(chassis)
    out = {}
    for name, n in wheels.items():
        c, f, sd, rec, gr, sl = [], [], [], [], [], []
        scale = 1.0
        for fr in frames:
            ms = world_matrix(n["susp"], fr)
            mt = world_matrix(n["steer"], fr)
            c.append((ms[12], ms[13], ms[14]))
            f.append((-mt[8], -mt[9], -mt[10]))
            scale = mu.v_len((ms[4], ms[5], ms[6]))
            sd.append(cmds.getAttr(n["spin"] + ".drvSlipDistance", time=fr))
            rec.append(cmds.getAttr(n["spin"] + ".drvSpinRecorded", time=fr))
            if "contact" in n:
                gr.append(bool(cmds.getAttr(n["contact"] + ".grounded", time=fr)))
                sl.append(cmds.getAttr(n["contact"] + ".slipLong", time=fr))
        out[name] = {"centers": c, "forwards": f, "slip_distance": sd, "recorded": rec,
                     "grounded": gr or [True] * len(frames), "slip_long": sl or [0.0] * len(frames),
                     "world_scale": scale}
    return frames, wheels, out


def resolve_spin(root=None, verbose=True):
    """Spec 3.3 re-solve: rebuild every wheel's spin from its travel in the scene plus the
    keyed slip distance. Run after retiming or offsetting the car."""
    root = find_rig_root(root)
    if not root:
        raise RuntimeError("Select a Driving Rig (any node of it) first.")
    with scene_units():
        radius = cmds.getAttr(root + ".drvWheelRadius")
        frames, wheels, data = _sample_scene(root)
        reports = {}
        for name, d in data.items():
            r = radius * d["world_scale"]     # a scaled root scales the wheels too
            spin = bake.solve_spin(d["centers"], d["forwards"],
                                   [x * d["world_scale"] for x in d["slip_distance"]], d["recorded"][0], r)
            write_curve(wheels[name]["spin"], "rotateX", frames, [-a for a in spin], "linear")
            reports[name] = bake.spin_check(d["centers"], d["forwards"], d["recorded"], d["grounded"],
                                            d["slip_long"], r, solved=spin)
    cmds.setAttr(root + ".drvSpinMode", "solved", type="string")
    warn = [w for w, rp in reports.items() if not abs(rp["radius_error_percent"]) <= bake.RADIUS_WARN_PERCENT]
    report = _format_report(cmds.getAttr(root + ".drvTakeName"), reports, warn, "Re-solved")
    cmds.setAttr(root + ".drvLastCheck", report, type="string")
    if verbose:
        print(report)
    return reports


def check_spin(root=None, verbose=True):
    """Effective-radius diagnostic against the scene as it is now (nothing is changed)."""
    root = find_rig_root(root)
    if not root:
        raise RuntimeError("Select a Driving Rig (any node of it) first.")
    with scene_units():
        radius = cmds.getAttr(root + ".drvWheelRadius")
        frames, wheels, data = _sample_scene(root)
        reports = {}
        for name, d in data.items():
            r = radius * d["world_scale"]
            current = [-math.radians(cmds.getAttr(wheels[name]["spin"] + ".rotateX", time=f)) for f in frames]
            reports[name] = bake.spin_check(d["centers"], d["forwards"], d["recorded"], d["grounded"],
                                            d["slip_long"], r, solved=current)
    warn = [w for w, rp in reports.items() if not abs(rp["radius_error_percent"]) <= bake.RADIUS_WARN_PERCENT]
    report = _format_report(cmds.getAttr(root + ".drvTakeName"), reports, warn, "Check")
    if verbose:
        print(report)
    return reports


# === scene geometry =========================================================

def import_scene(path, name=None, world_scale=None, verbose=True):
    """Build the exported scene (scene.json + OBJs) in Maya, in the takes' space: world,
    centimetres, Y-up (rotated for Z-up scenes). Meshes are created through the API from our
    own reader, so the result doesn't depend on OBJ-importer unit settings. Returns the group."""
    scene = scene_io.load(path)
    base = name or scene.name
    with scene_units():
        ns = rig.unique_namespace(base)
        grp = cmds.createNode("transform", name="%s:scene_root" % ns, skipSelect=True)
        add_attr(grp, SCENE_ATTR, __version__, "string")
        add_attr(grp, "drvCollisionSource", scene.collision_source, "string")
        add_attr(grp, "drvScenePath", scene.folder, "string")
        if cmds.upAxis(query=True, axis=True) == "z":
            cmds.setAttr(grp + ".rotateX", 90.0)
        for obj in scene.objects:
            _build_mesh(obj, ns, grp)
        grp = put_in_world(grp, world_scale)
    lines = ["Imported scene %s - %d objects (%s)" % (base, len(scene.objects), ", ".join(
        "%s%s" % (o.name, "" if o.collides else " [visual only]") for o in scene.objects))]
    warn = _ground_mismatch(scene.collision_source, RIG_ATTR)
    if warn:
        lines.append(warn)
    report = "\n".join(lines)
    add_attr(grp, "drvLastCheck", report, "string")
    if verbose:
        print(report)
    return grp


def _array(cls, seq):
    try:
        return cls(seq)
    except (TypeError, ValueError):   # older API builds: no sequence constructor
        a = cls()
        for x in seq:
            a.append(x)
        return a


def _build_mesh(obj, ns, grp):
    pts = _array(om.MPointArray, [om.MPoint(p[0], p[1], p[2]) for p in obj.points])   # internal units: cm
    counts = _array(om.MIntArray, [3] * len(obj.faces))
    connects = _array(om.MIntArray, [i for f in obj.faces for i in f])
    fn = om.MFnMesh()
    tobj = fn.create(pts, counts, connects)
    tr = cmds.rename(om.MFnDependencyNode(tobj).name(), "%s:%s" % (ns, obj.name))
    tr = cmds.parent(tr, grp, relative=True)[0]
    cmds.polySoftEdge(tr, angle=60.0, constructionHistory=False)
    sh = cmds.shadingNode("lambert", asShader=True, name="%s:%s_mat" % (ns, obj.name))
    cmds.setAttr(sh + ".color", obj.color[0], obj.color[1], obj.color[2], type="double3")
    sg = cmds.sets(renderable=True, noSurfaceShader=True, empty=True, name="%s:%s_SG" % (ns, obj.name))
    cmds.connectAttr(sh + ".outColor", sg + ".surfaceShader")
    cmds.sets(tr, edit=True, forceElement=sg)
    add_attr(tr, "drvCollides", obj.collides, "bool")
    return tr


def _find_scene_root(node=None):
    if node is None:
        sel = cmds.ls(selection=True, long=True) or []
        node = sel[0] if sel else None
    while node:
        if cmds.attributeQuery(SCENE_ATTR, node=node, exists=True):
            return node
        parents = cmds.listRelatives(node, parent=True, fullPath=True)
        node = parents[0] if parents else None
    return None


def _ground_mismatch(source, other_attr):
    """Compare a ground source with the rigs (or scenes) already in the file."""
    others = [n for n in (cmds.ls(type="transform", long=True) or [])
              if cmds.attributeQuery(other_attr, node=n, exists=True)
              and cmds.attributeQuery("drvCollisionSource", node=n, exists=True)]
    bad = sorted({cmds.getAttr(n + ".drvCollisionSource") for n in others} - {source})
    if not bad:
        return ""
    kind = "scene geometry" if other_attr == SCENE_ATTR else "take rigs"
    return ("! Ground mismatch: this was made on '%s' but %s in this file use '%s'. "
            "Wheels will float or sink by the difference." % (source, kind, "', '".join(bad)))


def delete_rig(root=None):
    """Delete a take rig or an imported scene (whichever the selection belongs to)."""
    root = find_rig_root(root) or _find_scene_root(root)
    if not root:
        return False
    ns = namespace_of(root)
    cmds.namespace(removeNamespace=":" + ns, deleteNamespaceContent=True)
    return True


def list_rigs():
    return all_rig_roots()


def _format_report(name, reports, warn, title="Imported"):
    lines = ["%s %s - spin check (effective radius from clean rolling frames):" % (title, name)]
    for w in WHEELS:
        r = reports.get(w)
        if not r:
            continue
        lines.append("  %s  r %.3f -> eff %.3f  (%+.2f%%)  drift vs recorded %.2f deg  %.1f rev%s" % (
            w, r["radius"], r["radius_effective"], r["radius_error_percent"],
            r.get("max_drift_deg", float("nan")), r["revolutions"], "   !" if w in warn else ""))
    if warn:
        lines.append("  ! %s: effective radius differs by > %.1f%% - check wheel radius, rig scale, or "
                     "contact offsets." % (", ".join(warn), bake.RADIUS_WARN_PERCENT))
    return "\n".join(lines)

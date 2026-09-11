"""Thin Maya helpers. Everything Maya-specific that isn't rig layout lives here.

Units: keys are written with MFnAnimCurve.addKeys, which takes Maya's *internal* units
(centimetres, radians) whatever the scene's UI units are. Everything done through cmds runs
inside :class:`scene_units`, which sets cm / degrees for the duration and restores the
user's settings afterwards — so a scene set to metres gets the same car.
"""
from __future__ import annotations

import maya.api.OpenMaya as om
import maya.api.OpenMayaAnim as oma
from maya import cmds

RIG_ATTR = "drvRig"
SCENE_ATTR = "drvScene"
WORLD = "DrivingRig_world"

TANGENT = {
    "auto": oma.MFnAnimCurve.kTangentAuto,
    "linear": oma.MFnAnimCurve.kTangentLinear,
    "step": oma.MFnAnimCurve.kTangentStep,
}

# fps → Maya time unit name (cmds.currentUnit(time=...)).
TIME_UNITS = {
    23.976: "23.976fps", 24.0: "film", 25.0: "pal", 29.97: "29.97fps", 30.0: "ntsc",
    47.952: "47.952fps", 48.0: "show", 50.0: "palf", 59.94: "59.94fps", 60.0: "ntscf",
}
FPS_CHOICES = [23.976, 24.0, 25.0, 29.97, 30.0, 48.0, 50.0, 60.0]

# NTSC-family labels are the exact rational rates.
EXACT_FPS = {23.976: 24000.0 / 1001.0, 29.97: 30000.0 / 1001.0, 47.952: 48000.0 / 1001.0, 59.94: 60000.0 / 1001.0}

# fps → MTime unit, so keys land exactly on Maya's frames (no float-seconds rounding).
_MTIME_UNIT = {
    23.976: "k23_976FPS", 24.0: "kFilm", 25.0: "kPALFrame", 29.97: "k29_97FPS", 30.0: "kNTSCFrame",
    47.952: "k47_952FPS", 48.0: "kShowScan", 50.0: "kPALField", 59.94: "k59_94FPS", 60.0: "kNTSCField",
}


def exact_fps(fps):
    return EXACT_FPS.get(round(float(fps), 3), float(fps))


def mtime_unit(fps):
    """MTime unit enum for a frame rate (falls back to the scene's UI unit)."""
    name = _MTIME_UNIT.get(round(float(fps), 3))
    return getattr(om.MTime, name) if name and hasattr(om.MTime, name) else om.MTime.uiUnit()


class scene_units(object):
    """Context manager: linear cm + angle degrees while building, restored afterwards."""

    def __enter__(self):
        self._lin = cmds.currentUnit(query=True, linear=True)
        self._ang = cmds.currentUnit(query=True, angle=True)
        cmds.currentUnit(linear="cm")
        cmds.currentUnit(angle="deg")
        return self

    def __exit__(self, *exc):
        cmds.currentUnit(linear=self._lin)
        cmds.currentUnit(angle=self._ang)
        return False


def set_scene_fps(fps):
    unit = TIME_UNITS.get(round(float(fps), 3))
    if unit is None:
        raise ValueError("No Maya time unit for %s fps (choose one of %s)" % (fps, FPS_CHOICES))
    cmds.currentUnit(time=unit)


def scene_fps():
    """Current scene frame rate as a float."""
    return om.MTime(1.0, om.MTime.kSeconds).asUnits(om.MTime.uiUnit())


def plug(node_attr):
    sel = om.MSelectionList()
    sel.add(node_attr)
    return sel.getPlug(0)


def write_curve(node, attr, frames, values, tangent="auto", unit=None):
    """Replace any animation on node.attr with one key per (frames[i], values[i]).
    `unit` is an MTime unit (see mtime_unit); default the scene's. Values in internal units
    (cm, radians, or plain numbers). Bulk addKeys — not cmds.setKeyframe in a loop
    (seconds vs minutes on a rig this size)."""
    na = "%s.%s" % (node, attr)
    cmds.cutKey(na, clear=True)
    p = plug(na)
    u = om.MTime.uiUnit() if unit is None else unit
    times = om.MTimeArray()
    for f in frames:
        times.append(om.MTime(float(f), u))
    vals = om.MDoubleArray()
    for v in values:
        vals.append(float(v))
    fn = oma.MFnAnimCurve()
    obj = fn.create(p)
    t = TANGENT[tangent]
    fn.addKeys(times, vals, t, t)
    # Name the curve into the rig's namespace, so deleting the namespace takes the
    # animation with it and "all curves of this rig" is one ls() away.
    short = node.split("|")[-1]
    ns = short.rsplit(":", 1)[0] if ":" in short else ""
    if ns:
        base = short.rsplit(":", 1)[1]
        cmds.rename(om.MFnDependencyNode(obj).name(), "%s:%s_%s" % (ns, base, attr))
    return fn


def rig_curves(ns):
    return cmds.ls("%s:*" % ns, type="animCurve") or []


def add_attr(node, name, value=None, kind="double", keyable=False):
    if not cmds.attributeQuery(name, node=node, exists=True):
        if kind == "string":
            cmds.addAttr(node, longName=name, dataType="string")
        else:
            cmds.addAttr(node, longName=name, attributeType=kind, keyable=keyable)
    if value is not None:
        if kind == "string":
            cmds.setAttr("%s.%s" % (node, name), value, type="string")
        else:
            cmds.setAttr("%s.%s" % (node, name), value)


def find_rig_root(node=None):
    """Walk up from `node` (default: first selected) to the rig root (has drvRig)."""
    if node is None:
        sel = cmds.ls(selection=True, long=True) or []
        if not sel:
            return None
        node = sel[0]
    node = cmds.ls(node, long=True)[0]
    while node:
        if cmds.attributeQuery(RIG_ATTR, node=node, exists=True):
            return node
        parents = cmds.listRelatives(node, parent=True, fullPath=True)
        node = parents[0] if parents else None
    return None


def world_group(scale=None):
    """The shared world-scale group every rig and scene lives under. One attribute,
    `worldScale`, drives uniform scale - change it any time (1.0 = true size in cm;
    0.1 = one unit per 10 cm). Created on first use; adopts rigs/scenes from older imports."""
    if not cmds.objExists(WORLD):
        cmds.createNode("transform", name=WORLD, skipSelect=True)
        cmds.addAttr(WORLD, longName="worldScale", attributeType="double", defaultValue=1.0,
                     minValue=0.0001, keyable=True)
        for ax in "XYZ":
            cmds.connectAttr(WORLD + ".worldScale", WORLD + ".scale" + ax)
            cmds.setAttr(WORLD + ".scale" + ax, keyable=False, channelBox=False)
        for n in all_rig_roots() + all_scene_roots():
            if not cmds.listRelatives(n, parent=True):
                cmds.parent(n, WORLD, relative=True)
    if scale is not None:
        cmds.setAttr(WORLD + ".worldScale", float(scale))
    return WORLD


def put_in_world(node, scale=None):
    """Parent `node` under the world group (creating it if needed) and return its name.
    Creating the group adopts every loose rig/scene - which can include `node` itself - and
    Maya's parent() returns None for "already a child", so check instead of assuming."""
    grp = world_group(scale)
    parents = cmds.listRelatives(node, parent=True) or []
    if parents and parents[0] == grp:
        return node
    return cmds.parent(node, grp, relative=True)[0]


def get_world_scale():
    return cmds.getAttr(WORLD + ".worldScale") if cmds.objExists(WORLD) else None


def all_scene_roots():
    return [n for n in (cmds.ls(type="transform", long=True) or [])
            if cmds.attributeQuery(SCENE_ATTR, node=n, exists=True)]


def all_rig_roots():
    return [n for n in (cmds.ls(type="transform", long=True) or [])
            if cmds.attributeQuery(RIG_ATTR, node=n, exists=True)]


def namespace_of(node):
    short = node.split("|")[-1]
    return short.rsplit(":", 1)[0] if ":" in short else ""


def world_matrix(node, frame):
    """Flat 16-float world matrix (row-major, translation in [12:15]) evaluated at `frame`."""
    return cmds.getAttr("%s.worldMatrix[0]" % node, time=frame)

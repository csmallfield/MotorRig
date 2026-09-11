"""Spec 3.1 — build the proxy rig from a take's `meta` alone (no mesh export).

    ns:root                       offset control — move/rotate the whole take from here
      ns:chassis                  animated: translate + rotate (rotate order zxy)
        ns:body_geo, ns:nose_geo
        ns:wheel_FL_steer         at the hardpoint; animated rotateY (steer)
          ns:wheel_FL_susp        animated translateY (suspension)
            ns:wheel_FL_spin      animated rotateX (spin); keeps drvSpinRecorded / drvSlipDistance
              ns:wheel_FL_geo     cylinder along X
        … ×4 (FL FR RL RR)
      ns:contacts
        ns:contact_FL             world contact point + grounded / slipLong / slipLat (FX triggers)
      ns:take_cam                 the take's recorded camera (optional)

Call inside mayautil.scene_units() (cm / degrees).
"""
from __future__ import annotations

from maya import cmds

from . import mathutil as mu
from .mayautil import RIG_ATTR, add_attr
from .take_io import WHEELS


def _named(node, ns, name):
    return cmds.rename(node, "%s:%s" % (ns, name))


def _group(ns, name, parent=None):
    kw = {"name": "%s:%s" % (ns, name), "skipSelect": True}
    if parent:
        kw["parent"] = parent
    return cmds.createNode("transform", **kw)


def _parent(child, parent):
    return cmds.parent(child, parent, relative=True)[0]


def unique_namespace(base):
    base = "".join(c if c.isalnum() or c == "_" else "_" for c in base) or "take"
    if base[0].isdigit():
        base = "t" + base
    ns = "drv_" + base
    k = 2
    while cmds.namespace(exists=":" + ns):
        ns = "drv_%s_%d" % (base, k)
        k += 1
    cmds.namespace(add=ns, parent=":")
    return ns


def build(meta, ns, camera=True, contacts=True, version="dev", camera_names=(), steering=None):
    s = float(meta.get("unit_scale", 100.0))
    ext = meta["body"]["extents"]
    r = float(meta["wheel_radius"]) * s
    width = float(meta["wheel_width"]) * s
    susp_rest = float(meta["susp_rest"]) * s
    names = meta.get("wheel_order", list(WHEELS))
    nodes = {"wheels": {}}

    root = _group(ns, "root")
    nodes["root"] = root
    add_attr(root, RIG_ATTR, version, "string")
    if cmds.upAxis(query=True, axis=True) == "z":
        cmds.setAttr(root + ".rotateX", 90.0)   # take is Y-up

    chassis = _group(ns, "chassis", root)
    cmds.setAttr(chassis + ".rotateOrder", mu.ROTATE_ORDER_ZXY)
    nodes["chassis"] = chassis

    body = cmds.polyCube(width=ext[0] * s, height=ext[1] * s, depth=ext[2] * s,
                         constructionHistory=False)[0]
    body = _parent(_named(body, ns, "body_geo"), chassis)
    nose = cmds.polyCube(width=ext[0] * s * 0.8, height=12.0, depth=12.0, constructionHistory=False)[0]
    nose = _parent(_named(nose, ns, "nose_geo"), chassis)
    cmds.setAttr(nose + ".translate", 0.0, ext[1] * s * 0.5 - 6.0, -ext[2] * s * 0.5 + 2.0)

    for i, w in enumerate(names):
        hp = meta["hardpoints"][i]
        steer = _group(ns, "wheel_%s_steer" % w, chassis)
        cmds.setAttr(steer + ".translate", hp[0] * s, hp[1] * s, hp[2] * s)
        susp = _group(ns, "wheel_%s_susp" % w, steer)
        cmds.setAttr(susp + ".translateY", -susp_rest)
        spin = _group(ns, "wheel_%s_spin" % w, susp)
        add_attr(spin, "drvSpinRecorded", kind="double", keyable=True)
        add_attr(spin, "drvSlipDistance", kind="double", keyable=True)
        geo = cmds.polyCylinder(radius=r, height=width, axis=(1, 0, 0), subdivisionsAxis=24,
                                subdivisionsCaps=1, constructionHistory=False)[0]
        geo = _parent(_named(geo, ns, "wheel_%s_geo" % w), spin)
        nodes["wheels"][w] = {"steer": steer, "susp": susp, "spin": spin, "geo": geo}

    if contacts:
        grp = _group(ns, "contacts", root)
        for w in names:
            loc = cmds.spaceLocator()[0]
            loc = _parent(_named(loc, ns, "contact_%s" % w), grp)
            for ax in "XYZ":
                cmds.setAttr("%s.localScale%s" % (loc, ax), 6.0)
            add_attr(loc, "grounded", kind="bool", keyable=True)
            add_attr(loc, "slipLong", kind="double", keyable=True)
            add_attr(loc, "slipLat", kind="double", keyable=True)
            nodes["wheels"][w]["contact"] = loc

    if steering:
        nodes["steering"] = _steering_wheel(ns, chassis, steering)

    if camera_names:
        grp = _group(ns, "cameras", root)
        nodes["cams"] = [_camera(ns, "cam_%s" % n, grp) for n in camera_names]

    if camera:
        cam, shape = cmds.camera()
        cam = _parent(_named(cam, ns, "take_cam"), root)
        shape = cmds.rename(cmds.listRelatives(cam, shapes=True, fullPath=True)[0], "%s:take_camShape" % ns)
        cmds.setAttr(cam + ".rotateOrder", mu.ROTATE_ORDER_ZXY)
        cmds.setAttr(shape + ".filmFit", 2)                  # vertical: Godot fov is vertical
        cmds.setAttr(shape + ".horizontalFilmAperture", 1.417)
        cmds.setAttr(shape + ".verticalFilmAperture", 0.945)
        cmds.setAttr(shape + ".nearClipPlane", 1.0)
        cmds.setAttr(shape + ".farClipPlane", 200000.0)
        nodes["camera"] = cam
        nodes["camera_shape"] = shape
    return nodes


def _camera(ns, name, parent):
    cam, shape = cmds.camera()
    cam = _parent(_named(cam, ns, name), parent)
    shape = cmds.rename(cmds.listRelatives(cam, shapes=True, fullPath=True)[0], "%s:%sShape" % (ns, name))
    cmds.setAttr(cam + ".rotateOrder", mu.ROTATE_ORDER_ZXY)
    cmds.setAttr(shape + ".filmFit", 2)
    cmds.setAttr(shape + ".horizontalFilmAperture", 1.417)
    cmds.setAttr(shape + ".verticalFilmAperture", 0.945)
    cmds.setAttr(shape + ".nearClipPlane", 1.0)
    cmds.setAttr(shape + ".farClipPlane", 200000.0)
    return cam, shape


def _steering_wheel(ns, chassis, st):
    """column (at the wheel centre, tilted back) -> steering_wheel (animated rotateZ; +Z points
    at the driver, so + = counter-clockwise from the seat = turning left) -> rim, spoke, marker."""
    column = _group(ns, "steering_column", chassis)
    cmds.setAttr(column + ".translate", *st["position_cm"])
    cmds.setAttr(column + ".rotateX", -st["tilt_deg"])
    wheel = _group(ns, "steering_wheel", column)
    r = st["radius_cm"]
    rim = cmds.polyTorus(radius=r, sectionRadius=1.6, subdivisionsAxis=32, subdivisionsHeight=8,
                         axis=(0, 0, 1), constructionHistory=False)[0]
    _parent(_named(rim, ns, "steering_rim_geo"), wheel)
    spoke = cmds.polyCube(width=2.0 * r, height=2.5, depth=2.0, constructionHistory=False)[0]
    _parent(_named(spoke, ns, "steering_spoke_geo"), wheel)
    mark = cmds.polyCube(width=3.5, height=5.0, depth=4.0, constructionHistory=False)[0]
    mark = _parent(_named(mark, ns, "steering_marker_geo"), wheel)
    cmds.setAttr(mark + ".translateY", r)
    return wheel

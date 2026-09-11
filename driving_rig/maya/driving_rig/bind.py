"""Put your own car model on a take rig.

    1. Import a take.
    2. create_bind_car(rig)       - a static copy of the rig at rest, in <ns>_bind:
                                    parked level at the origin, on its tyres at static ride
                                    height, wheels straight, steering centred.
    3. Place your model over it, organised in named groups (create_model_groups() makes them):
           chassis   wheel_FL   wheel_FR   wheel_RL   wheel_RR   [steering_wheel]
       Case, namespaces and a _grp / _geo suffix are ignored ("carA:Wheel_FL_GRP" counts).
    4. attach_model(model, rig)   - every group follows its part of the animated rig.
       detach_model(rig)          - puts everything back exactly as it was.

How attaching works: each group is parented under the animated node and the bind-to-model
offset goes into its offsetParentMatrix. The group's own translate/rotate/scale, pivots and
any animation are untouched, nothing is baked, and wheels spin about the rig's wheel centre
wherever your pivots are: line the geometry up with the bind car and that's all.
"""
from __future__ import annotations

import json
import os
import re

from maya import cmds

from . import __version__, bake, mathutil as mu, rig, take_io
from .mayautil import (add_attr, find_rig_root, namespace_of, put_in_world, scene_units)
from .take_io import WHEELS

BIND_ATTR = "drvBind"
# model group name -> node of the rig it follows
PARTS = [("chassis", "chassis")] + [("wheel_%s" % w, "wheel_%s_spin" % w) for w in WHEELS] + \
    [("steering_wheel", "steering_wheel")]
REQUIRED = ["chassis"] + ["wheel_%s" % w for w in WHEELS]
_SUFFIX = re.compile(r"(_?(grp|group|geo))$")


class BindError(RuntimeError):
    pass


def bind_namespace(rig_ns):
    return rig_ns + "_bind"


def _meta_for(root):
    if cmds.attributeQuery("drvMeta", node=root, exists=True):
        return json.loads(cmds.getAttr(root + ".drvMeta"))
    path = cmds.getAttr(root + ".drvTakePath")            # rigs imported before 0.8
    if not os.path.isfile(path):
        raise BindError("This rig was imported before 0.8 and its take is gone:\n%s\n"
                        "Re-import the take." % path)
    return take_io.load(path).meta


# === bind car ==================================================================

def create_bind_car(root=None):
    """Static, unanimated copy of the rig at rest. Returns its root (replaces an existing one)."""
    root = find_rig_root(root)
    if not root:
        raise BindError("Select a Driving Rig (any node of it) first.")
    ns = namespace_of(root)
    bns = bind_namespace(ns)
    meta = _meta_for(root)
    s = float(meta.get("unit_scale", 100.0))
    if cmds.namespace(exists=":" + bns):
        cmds.namespace(removeNamespace=":" + bns, deleteNamespaceContent=True)
    cmds.namespace(add=bns, parent=":")
    with scene_units():
        nodes = rig.build(meta, bns, camera=False, contacts=False, version=__version__,
                          steering=bake.steering_params(meta))
        broot = nodes["root"]
        cmds.deleteAttr(broot + "." + rig.RIG_ATTR)        # not a take rig: not listed, not re-solved
        add_attr(broot, BIND_ATTR, ns, "string")
        # at rest: each axle at its static compression, chassis level with the tyres on y = 0
        cf, cr = bake.static_compression(meta)
        rest, r = float(meta["susp_rest"]), float(meta["wheel_radius"])
        bottoms = []
        for i, w in enumerate(WHEELS):
            comp = cf if i < 2 else cr
            cmds.setAttr(nodes["wheels"][w]["susp"] + ".translateY", -(rest - comp) * s)
            bottoms.append(float(meta["hardpoints"][i][1]) - (rest - comp) - r)
        cmds.setAttr(nodes["chassis"] + ".translateY", -sum(bottoms) / 4.0 * s)
        # reference display: visible for snapping, not selectable by accident
        cmds.setAttr(broot + ".overrideEnabled", True)
        cmds.setAttr(broot + ".overrideDisplayType", 2)
        broot = put_in_world(broot)
    return broot


def find_bind_car(root):
    bns = bind_namespace(namespace_of(root))
    n = "%s:root" % bns
    return n if cmds.objExists(n) else None


def create_model_groups(root=None, name="car_model"):
    """Empty, correctly named groups at the bind car's parts - drop your geometry in them.
    Created at world level (identity), so each group's translate is its world position."""
    root = find_rig_root(root)
    if not root:
        raise BindError("Select a Driving Rig (any node of it) first.")
    bind = find_bind_car(root) or create_bind_car(root)
    bns = namespace_of(bind)
    with scene_units():
        top = cmds.createNode("transform", name=name, skipSelect=True)
        for part, node in PARTS:
            src = "%s:%s" % (bns, node)
            if not cmds.objExists(src):
                continue                                   # no steering wheel on older takes
            m = cmds.getAttr(src + ".worldMatrix[0]")
            g = cmds.createNode("transform", name=part, parent=top, skipSelect=True)
            cmds.setAttr(g + ".translate", m[12], m[13], m[14])
    cmds.select(top)
    return top


# === attach / detach =============================================================

def _clean(name):
    base = name.split("|")[-1].split(":")[-1].lower()
    return _SUFFIX.sub("", base)


def find_parts(model):
    """{part: node} for the named groups under `model` (or `model` itself). Raises BindError
    listing what's missing or ambiguous."""
    found = {}
    nodes = [cmds.ls(model, long=True)[0]] + \
        (cmds.listRelatives(model, allDescendents=True, type="transform", fullPath=True) or [])
    nodes.sort(key=lambda n: n.count("|"))                 # top-most first
    wanted = {p.lower(): p for p, _ in PARTS}
    dup = []
    for n in nodes:
        key = _clean(n)
        if key not in wanted:
            continue
        part = wanted[key]
        if part in found:
            if n.startswith(found[part] + "|"):
                continue                                    # e.g. chassis_geo inside chassis: same part
            dup.append(part)
        found[part] = n
    missing = [p for p in REQUIRED if p not in found]
    if missing or dup:
        msg = []
        if missing:
            msg.append("Missing: %s" % ", ".join(missing))
        if dup:
            msg.append("More than one group named: %s" % ", ".join(sorted(set(dup))))
        msg.append("Found: %s" % (", ".join(sorted(found)) or "nothing"))
        msg.append("Expected groups named chassis, wheel_FL, wheel_FR, wheel_RL, wheel_RR and "
                   "optionally steering_wheel (case, namespace and _grp/_geo suffix ignored).")
        raise BindError("\n".join(msg))
    return found


def _world(node):
    return cmds.getAttr(node + ".worldMatrix[0]")


def _parent_world(node):
    p = cmds.listRelatives(node, parent=True, fullPath=True)
    return (_world(p[0]), p[0]) if p else (list(mu.M4_IDENTITY), "")


def attach_model(model, root=None, hide_proxy=True, hide_bind=True):
    """Parent each named group of `model` under its animated rig node, keeping its placement
    relative to the bind car. Returns {part: node}."""
    root = find_rig_root(root)
    if not root:
        raise BindError("Select the model group and a Driving Rig.")
    ns = namespace_of(root)
    bind = find_bind_car(root)
    if not bind:
        raise BindError("Create the bind car first (Driving Rig > Car Model > Create Bind Car), "
                        "and line your model up with it.")
    if attached_parts(root):
        raise BindError("A model is already attached to this rig - detach it first.")
    bns = namespace_of(bind)
    parts = find_parts(model)
    # Pass 1 - measure everything in the untouched bind state. (Reparenting part by part would
    # measure a steering wheel inside an already-attached chassis group from a moving parent.)
    plan = []
    for part, node in PARTS:
        if part not in parts:
            continue
        target, bind_node = "%s:%s" % (ns, node), "%s:%s" % (bns, node)
        if not (cmds.objExists(target) and cmds.objExists(bind_node)):
            if part in REQUIRED:
                raise BindError("Rig has no %s" % node)
            continue                                        # steering wheel on an older take
        n = parts[part]
        wpp, parent_path = _parent_world(n)
        opm_old = cmds.getAttr(n + ".offsetParentMatrix")
        # world_new = L * OPM_new * W_anim  ==  (L * OPM_old * W_parent) * inv(W_bind) * W_anim
        opm_new = mu.m4_mul(mu.m4_mul(opm_old, wpp), mu.m4_inverse_affine(_world(bind_node)))
        parent_id = cmds.ls(parent_path, uuid=True)[0] if parent_path else ""
        plan.append((part, cmds.ls(n, uuid=True)[0], target, opm_old, opm_new, parent_id))
    # Pass 2 - reparent (by UUID: paths change as parents move)
    done = {}
    for part, uid, target, opm_old, opm_new, parent_id in plan:
        n = cmds.ls(uid, long=True)[0]
        add_attr(n, "drvOrigParent", parent_id, "string")
        add_attr(n, "drvOrigOffset", json.dumps(opm_old), "string")
        add_attr(n, "drvAttachedTo", ns, "string")
        n = cmds.parent(n, target, relative=True)[0]
        cmds.setAttr(n + ".offsetParentMatrix", *opm_new, type="matrix")
        done[part] = cmds.ls(n, long=True)[0]
    if hide_proxy and cmds.attributeQuery("proxyVisibility", node=root, exists=True):
        cmds.setAttr(root + ".proxyVisibility", False)
    if hide_bind:
        cmds.setAttr(bind + ".visibility", False)
    return done


def attached_parts(root):
    ns = namespace_of(find_rig_root(root))
    out = []
    for n in cmds.ls(type="transform", long=True) or []:
        if cmds.attributeQuery("drvAttachedTo", node=n, exists=True) and cmds.getAttr(n + ".drvAttachedTo") == ns:
            out.append(n)
    return out


def detach_model(root=None):
    """Undo attach_model: every part back under its original parent with its original offset,
    so it sits exactly where it was placed against the bind car. Returns the parts."""
    root = find_rig_root(root)
    if not root:
        raise BindError("Select a Driving Rig first.")
    back = []
    for uid in [cmds.ls(n, uuid=True)[0] for n in attached_parts(root)]:
        n = cmds.ls(uid, long=True)[0]
        parent_id = cmds.getAttr(n + ".drvOrigParent")
        opm = json.loads(cmds.getAttr(n + ".drvOrigOffset"))
        parent = (cmds.ls(parent_id, long=True) or [None])[0] if parent_id else None
        if parent:
            n = cmds.parent(n, parent, relative=True)[0]
        else:
            n = cmds.parent(n, world=True, relative=True)[0]
        cmds.setAttr(n + ".offsetParentMatrix", *opm, type="matrix")
        for a in ("drvOrigParent", "drvOrigOffset", "drvAttachedTo"):
            cmds.deleteAttr(n + "." + a)
        back.append(n)
    if cmds.attributeQuery("proxyVisibility", node=root, exists=True):
        cmds.setAttr(root + ".proxyVisibility", True)
    bind = find_bind_car(root)
    if bind:
        cmds.setAttr(bind + ".visibility", True)
    return back

"""Tyre marks as curves, for FX.

    from driving_rig import skid
    skid.create_skid_curves(rig)     # or Driving Rig > Create Skid Curves

Every take already stores, per wheel per tick, the world contact point, whether the wheel was
on the ground, and how much it was slipping. This turns the slipping stretches into NURBS
curves you can extrude, attach tracks to, or use as emitters.

One curve per continuous skid, under `<ns>:skids`, in the same space as the rig (world, cm,
under DrivingRig_world). Each carries:

    drvWheel        FL / FR / RL / RR
    drvStartFrame   frame the skid begins          drvEndFrame  frame it ends
    drvPeakSlip     the worst slip in it (0-1+)    drvLength    length in cm
    drvIntensity    KEYED 0..1 over the skid: 0 before it starts, the slip amount while it
                    runs, 0 after - ready to drive smoke density or a dust emitter's rate.
"""
from __future__ import annotations

import math

from maya import cmds

from . import bake, take_io
from .mayautil import add_attr, exact_fps, find_rig_root, mtime_unit, namespace_of, put_in_world, \
    scene_units, write_curve
from .take_io import WHEELS

SKID_ATTR = "drvSkids"


def slip_amount(take, w, i):
    """How hard wheel `w` is sliding at sample `i`, as one number. 0 = rolling cleanly.
    Combines locking/spinning (slip_long) with sideways slide (slip_lat, in radians)."""
    lon = abs(take.wheel(w, "wheels.slip_long")[i])
    lat = abs(take.wheel(w, "wheels.slip_lat")[i])
    return math.sqrt(lon * lon + (lat / math.radians(20.0)) ** 2)


def find_skids(take, threshold=0.35, min_speed_kmh=8.0, min_points=4, gap_ticks=12):
    """Stretches where a wheel was grounded and sliding. Returns a list of dicts with the
    wheel, the sample range, the world contact points (metres) and the slip at each."""
    speed = take["vel"]
    hz = take.tick_hz
    out = []
    for w in range(4):
        grounded = take.wheel(w, "wheels.grounded")
        cp = take.wheel(w, "wheels.contact_p")
        run = None
        gap = 0
        for i in range(take.n):
            v = math.sqrt(speed[0][i] ** 2 + speed[1][i] ** 2 + speed[2][i] ** 2) * 3.6
            hot = bool(grounded[i]) and v >= min_speed_kmh and slip_amount(take, w, i) >= threshold
            if hot:
                if run is None:
                    run = {"wheel": WHEELS[w], "start": i, "points": [], "slip": []}
                gap = 0
                run["end"] = i
                run["points"].append((cp[0][i], cp[1][i], cp[2][i]))
                run["slip"].append(slip_amount(take, w, i))
            elif run is not None:
                gap += 1
                if gap > gap_ticks:                     # short interruptions stay one skid
                    if len(run["points"]) >= min_points:
                        out.append(run)
                    run = None
                    gap = 0
        if run is not None and len(run["points"]) >= min_points:
            out.append(run)
    out.sort(key=lambda r: (r["start"], r["wheel"]))
    return out


def _thin(points, slips, tolerance_cm):
    """Drop points that sit on the line between their neighbours (they add nothing to the
    curve shape). Keeps the ends, and the sample index of everything it keeps."""
    keep = [0]
    for i in range(1, len(points) - 1):
        a, b, c = points[keep[-1]], points[i], points[i + 1]
        ab = [b[k] - a[k] for k in range(3)]
        ac = [c[k] - a[k] for k in range(3)]
        n = math.sqrt(sum(x * x for x in ac))
        if n < 1e-9:
            continue
        t = max(0.0, min(1.0, sum(ab[k] * ac[k] for k in range(3)) / (n * n)))
        d = math.sqrt(sum((ab[k] - t * ac[k]) ** 2 for k in range(3)))
        if d > tolerance_cm:
            keep.append(i)
    keep.append(len(points) - 1)
    return keep


def create_skid_curves(root=None, threshold=0.35, min_speed_kmh=8.0, tolerance_cm=0.5, verbose=True):
    """Build skid curves for the take on `root`'s rig. Replaces any it made before."""
    root = find_rig_root(root)
    if not root:
        raise RuntimeError("Select a Driving Rig (any node of it) first.")
    path = cmds.getAttr(root + ".drvTakePath")
    take = take_io.load(path)
    fps = cmds.getAttr(root + ".drvFps")
    in_frame = cmds.getAttr(root + ".drvInFrame")
    rate = exact_fps(fps)
    unit = mtime_unit(fps)
    s = take.unit_scale
    ns = namespace_of(root)

    runs = find_skids(take, threshold=threshold, min_speed_kmh=min_speed_kmh)
    with scene_units():
        grp = "%s:skids" % ns
        if cmds.objExists(grp):
            cmds.delete(grp)
        grp = cmds.createNode("transform", name=grp, skipSelect=True)
        add_attr(grp, SKID_ATTR, "%d" % len(runs), "string")
        add_attr(grp, "drvSkidThreshold", float(threshold))
        made = []
        for idx, run in enumerate(runs):
            keep = _thin(run["points"], run["slip"], tolerance_cm / s)
            pts = [tuple(run["points"][i][k] * s for k in range(3)) for i in keep]
            if len(pts) < 2:
                continue
            crv = cmds.curve(point=pts, degree=min(3, len(pts) - 1))
            crv = cmds.rename(crv, "%s:skid_%s_%03d" % (ns, run["wheel"], idx))
            crv = cmds.parent(crv, grp, relative=True)[0]
            # samples are at tick_hz; frames at `rate`
            per_frame = take.tick_hz / rate
            f0 = in_frame + (run["start"] - take.in_index) / per_frame
            f1 = in_frame + (run["end"] - take.in_index) / per_frame
            add_attr(crv, "drvWheel", run["wheel"], "string")
            add_attr(crv, "drvStartFrame", float(f0))
            add_attr(crv, "drvEndFrame", float(f1))
            add_attr(crv, "drvPeakSlip", float(max(run["slip"])))
            add_attr(crv, "drvLength", float(cmds.arclen(crv)))
            # intensity: 0 -> slip over the skid -> 0, one key per frame it covers
            frames = [f0 - 1.0]
            values = [0.0]
            step = max(1, int(round(per_frame)))
            for j in range(0, len(run["slip"]), step):
                frames.append(in_frame + (run["start"] + j - take.in_index) / per_frame)
                values.append(min(run["slip"][j], 2.0))
            frames.append(f1 + 1.0)
            values.append(0.0)
            add_attr(crv, "drvIntensity", 0.0, "double", keyable=True)
            write_curve(crv, "drvIntensity", frames, values, "linear", unit)
            made.append(crv)
        grp = put_in_world(grp)
    report = "%d skid curves from %s (slip threshold %.2f)" % (len(made), path.replace("\\", "/").split("/")[-1], threshold)
    if made:
        by_wheel = {}
        for r in runs:
            by_wheel[r["wheel"]] = by_wheel.get(r["wheel"], 0) + 1
        report += "\n  " + ", ".join("%s: %d" % (w, by_wheel.get(w, 0)) for w in WHEELS)
    else:
        report += "\n  Nothing slid past the threshold - try a lower one, or a take with some sliding in it."
    add_attr(grp, "drvLastCheck", report, "string")
    if verbose:
        print(report)
    return grp

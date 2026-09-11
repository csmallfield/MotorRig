"""Take → per-frame rig channels. Pure Python (no Maya), so it's tested outside Maya.

The Maya layer only creates nodes and writes what :func:`bake` returns. Units out:
centimetres (× meta.unit_scale), radians, seconds — Maya's internal units, which is what
MFnAnimCurve.addKeys takes regardless of the scene's UI units.

Resampling is point sampling at frame times (what a zero-length shutter would see);
the raw 240 Hz stays in the take, so any take can be re-cut at another rate later.
"""
from __future__ import annotations

import math

from . import mathutil as mu
from .take_io import WHEELS


class Resampler(object):
    """Maps target times (seconds re IN) onto the take's 240 Hz samples once, then applies
    that mapping to any number of channels."""

    def __init__(self, take, times):
        self.n = take.n
        self.idx = []
        self.frac = []
        last = take.n - 1
        for t in times:
            x = take.in_index + t * take.tick_hz
            j = int(math.floor(x + 1e-9))
            f = x - j
            if j < 0:
                j, f = 0, 0.0
            elif j >= last:
                j, f = last - 1, 1.0
            if abs(f) < 1e-9:
                f = 0.0
            self.idx.append(j)
            self.frac.append(f)

    def lin(self, s):
        return [s[j] + (s[j + 1] - s[j]) * f for j, f in zip(self.idx, self.frac)]

    def step(self, s):
        """Value of the most recent tick (for 0/1 flags)."""
        return [s[j + 1] if f >= 1.0 - 1e-9 else s[j] for j, f in zip(self.idx, self.frac)]

    def quat(self, qx, qy, qz, qw):
        out = []
        for j, f in zip(self.idx, self.frac):
            a = (qx[j], qy[j], qz[j], qw[j])
            if f == 0.0:
                out.append(mu.q_norm(a))
            else:
                out.append(mu.q_norm(mu.q_slerp(a, (qx[j + 1], qy[j + 1], qz[j + 1], qw[j + 1]), f)))
        return out


def wheel_center_and_forward(chassis_p, chassis_q, hardpoint, susp_rest, comp, steer):
    """World wheel centre and wheel-forward (after steer, before spin), metres.
    Same chain as the rig: chassis → steer (at hardpoint, rotY) → susp (−(rest − comp))."""
    local_center = (hardpoint[0], hardpoint[1] - (susp_rest - comp), hardpoint[2])
    center = mu.v_add(chassis_p, mu.q_rotate(chassis_q, local_center))
    fwd = mu.q_rotate(chassis_q, (-math.sin(steer), 0.0, -math.cos(steer)))
    return center, fwd


def travel(centers, forwards):
    """Cumulative wheel-centre travel along wheel-forward (same units as centers)."""
    d = [0.0] * len(centers)
    for i in range(1, len(centers)):
        fwd = mu.v_norm(mu.v_add(forwards[i], forwards[i - 1]))
        d[i] = d[i - 1] + mu.v_dot(mu.v_sub(centers[i], centers[i - 1]), fwd)
    return d


def slip_distance(travel_240, spin_240, radius):
    """Everything the wheel's rotation did that rolling doesn't explain — wheelspin,
    lock-up, free spin in the air — as a cumulative distance: S = r·θ − travel.

    Computed at 240 Hz where the take is exact. Because S is cumulative, point-sampling it
    at frames is exact at any frame rate. (Averaging instantaneous slip_long at frame ends,
    as spec 3.3 first proposed, misses slip bursts shorter than a frame: up to ~250° of spin
    error mid-take at 24 fps on a real take.)"""
    return [radius * th - d for th, d in zip(spin_240, travel_240)]


def solve_spin(centers, forwards, slip_dist, theta0, radius):
    """Spec 3.3 spin solve, per frame:   θ = θ₀ + (Δtravel + Δslip_distance) / r

    `centers`/`forwards` come from the *scene* (so the spin follows retimes, root offsets,
    constraints); `slip_dist` is the keyed slip-distance curve sampled at the same frames.
    Units: centers, slip_dist and radius share one unit (m or cm)."""
    d = travel(centers, forwards)
    if not d:
        return []
    return [theta0 + ((d[i] - d[0]) + (slip_dist[i] - slip_dist[0])) / radius for i in range(len(d))]


def spin_check(centers, forwards, recorded, grounded, slip_long, radius, solved=None):
    """Diagnostics. The solve reproduces the recorded spin by construction, so drift alone
    can't catch a wrong radius; instead estimate the *effective* radius from clean rolling
    frames (grounded, |slip| < 2 %): r_eff = Σ Δd·Δθ / Σ Δθ². A wrong wheel radius, a
    unit-scale mistake or a bad contact offset shows up as r_eff ≠ radius."""
    d = travel(centers, forwards)
    num = den = 0.0
    used = 0
    for i in range(1, len(d)):
        if grounded[i] and grounded[i - 1] and abs(slip_long[i]) < 0.02 and abs(slip_long[i - 1]) < 0.02:
            dth = recorded[i] - recorded[i - 1]
            if abs(dth) > 1e-3:
                num += (d[i] - d[i - 1]) * dth
                den += dth * dth
                used += 1
    r_eff = num / den if den > 0 else float("nan")
    rep = {
        "radius": radius,
        "radius_effective": r_eff,
        "radius_error_percent": 100.0 * (r_eff - radius) / radius if den > 0 else float("nan"),
        "frames_used": used,
        "revolutions": abs(recorded[-1] - recorded[0]) / mu.TAU if recorded else 0.0,
    }
    if solved is not None:
        rep["max_drift_deg"] = math.degrees(max((abs(a - b) for a, b in zip(solved, recorded)), default=0.0))
    return rep


RADIUS_WARN_PERCENT = 1.5


def _chain_240(take, w, hp, susp_rest):
    P = take["chassis.p"]
    Q = take["chassis.q"]
    comp = take.wheel(w, "wheels.compression")
    steer = take.wheel(w, "wheels.steer")
    cs, fs = [], []
    for i in range(take.n):
        c, f = wheel_center_and_forward((P[0][i], P[1][i], P[2][i]), (Q[0][i], Q[1][i], Q[2][i], Q[3][i]),
                                        hp, susp_rest, comp[i], steer[i])
        cs.append(c)
        fs.append(f)
    return cs, fs


class Bake(object):
    """Everything the Maya layer writes, per frame. Lists are parallel to `frames`."""
    pass


def bake(take, fps=24.0, in_frame=1001.0, solve=True):
    s = take.unit_scale
    frames, times = take.frame_grid(fps, in_frame)
    rs = Resampler(take, times)
    meta = take.meta
    b = Bake()
    b.fps = float(fps)
    b.in_frame = float(in_frame)
    b.frames = frames
    b.times = times
    b.unit_scale = s
    b.spin_solved = bool(solve)

    # chassis
    P = take["chassis.p"]
    px, py, pz = rs.lin(P[0]), rs.lin(P[1]), rs.lin(P[2])
    Q = take["chassis.q"]
    quats = rs.quat(Q[0], Q[1], Q[2], Q[3])
    eul = mu.quats_to_euler_zxy(quats)
    b.chassis_t = ([x * s for x in px], [y * s for y in py], [z * s for z in pz])
    b.chassis_r = ([e[0] for e in eul], [e[1] for e in eul], [e[2] for e in eul])

    # wheels
    susp_rest = float(meta["susp_rest"])
    radius = float(meta["wheel_radius"])
    hps = meta["hardpoints"]
    b.wheels = {}
    b.spin_report = {}
    n = take.n
    for w, name in enumerate(WHEELS):
        comp = rs.lin(take.wheel(w, "wheels.compression"))
        steer = rs.lin(take.wheel(w, "wheels.steer"))
        rec = rs.lin(take.wheel(w, "wheels.spin_cumulative"))
        grounded = rs.step(take.wheel(w, "wheels.grounded"))
        slip_l = rs.lin(take.wheel(w, "wheels.slip_long"))
        slip_a = rs.lin(take.wheel(w, "wheels.slip_lat"))
        cp = take.wheel(w, "wheels.contact_p")
        cx, cy, cz = rs.lin(cp[0]), rs.lin(cp[1]), rs.lin(cp[2])

        # 240 Hz: exact travel and slip distance from the take itself
        rec240 = take.wheel(w, "wheels.spin_cumulative")
        c240, f240 = _chain_240(take, w, hps[w], susp_rest)
        slip240 = slip_distance(travel(c240, f240), rec240, radius)
        slip_d = rs.lin(slip240)

        # frame rate: what the rig will show
        centers, fwds = [], []
        for i in range(len(frames)):
            c, f = wheel_center_and_forward((px[i], py[i], pz[i]), quats[i], hps[w], susp_rest, comp[i], steer[i])
            centers.append(c)
            fwds.append(f)
        spin = solve_spin(centers, fwds, slip_d, rec[0], radius) if solve else list(rec)
        b.spin_report[name] = spin_check(centers, fwds, rec, grounded, slip_l, radius, solved=spin)
        b.wheels[name] = {
            "steer_ry": steer,                                        # rad, + = left
            "susp_ty": [-(susp_rest - c) * s for c in comp],          # cm
            "spin_rx": [-a for a in spin],                            # rad; forward roll = −X
            "spin_recorded": rec,                                     # rad, for re-solve / check
            "slip_distance": [v * s for v in slip_d],                 # cm, cumulative (re-solve input)
            "contact_t": ([v * s for v in cx], [v * s for v in cy], [v * s for v in cz]),
            "grounded": grounded,
            "slip_long": slip_l,
            "slip_lat": slip_a,
            "centers_cm": [mu.v_scale(c, s) for c in centers],
        }

    b.radius_warn = [w for w, r in b.spin_report.items()
                     if not abs(r["radius_error_percent"]) <= RADIUS_WARN_PERCENT]

    # steering wheel: mean front road-wheel angle x ratio (as in Godot); needs rig 0.7+ params
    cp = meta.get("car_params", {})
    b.steering = None
    if "steering_ratio" in cp and "driver_eye" in cp:
        fl, fr = b.wheels["FL"]["steer_ry"], b.wheels["FR"]["steer_ry"]
        ratio = float(cp["steering_ratio"])
        b.steering = {
            "angle": [(a + c) * 0.5 * ratio for a, c in zip(fl, fr)],   # rad, + = CCW from the seat
            "ratio": ratio,
            "position_cm": [(float(cp["driver_eye"][k]) + float(cp["steering_wheel_offset"][k])) * s for k in range(3)],
            "tilt_deg": float(cp["steering_column_tilt_deg"]),
            "radius_cm": float(cp["steering_wheel_radius"]) * s,
        }

    # every recorded camera (rig 0.7+) and which one was on screen
    b.cameras = []
    for k, name in enumerate(take.camera_names):
        P = take.camera(k, "cams.p")
        Q = take.camera(k, "cams.q")
        eul = mu.quats_to_euler_zxy(rs.quat(Q[0], Q[1], Q[2], Q[3]))
        b.cameras.append({
            "name": name,
            "t": tuple([v * s for v in rs.lin(P[c])] for c in range(3)),
            "r": tuple([e[c] for e in eul] for c in range(3)),
            "focal": [mu.vfov_to_focal_mm(v) for v in rs.lin(take.camera(k, "cams.fov"))],
        })
    b.active_camera = rs.step(take["camera.active"]) if "camera.active" in take else None

    # camera (optional channel)
    b.camera = None
    if "camera.p" in take and "camera.q" in take:
        C = take["camera.p"]
        CQ = take["camera.q"]
        ce = mu.quats_to_euler_zxy(rs.quat(CQ[0], CQ[1], CQ[2], CQ[3]))
        fov = rs.lin(take["camera.fov"]) if "camera.fov" in take else [50.0] * len(frames)
        b.camera = {
            "t": tuple([v * s for v in rs.lin(C[k])] for k in range(3)),
            "r": tuple([e[k] for e in ce] for k in range(3)),
            "focal": [mu.vfov_to_focal_mm(v) for v in fov],
        }
    return b

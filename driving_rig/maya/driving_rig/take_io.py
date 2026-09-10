"""Read Driving Rig takes - format v2 (``.json.gz`` or ``.json``).

Standard library only, so it runs in any mayapy (or plain Python 3.7+) without a pip step.
numpy is used for :meth:`Take.as_numpy` if it happens to be installed; nothing requires it.

    from driving_rig import take_io
    take = take_io.load(r"D:/shots/hero_pass_A.json.gz")
    take.n, take.tick_hz, take.in_index, take.out_index
    take["chassis.p"]                   # [[x...], [y...], [z...]]  component-major, time last
    take.wheel("FL", "wheels.compression")   # [c0, c1, ...]
    take.times()                        # seconds, 0.0 at the IN point, handles negative / past OUT
    frames, t = take.frame_grid(24.0, in_frame=1001)
    take.resample(take["chassis.p"][0], t)   # linear, onto the frame grid

Shapes (time is always the last axis):  scalar -> (n)   vector -> (k, n)
per-wheel scalar -> (4, n)   per-wheel vector -> (4, k, n).  Wheel order FL FR RL RR.
Conventions are written into every take under ``meta["conventions"]`` - read them there.

Command line (no Maya needed):  python take_io.py take_0007.json.gz
"""
from __future__ import annotations

import bisect
import gzip
import json
import math
import sys

FORMAT_NAME = "driving_rig_take"
SUPPORTED_VERSIONS = (2,)
WHEELS = ("FL", "FR", "RL", "RR")

# name -> (per_wheel, components, is_flag). Mirrors TakeFormat.CHANNELS in the Godot project.
CHANNELS = {
    "chassis.p": (False, 3, False),
    "chassis.q": (False, 4, False),
    "vel": (False, 3, False),
    "angvel": (False, 3, False),
    "input.throttle": (False, 1, False),
    "input.brake": (False, 1, False),
    "input.steer": (False, 1, False),
    "input.handbrake": (False, 1, True),
    "camera.p": (False, 3, False),
    "camera.q": (False, 4, False),
    "camera.fov": (False, 1, False),
    "wheels.compression": (True, 1, False),
    "wheels.steer": (True, 1, False),
    "wheels.spin_cumulative": (True, 1, False),
    "wheels.grounded": (True, 1, True),
    "wheels.contact_p": (True, 3, False),
    "wheels.contact_n": (True, 3, False),
    "wheels.slip_long": (True, 1, False),
    "wheels.slip_lat": (True, 1, False),
}
OPTIONAL = {"camera.p", "camera.q", "camera.fov"}


class TakeError(ValueError):
    """Raised for anything that isn't a readable v2 take."""


class Take(object):
    """One loaded take. Channel data are plain Python lists (see module docstring for shapes)."""

    def __init__(self, root, path=""):
        self.path = path
        self.meta = root["meta"]
        self.summary = root.get("summary", {})
        self.channels = root["channels"]
        self.format_version = int(root.get("format_version", 0))
        self.n = int(self.meta["n"])
        self.tick_hz = float(self.meta["tick_hz"])
        self.in_index = int(self.meta["in_index"])
        self.out_index = int(self.meta["out_index"])
        self.unit_scale = float(self.meta.get("unit_scale", 1.0))

    # --- access -------------------------------------------------------------

    def __getitem__(self, name):
        try:
            return self.channels[name]
        except KeyError:
            raise KeyError("channel %r not in take (have: %s)" % (name, ", ".join(sorted(self.channels))))

    def __contains__(self, name):
        return name in self.channels

    def wheel(self, wheel, name):
        """Per-wheel channel for one wheel, by name ('FL') or index (0)."""
        i = WHEELS.index(wheel) if isinstance(wheel, str) else int(wheel)
        return self[name][i]

    def times(self):
        """Sample times in seconds, 0.0 at the IN point (handles negative / past OUT)."""
        inv = 1.0 / self.tick_hz
        return [(i - self.in_index) * inv for i in range(self.n)]

    @property
    def duration(self):
        """IN -> OUT, seconds."""
        return (self.out_index - self.in_index) / self.tick_hz

    def frame_grid(self, fps, in_frame=1001.0):
        """Whole frames at ``fps`` covering the recorded range (handles included), with IN on
        ``in_frame``. Returns (frames, times_in_seconds)."""
        t0 = -self.in_index / self.tick_hz
        t1 = (self.n - 1 - self.in_index) / self.tick_hz
        first = int(math.ceil(t0 * fps - 1e-9))
        last = int(math.floor(t1 * fps + 1e-9))
        frames = [in_frame + k for k in range(first, last + 1)]
        return frames, [k / float(fps) for k in range(first, last + 1)]

    def resample(self, series, times):
        """Linear resample of one time series (length n) onto ``times`` (seconds re IN).
        Plain linear is correct for every channel except quaternions - spin_cumulative is
        never wrapped precisely so this works."""
        src = self.times()
        out = []
        last = self.n - 1
        for t in times:
            j = bisect.bisect_right(src, t) - 1
            if j < 0:
                out.append(series[0])
            elif j >= last:
                out.append(series[last])
            else:
                f = (t - src[j]) * self.tick_hz
                out.append(series[j] + (series[j + 1] - series[j]) * f)
        return out

    def as_numpy(self):
        """{name: float64 ndarray}. Requires numpy (optional dependency)."""
        import numpy as np  # noqa: deferred on purpose
        return {k: np.asarray(v, dtype=np.float64) for k, v in self.channels.items()}

    def __repr__(self):
        return "<Take %s: %d samples @ %g Hz, %.2f s IN->OUT>" % (
            _num(self.meta.get("take", "?")), self.n, self.tick_hz, self.duration)


# --- loading ----------------------------------------------------------------

def read_root(path):
    """Parse a take file (gzip detected by magic bytes, not extension)."""
    with open(path, "rb") as f:
        raw = f.read()
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    return json.loads(raw.decode("utf-8"))


def load(path, validate_take=True):
    root = read_root(path)
    if not isinstance(root, dict) or "meta" not in root:
        raise TakeError("%s: not a Driving Rig take" % path)
    if "samples" in root and "channels" not in root:
        raise TakeError("%s is a format v1 take. Open it in the Godot take browser and Export - "
                        "exports are always written as v2." % path)
    if root.get("format") != FORMAT_NAME or int(root.get("format_version", 0)) not in SUPPORTED_VERSIONS:
        raise TakeError("%s: unsupported format %r v%r" % (path, root.get("format"), root.get("format_version")))
    if validate_take:
        errors = validate(root)
        if errors:
            raise TakeError("%s failed validation:\n  " % path + "\n  ".join(errors[:10]))
    return Take(root, path)


def validate(root):
    """Structural checks (same rules as the in-app TakeValidator). Returns a list of errors."""
    e = []
    meta = root.get("meta", {})
    for k in ("n", "tick_hz", "in_index", "out_index", "wheel_radius", "susp_rest", "unit_scale"):
        if not isinstance(meta.get(k), (int, float)):
            e.append("meta.%s missing" % k)
    if e:
        return e
    n = int(meta["n"])
    if not (0 <= meta["in_index"] < meta["out_index"] < n):
        e.append("meta.in_index/out_index out of range")
    hp = meta.get("hardpoints")
    if not (isinstance(hp, list) and len(hp) == 4 and all(isinstance(h, list) and len(h) == 3 for h in hp)):
        e.append("meta.hardpoints: expected 4 x [x,y,z]")
    chs = root.get("channels", {})
    for name, (per_wheel, comps, flag) in CHANNELS.items():
        v = chs.get(name)
        if v is None:
            if name not in OPTIONAL:
                e.append("channels.%s missing" % name)
            continue
        outer = v if per_wheel else [v]
        if per_wheel and len(v) != 4:
            e.append("channels.%s: expected 4 wheels" % name)
            continue
        for item in outer:
            series = [item] if comps == 1 else item
            if len(series) != comps:
                e.append("channels.%s: expected %d components" % (name, comps))
                break
            for s in series:
                if not isinstance(s, list) or len(s) != n:
                    e.append("channels.%s: expected %d samples" % (name, n))
                    break
                if flag and any(x not in (0, 1) for x in s):
                    e.append("channels.%s: flags must be 0/1" % name)
                    break
                if not flag and not all(isinstance(x, (int, float)) for x in s):
                    e.append("channels.%s: non-numeric value" % name)
                    break
    q = chs.get("chassis.q")
    if q and len(q) == 4 and all(len(c) == n for c in q):
        for i in range(n):
            if abs(math.sqrt(q[0][i] ** 2 + q[1][i] ** 2 + q[2][i] ** 2 + q[3][i] ** 2) - 1.0) > 1e-3:
                e.append("channels.chassis.q[%d]: not unit length" % i)
                break
    return e


# --- CLI --------------------------------------------------------------------

def _num(v):
    """Godot's JSON round-trip turns whole numbers into floats (1 -> 1.0); show them as ints."""
    return int(v) if isinstance(v, float) and v.is_integer() else v


def _main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    rc = 0
    for path in argv[1:]:
        try:
            t = load(path)
        except (TakeError, OSError, ValueError) as ex:
            print("INVALID  %s\n  %s" % (path, ex))
            rc = 1
            continue
        s = t.summary
        print("OK  %r" % t)
        print("    %s  |  %.1f m  |  peak %.1f km/h  |  %.2f g lat  |  air %.2f s" % (
            t.meta.get("created", ""), s.get("distance_m", 0), s.get("peak_speed_kmh", 0),
            s.get("max_lateral_g", 0), s.get("airtime_s", 0)))
        print("    ground: %s  |  unit_scale %g  |  handles %s frames" % (
            t.meta.get("collision_source", "?"), t.unit_scale, _num(t.meta.get("handles", "?"))))
        for fps in (24, 25, 30):
            frames, _ = t.frame_grid(fps)
            print("    @%d fps: frames %d-%d (IN = 1001, OUT = %.0f)" % (
                fps, frames[0], frames[-1], 1001 + t.duration * fps))
    return rc


if __name__ == "__main__":
    sys.exit(_main(sys.argv))

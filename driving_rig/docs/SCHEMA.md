# Take file format — v2

Current format since rig 0.3.0. One file per take: `take_####.json.gz` (gzip) or
`take_####.json` (same content, uncompressed — `compress_takes` on the Recorder node).
Units metres, radians, seconds. Right-handed, Y-up, −Z forward — the same as Maya, so
conversion is a pure `unit_scale` multiply.

## Reading it

```python
from driving_rig import take_io            # maya/driving_rig — stdlib only, numpy optional
take = take_io.load("hero_pass_A.json.gz")
take["chassis.p"][0]                        # x series, one value per 240 Hz tick
```

Without the module: `json.load(gzip.open(path))`. Gzip is standard (magic `1f 8b`); detect it
by magic bytes, not extension. Validate pipeline-side with `docs/take.schema.json`.

## Layout

```
{"format":"driving_rig_take","format_version":2,"meta":{…},"summary":{…},   ← line 1
"channels":{
"chassis.p":[[x…],[y…],[z…]],                                              ← one channel per line
…
}}
```

Every channel is a time series of length `meta.n`, **time is always the last axis**, and
multi-component channels are component-major, so each innermost list maps to one anim curve.

| shape | example |
|---|---|
| `(n)` | `input.throttle`, `camera.fov` |
| `(k, n)` | `chassis.p` (3), `chassis.q` (4), `vel`, `angvel`, `camera.p`, `camera.q` |
| `(4, n)` | `wheels.compression`, `wheels.steer`, `wheels.spin_cumulative`, `wheels.grounded`, `wheels.slip_long`, `wheels.slip_lat` |
| `(4, k, n)` | `wheels.contact_p`, `wheels.contact_n` (k = 3) |

`meta.channel_shapes` repeats this per channel, without the time axis. Wheel order is FL FR RL RR.

**Time is implicit:** sample `i` is at `t = (i − in_index) / tick_hz` seconds. `t = 0` is the IN
point; handles are negative / past OUT. (v1 stored `t` per sample; it was fully redundant.)

## Precision (decimals written; values are rounded, never truncated)

| channel | decimals | resolution |
|---|---|---|
| chassis.p, wheels.contact_p, wheels.compression | 5 | 0.01 mm |
| chassis.q, camera.q | 6 | 1e-6 (≈ 0.0001°) |
| wheels.steer | 5 | 0.0006° |
| wheels.spin_cumulative | 4 | 1e-4 rad = 34 µm at the tyre surface |
| vel, angvel, camera.p, wheels.contact_n, wheels.slip_lat | 4 | |
| input.*, wheels.slip_long, camera.fov | 3 | |
| input.handbrake, wheels.grounded | — | 0 / 1 |

The Godot test suite checks every channel of a real recording stays within half a step of
the unrounded data, and that the ghost rebuilt from the file matches the live drive to
~0.03 mm. v2 is ~11× smaller than v1: ~290 KB per 10 s, ~5 MB for a 3-minute take.

## meta

Spec schema fields plus:

| key | why |
|---|---|
| `n` | Sample count — every series has this length. |
| `in_index`, `out_index` | Sample indices of the marked IN/OUT. |
| `handle_ticks`, `handle_fps_basis` | `handles: 8` is frames, sized at a 24 fps basis (80 ticks) so every delivery rate gets ≥ 8 frames. |
| `body.extents_are: "full_size"` | `extents` is the full box size, not half extents. |
| `channel_shapes` | Per-channel shape without the time axis. |
| `conventions` | Sign conventions (below) — importers should read this, not assume. |
| `car_params` | Every tuning value, for re-simulating from `input.*` later. |
| `body.mass`, `wheel_order`, `rig_version`, `godot_version`, `created` | Provenance. |

`hardpoints` are chassis-local.

## Conventions

| channel | convention |
|---|---|
| `chassis.p`, `chassis.q` | body origin (not COM), world. Quaternion xyzw, hemisphere-continuous (safe to slerp). |
| `wheels.compression` | m from full droop. Wheel centre = hardpoint − (susp_rest − compression)·chassis_up. Droop-smoothed in the air, clamped at 1.1 × max travel. |
| `wheels.steer` | rad about chassis +Y, **+ = left**. Rear always 0. Ackermann applied per wheel. |
| `wheels.spin_cumulative` | rad, **+ = forward roll**, never wrapped. Visual rotation about the wheel's **−X**. |
| `wheels.contact_p/n` | world. Airborne: predicted point under the wheel, n = chassis up, grounded 0. |
| `wheels.slip_long` | (ω·r − v_long) / max(\|v_long\|, 1 m/s). −1 = locked, + = wheelspin. |
| `wheels.slip_lat` | slip angle, rad. |
| `input.steer` | raw device, −1 left … +1 right (opposite sign to `wheels.steer`). |
| `camera.*` | active camera (chase or driver) at that tick. Optional. |

### Note for the 3.3 spin solve

Because `slip_long` uses `max(|v|, 1)` in the denominator, `ω × (1 + slip_long)` is only exact
above 1 m/s. Use the additive form, exact at all speeds:

    Δθ = (Δd + slip_long · max(|Δd|, 1.0 · Δt)) / r      Δd = contact-patch travel along wheel forward

## Beside each take (not part of the interchange format)

`take_####.png` (path thumbnail) and a shared `index.cfg` (labels, favourites, cached headers,
last export folder).

## Legacy v1

`take_####.json`, one object per sample, per-sample `t`, no `format` key. Written by rig
0.1–0.2. The Godot project still lists, replays and validates v1; **Export always writes v2**,
which is the only format `take_io` (and so the Maya importer) reads.

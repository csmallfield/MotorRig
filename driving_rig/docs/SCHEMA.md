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

### How the Maya importer solves spin (3.3)

The spec's first formula — Δθ = (Δd + slip_long·max(|Δd|, Δt))/r with slip_long averaged at
frame ends — is exact per 240 Hz tick but not per film frame: slip bursts shorter than a frame
are lost, which measured up to ~250° of spin error mid-take at 24 fps. The importer instead
computes, at 240 Hz, each wheel's cumulative **slip distance** S = r·θ_recorded − travel, keys it
on the rig (`wheel_XX_spin.drvSlipDistance`), and solves

    θ(f) = θ₀ + (travel_scene(f) − travel_scene(f₀) + S(f) − S(f₀)) / r

where travel is measured from the wheel's world matrix in the scene. Cumulative quantities are
exact under point sampling, so this holds at any frame rate (≤ 0.22° vs recorded on a real take)
and still follows retimes and offsets. `slip_long` stays in the take and on the contact
locators for FX.

## Beside each take (not part of the interchange format)

`take_####.png` (path thumbnail) and a shared `index.cfg` (labels, favourites, cached headers,
last export folder).

## Scene geometry export (Export Scene...)

A folder `scene_<collision source>/` containing one OBJ per object, `scene.mtl` and `scene.json`:

```json
{"format": "driving_rig_scene", "format_version": 1, "units": "cm", "unit_scale": 100,
 "up_axis": "Y", "forward": "-Z", "space": "world", "winding": "ccw",
 "collision_source": "proc_heightmap_seed1234_800m_cell2.00+props",
 "objects": [{"name": "Ground", "file": "Ground.obj", "vertices": 160801, "triangles": 320000,
              "bounds_min": [...], "bounds_max": [...], "color": [r, g, b], "collides": true}, ...]}
```

- Vertices are world space, Godot metres × `unit_scale`; every node transform is baked in.
- Faces are **counter-clockwise** (Maya/OBJ front faces). Godot uses clockwise, so faces are
  reversed on export; `v//vn` vertex normals are included.
- `collides: false` marks visual-only geometry (road paint). Everything with `collides: true`
  is exactly what the wheels touched: procedural props collide against their own render mesh,
  imported sets against trimeshes of their meshes. Verified: 4,696 grounded contacts from a take
  driven through the hills lie on the exported surface to a median of 0.005 mm.
- `collision_source` equals the takes' `meta.collision_source` — the Maya importer compares
  them and warns on a mismatch.

## Legacy v1

`take_####.json`, one object per sample, per-sample `t`, no `format` key. Written by rig
0.1–0.2. The Godot project still lists, replays and validates v1; **Export always writes v2**,
which is the only format `take_io` (and so the Maya importer) reads.

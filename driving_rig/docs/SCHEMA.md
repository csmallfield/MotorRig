# Take file format — v0.1.0

One file per take: `user://takes/take_####.json`. Units metres, radians, seconds.
Right-handed, Y-up, −Z forward (same as Maya — conversion is a pure `unit_scale` multiply).

## Layout

```
{"meta":{…},"summary":{…},          ← line 1: parse this line alone (strip ",", append "}")
"samples":[
{…sample…},                          ← one sample per physics tick (240 Hz), one per line
…
]}
```

The whole file is also one valid JSON document.

## meta — additions to the spec schema

| key | why |
|---|---|
| `in_index`, `out_index` | Sample indices of the marked IN/OUT. The spec schema had no way to find them. |
| `handle_ticks`, `handle_fps_basis` | `handles: 8` is frames; ticks are sized at a 24 fps basis (80 ticks) so every delivery rate gets ≥ 8 frames of handle. |
| `body.extents_are: "full_size"` | `extents` is the full box size, not Godot-style half extents. |
| `body.mass`, `wheel_order`, `conventions` | Self-describing; the importer should read `conventions`, not assume. |
| `car_params` | Snapshot of every tuning value, for re-simulating from `input` later. |
| `rig_version`, `created` | Provenance. |

`hardpoints` are chassis-local, FL FR RL RR.

## sample

`t` is seconds relative to the IN point: pre-roll handle samples are negative, post-roll run past `(out_index − in_index) / tick_hz`.

| field | convention |
|---|---|
| `chassis.p`, `chassis.q` | body origin (not COM), world. Quaternion xyzw, hemisphere-continuous between samples (safe to slerp). |
| `wheels[].compression` | m from full droop. Wheel centre = hardpoint − (susp_rest − compression)·chassis_up. Visual value: droop-smoothed in the air, clamped at 1.1 × max travel. |
| `wheels[].steer` | rad about chassis +Y, **+ = left**. Rear always 0. Ackermann already applied per wheel. |
| `wheels[].spin_cumulative` | rad, **+ = forward roll**, never wrapped. Visual rotation is about the wheel's **−X**. |
| `wheels[].contact_p/n` | world. When airborne: predicted point under the wheel, n = chassis up, `grounded: false`. |
| `wheels[].slip_long` | (ω·r − v_long) / max(\|v_long\|, 1 m/s). −1 = locked, + = wheelspin. |
| `wheels[].slip_lat` | slip angle, rad. |
| `input.steer` | raw device, −1 left … +1 right (note: opposite sign to wheel `steer`). |
| `vel`, `angvel` | world, m/s and rad/s. |
| `camera` | active camera (chase or driver) at that tick. |

### Note for the 3.3 spin solve

Because `slip_long` uses `max(|v|, 1)` in the denominator, the multiplicative form
`ω × (1 + slip_long)` is only exact above 1 m/s. Use the additive form, exact at all speeds:

    Δθ = (Δd + slip_long · max(|Δd|, 1.0 · Δt)) / r      Δd = contact-patch travel along wheel forward

## Open design question: file size

AoS JSON as specified costs ~300 bytes/tick → ~3 MB per 10 s, ~55 MB for a 3-minute take,
and Maya has to walk ~40k dicts. A column layout — `"channels": {"chassis.p.x": [...], ...}`
— is 3–5× smaller, parses faster, and maps 1:1 onto `MDoubleArray` / numpy for `addKeys()`.
The line-1 header trick works the same. Worth deciding before the Phase 3 importer is written.

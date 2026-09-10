# Driving Rig — v0.1.0

Gamepad-driven proxy car in Godot 4.7 that records takes as JSON for a Maya importer.
A DIY Craft Director replacement. Spec: `docs/godot-driving-rig-spec.md`.

**This drop:** Phase 1 complete (1.1–1.5) + recorder capture and persistence (2.1, 2.2).
**Next:** 2.3 browser/ghost replay, 2.4 export dialog, then Phase 3 (Maya).

## Quick start

1. Open `project.godot` in Godot **4.7** (Forward+). First open imports for a few seconds.
2. F5. Xbox pad or keyboard. F1 toggles the help overlay.
3. Start (or R) → 3-2-1 → drive → Start again. Take is written after the 8-frame post-roll.
4. O opens the takes folder (`%APPDATA%\Godot\app_userdata\Driving Rig\takes\` on Windows).

| Gamepad | Keyboard | |
|---|---|---|
| RT / LT | W / S (↑ / ↓) | throttle / brake — hold brake at a stop to reverse |
| Left stick | A / D (← / →) | steer |
| B | Space | handbrake |
| Y | C | chase ↔ driver cam |
| Start | R | record / stop (cancels during countdown) |
| View/Back | Backspace | recover upright in place |
| — | Home | reset to spawn |

Recover/reset are locked while a take is running so every take is physically continuous.

## Project layout

```
scenes/main.tscn            world, car, cameras, recorder, HUD
scenes/car.tscn             RigidBody3D + DriverCam; everything else is generated in code
scripts/car/car.gd          suspension, tires, drivetrain, steering, wheel chain, take meta
scripts/camera/…            chase SpringArm rig + camera toggle
scripts/recorder/…          ring buffer, countdown, handles, threaded JSON writer
scripts/world/terrain.gd    procedural heightmap or imported scene (same-triangle collision)
scripts/ui/hud.gd           readouts + utility actions
shaders/grid_triplanar.gdshader   world-space (terrain) / object-space (car, wheels) grid
docs/SCHEMA.md              take format, conventions, deviations from the spec
```

The car builds its body, collider, shape casts and `steer → susp → spin → geo` chains from
its exported dimensions (Inspector → Car). The recorded `meta` comes from the same values,
so the Maya proxy can never disagree with what you drove.

## Tuning map

All on the Car node, grouped in the Inspector. Tick rate is 240 Hz — tune *at* 240.

- **Feel of the body:** `spring_rate_*`, `damp_bump/rebound`, `arb_front/rear`, `com_offset.y`.
  Front ARB stiffer than rear = understeer bias. `tire_force_lift` > 0 reduces roll.
- **Forgiveness:** `rear_grip` > `front_grip` (stability), `falloff_floor` (grip kept in a slide),
  `peak_slip_angle_deg`, `abs_enabled`.
- **Steering:** `steer_grip_margin_deg` — full stick = what the tires can use at the current
  speed plus this margin. Raise it to allow provoked understeer; ~40 disables the limiter.
- **Terrain:** `amplitude`, `octaves` (sharper crests → more airtime), `flat_radius`.

## Verified (headless, Godot 4.7-stable, Jolt, 240 Hz)

| Spec test | Result |
|---|---|
| 1.1 lands and rests level | ride height as designed, 0.000° roll/pitch |
| 1.2 settles, no jitter, push damps | 0.0 mm rest jitter; push + roll kick damps in ~1 s |
| 1.3 accel / brake / turn / no spin-out | 0–100 4.35 s · 120→0 in 52 m (1.08 g), 1.5° dive · ~3.3° roll/g · full lock ≈ 1.0 g at 40–140 km/h, yaw-rate s.d. ≤ 0.02 rad/s · lift-off flick at 110 km/h: 1.8° body slip · handbrake slide caught by countersteer |
| 1.4 wheels over bumps | 8 cm kerbs at 20–70 km/h: no launch, ≤ 1.3° pitch |
| 1.5 slopes | 50 km/h across the hills: zero airtime, zero body contact |
| 2.1 sample count | 10 s take → 2561 samples (2400 + 2×80 handle ticks + 1) |
| 2.2 persistence | valid JSON; header readable from line 1 alone |

Rendering checked via software OpenGL (Compatibility renderer), not Forward+/Vulkan.

## Known issues / notes

- **Files are big:** ~3 MB per 10 s (≈55 MB for a 3-minute take). See `docs/SCHEMA.md` —
  a column-per-channel layout would be 3–5× smaller and load straight into numpy in Maya.
- At 80+ km/h over the rougher hill lines, crests launch and the 0.9 m overhangs scrape in
  sharp valleys. That's realistic for 18 cm of travel; tame with `octaves` / `amplitude`.
- Takes are numbered by scanning the folder; deleting `take_0005.json` makes the next one 0005.
- `car_params` in each take snapshots every tuning value, for re-simulation later.
- Editing `car.tscn`/`main.tscn` in the editor is fine, but a later drop-in that ships the same
  file will overwrite your edits. Prefer tuning via the Inspector on the instance in
  `main.tscn`, and tell me what you changed so drop-ins can carry it.

## Updating (drop-ins)

Every drop-in zip is rooted at `driving_rig/`. Extract it into the folder that **contains**
your `driving_rig` folder and let Windows replace files. If a drop-in removes files, it ships
a `DELETED.txt` listing them — delete those by hand. `CHANGELOG.md` says what changed.

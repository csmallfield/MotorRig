# Driving Rig — v0.2.0

Gamepad-driven proxy car in Godot 4.7 that records takes as JSON for a Maya importer.
A DIY Craft Director replacement. Spec: `docs/godot-driving-rig-spec.md`.

**Done:** Phase 1 (1.1–1.5) and Phase 2 (2.1–2.4): drive, record, browse, replay, export.
**Next:** Phase 3 — the Maya importer.

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
| LB | Tab | take browser |
| X | P | ghost play / pause |
| View/Back | Backspace | recover upright in place |
| — | Home | reset to spawn |

Recover/reset are locked while a take is running so every take is physically continuous.

## Take browser

Tab / LB opens it. The car parks, recording is blocked, and the chase cam follows the replay.

- **Double-click / Enter / A** replays. The ghost (cyan) is rebuilt from the take's `meta`
  alone — the same job the Maya importer does — and posed straight from the samples, no
  re-simulation. **Y / C** switches chase ↔ the take's own recorded camera. Scrub with the slider.
- **Label** renames for display only; files stay `take_####.json` so anything downstream that
  references a take never breaks. Labels and favourites live in `takes/index.cfg`.
- **Export…** copies the take out with a native Save dialog (label as the suggested name),
  then validates the copy on a background thread and reports the result.
- **Delete** moves the take and its thumbnail to the recycle bin.
- **Close the browser with a ghost playing** and it keeps looping while you drive — for
  re-shooting a take against the previous one.

Thumbnails are a top-down path plot (10 m grid, colour = speed, green IN, red OUT).

## Project layout

```
scenes/main.tscn            world, car, cameras, recorder, HUD
scenes/car.tscn             RigidBody3D + DriverCam; everything else is generated in code
scripts/car/car.gd          suspension, tires, drivetrain, steering, wheel chain, take meta
scripts/camera/…            chase SpringArm rig + camera toggle
scripts/recorder/…          ring buffer + writer, TakeFormat (layout/IO/thumbnail),
                            TakeIndex (labels, favourites), TakeValidator
scripts/replay/…            GhostCar (built from meta), TakePlayer (threaded load, playback)
scripts/world/terrain.gd    procedural heightmap or imported scene (same-triangle collision)
scripts/ui/hud.gd           readouts + utility actions
scripts/ui/take_browser.gd  browser, replay transport, export
tests/run_tests.gd          headless regression suite
shaders/grid_triplanar.gdshader   world-space (terrain) / object-space (car, wheels) grid
docs/SCHEMA.md              take format, conventions, deviations from the spec
docs/take.schema.json       JSON Schema for pipeline-side validation
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

## Tests

After any retune, run the suite (Windows: use the **console** executable):

    Godot_v4.7-stable_win64_console.exe --headless --path . --fixed-fps 240 --script res://tests/run_tests.gd

Add test names after `--` to run a subset. Each test prints PASS/FAIL with measured values;
the exit code is the failure count. Test takes go to `user://test_takes`, never your takes.
The thresholds encode the spec's handling target, so a retune that makes the car snappy or
twitchy fails loudly. Current results (Godot 4.7-stable, Jolt, 240 Hz):

| Test | Result |
|---|---|
| settle | 0.000 mm rest jitter · ride height within 0.07 mm of analytic · push damped in < 2 s |
| accel_brake | 0–100 4.35 s · 120→0 in 52 m (1.09 g) |
| corner_60/100/140 | full lock: ≤ 6.8° body slip · yaw-rate s.d. ≤ 0.019 · 1.02–1.05 g |
| flick | lift-off flick at 110 km/h: 1.8° body slip |
| catch | handbrake kick 8.3°, countersteer recovers to 0° |
| bumps / ramp / hills | no launch over 8 cm bumps · 0.76 s ramp jump lands upright · 50 km/h hills: no air, no scrape |
| record_replay | 2561 samples for 10 s · **ghost from file vs live drive: 0.031 mm max wheel error over every sample** |
| validator | real take clean · corrupted copy caught |
| browser | list, replay, camera follow, input lock and restore |

## Known issues / notes

- **Files are big:** ~3 MB per 10 s (≈55 MB for a 3-minute take). See `docs/SCHEMA.md` —
  a column-per-channel layout would be 3–5× smaller and load straight into numpy in Maya.
- At 80+ km/h over the rougher hill lines, crests launch and the 0.9 m overhangs scrape in
  sharp valleys. That's realistic for 18 cm of travel; tame with `octaves` / `amplitude`.
- Takes are numbered by scanning the folder; deleting the newest take frees its number.
- Replaying a very long take holds it in memory as parsed JSON while loading (~5× file size,
  briefly). Fine for minutes; revisit with the column layout if takes get long.
- `car_params` in each take snapshots every tuning value, for re-simulation later.
- Editing `car.tscn`/`main.tscn` in the editor is fine, but a later drop-in that ships the same
  file will overwrite your edits. Prefer tuning via the Inspector on the instance in
  `main.tscn`, and tell me what you changed so drop-ins can carry it.

## Updating (drop-ins)

Every drop-in zip is rooted at `driving_rig/`. Extract it into the folder that **contains**
your `driving_rig` folder and let Windows replace files. If a drop-in removes files, it ships
a `DELETED.txt` listing them — delete those by hand. `CHANGELOG.md` says what changed.

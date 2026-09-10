# Driving Rig — v0.5.0

Gamepad-driven proxy car in Godot 4.7 that records takes as JSON for a Maya importer.
A DIY Craft Director replacement. Spec: `docs/godot-driving-rig-spec.md`.

**Done:** all three phases — drive, record, browse/replay/export in Godot; import onto a
proxy rig in Maya 2026 with spin re-solve.

## Quick start

1. Open `project.godot` in Godot **4.7** (Forward+). First open imports for a few seconds.
2. F5. Xbox pad or keyboard. F1 toggles the help overlay.
3. Start (or R) → 3-2-1 → drive → Start again. Take is written after the 8-frame post-roll.
4. Takes are written as `take_####.json.gz` (format v2 — see `docs/SCHEMA.md`).
5. O opens the takes folder (`%APPDATA%\Godot\app_userdata\Driving Rig\takes\` on Windows).

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
- **Export…** writes the take with a native Save dialog (label as the suggested name) —
  always as format v2, so older v1 takes are upgraded on the way out — then validates the
  written file on a background thread and reports the result. Choose `.json` in the dialog
  for an uncompressed copy.
- **Delete** moves the take and its thumbnail to the recycle bin.
- **Close the browser with a ghost playing** and it keeps looping while you drive — for
  re-shooting a take against the previous one.
- **Export Scene...** writes the drivable scene (terrain, props, marks — or an imported set) as
  OBJ files into `<folder>/scene_<ground name>/`: one OBJ per object, `scene.mtl`, and
  `scene.json`. World space, **centimetres, Y-up** — the same space as the take rigs, so it
  lines up with no manual offset. ~2 s and ~21 MB for the default 800 m terrain.

Thumbnails are a top-down path plot (10 m grid, colour = speed, green IN, red OUT).

## Maya (2026)

**Install:** drag `maya/install_driving_rig.py` into a Maya viewport. You get a **Driving Rig**
menu and a **DrivingRig** shelf (Import, Solve) straight away, and a small marked block in your
`userSetup.py` brings the menu back each session. *Driving Rig ▸ Uninstall* removes all of it.
After updating the project, drop the installer again to reload the code without restarting.
No numpy or pip needed.

**Scene geometry:** *Driving Rig ▸ Import Scene Geo...* (or the Scene shelf button) and pick the
`scene.json` from an export. Meshes are built straight from the files through the API, so they
land correctly in any scene units and in Z-up scenes (plain *File ▸ Import* of the OBJs also
works in a normal cm, Y-up scene). Each object gets a lambert in its Godot colour and a
`drvCollides` attribute — `False` on road paint, which the wheels drive over. Importing a take
and a scene made on **different ground** puts a warning in the report: that mismatch reads as
floating or sunken wheels.

**Import:** *Driving Rig ▸ Import Take…* (or the shelf). Pick a `.json.gz` exported from the
take browser. Defaults: 24 fps, IN on frame 1001 — both remembered once changed. Options:
set scene frame rate, set playback range (take + handles), import the take's camera, contact
locators, solve spin (or use the recorded spin as-is). A spin-check report pops up afterwards.

Each import lives in its own namespace (`drv_<name>:`), curves included, so several takes can
share a scene and *Delete Rig…* removes one cleanly.

```
drv_hero:root                  move/rotate the whole take from here
  chassis                      translate + rotate (rotate order zxy — see below)
    body_geo, nose_geo
    wheel_FL_steer → wheel_FL_susp → wheel_FL_spin → wheel_FL_geo      ×4
  contacts/contact_FL          world contact point; grounded / slipLong / slipLat for FX
  take_cam                     the camera you drove with (vertical-fit, focal from Godot's fov)
```

- **Rotate order zxy** on chassis and camera: heading is the outermost axis, so donuts and
  long turns never approach gimbal lock (Maya's default xyz would, at every ±90° of heading).
  Euler curves are unrolled for continuity — no flips, heading accumulates past 360°.
- **Re-solve Spin** after you retime or offset the car. It measures each wheel's travel from
  its world matrix in the scene (so root moves, retimes and constraints all count) and adds
  the take's recorded slip distance, so lock-ups, wheelspin and airborne spin survive.
  Retime the *whole* rig for exact results; retiming only the chassis still rolls correctly,
  with slip events staying at their original timing.
- **Check Spin** estimates each wheel's effective radius from clean rolling frames and warns
  above 1.5 % — the symptom of a wrong wheel radius, a mis-scaled rig or a bad contact offset.
- Units: works in any scene linear unit; your unit settings are restored after import.
- Import isn't undoable (keys go through the API for speed) — use *Delete Rig…*.

**Tests** — run from the project folder:

    "C:\Program Files\Autodesk\Maya2026\bin\mayapy.exe" -m unittest discover -s maya/tests -v

67 tests: the take reader (bit-for-bit vs Godot), the scene reader (Godot-written fixture:
winding, baked transforms, take contacts on the ground), the maths core (Euler conventions
through gimbal, spin solve, radius check), hygiene (Windows-safe text), and 23 that run inside
headless Maya — convention proof under large rotations, wheel positions, metres/Z-up scenes,
30 fps, re-solve == import, 8-frame retime, root offset, scene geo in take space, ground faces
up, **wheels touching the imported ground**, ground-mismatch warning, clean-up, installer.

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
tests/run_tests.gd          headless regression suite (Godot)
maya/install_driving_rig.py drag into a Maya viewport to install
maya/driving_rig/           take_io (reader) · mathutil + bake (pure-Python maths, solve) ·
                            rig (3.1 builder) · importer (3.2 curves, 3.3 re-solve/check) ·
                            ui · menu (menu, shelf, install)
maya/tests/                 reader, maths and Maya tests + a Godot-written fixture take
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
| record_replay | v2 gz, 291 KB for 10 s · every channel within its stated precision of the raw data · **ghost from file vs live drive: 0.031 mm max wheel error over every sample** |
| format_compat | v1 and v2 readers decode the same take identically |
| validator | real take clean · corrupted copy caught |
| export | v1 take re-encoded to valid v2 gz, 10× smaller |
| scene_export | 7 OBJs, ground 160,801 verts / 320k tris; corner vertex on the height function to 0.0000 cm |
| browser | list, replay, camera follow, input lock and restore |

### Python side (no Maya needed)

    mayapy -m unittest discover -s maya/tests -v
    mayapy maya/driving_rig/take_io.py path/to/take_0007.json.gz     # summary + validation

The fixture take in `maya/tests` was written by Godot, with Godot's own decoded values
alongside — the tests prove Python reads the format bit-for-bit the same.

## Known issues / notes

- At 80+ km/h over the rougher hill lines, crests launch and the 0.9 m overhangs scrape in
  sharp valleys. That's realistic for 18 cm of travel; tame with `octaves` / `amplitude`.
- Takes are numbered by scanning the folder; deleting the newest take frees its number.
- Replaying a long take parses it fully in memory while loading (a 3-minute take briefly
  needs ~100 MB). Loading runs on its own thread.
- `car_params` in each take snapshots every tuning value, for re-simulation later.
- Editing `car.tscn`/`main.tscn` in the editor is fine, but a later drop-in that ships the same
  file will overwrite your edits. Prefer tuning via the Inspector on the instance in
  `main.tscn`, and tell me what you changed so drop-ins can carry it.

## Updating (drop-ins)

Every drop-in zip is rooted at `driving_rig/`. Extract it into the folder that **contains**
your `driving_rig` folder and let Windows replace files. If a drop-in removes files, it ships
a `DELETED.txt` listing them — delete those by hand. `CHANGELOG.md` says what changed.

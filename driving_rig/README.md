# Driving Rig — v0.8.0

Gamepad-driven proxy car in Godot 4.7 that records takes as JSON for a Maya importer.
A DIY Craft Director replacement. Spec: `docs/godot-driving-rig-spec.md`.

**Done:** all three phases — drive, record, browse/replay/export in Godot; import onto a
proxy rig in Maya 2026 with spin re-solve.

## Quick start

1. Open `project.godot` in Godot **4.7** (Forward+). First open imports for a few seconds.
2. F5 opens the **start menu**: pick a car and a world, then DRIVE (gamepad: D-pad, A, Start).
   Xbox pad or keyboard. F1 toggles the help overlay; **Esc** (or Tab > Menu) returns to the menu.
3. Start (or R) → 3-2-1 → drive → Start again. Take is written after the 8-frame post-roll.
4. Takes are written as `take_####.json.gz` (format v2 — see `docs/SCHEMA.md`).
5. O opens the takes folder (`%APPDATA%\Godot\app_userdata\Driving Rig\takes\` on Windows).

| Gamepad | Keyboard | |
|---|---|---|
| RT / LT | W / S (↑ / ↓) | throttle / brake — hold brake at a stop to reverse |
| Left stick | A / D (← / →) | steer |
| B | Space | handbrake |
| Y | C | next camera (9 angles) — number keys 1-9 jump to one |
| Start | R | record / stop (cancels during countdown) |
| LB | Tab | take browser |
| X | P | ghost play / pause |
| View/Back | Backspace | recover upright in place |
| — | Home | reset to spawn |

Recover/reset are locked while a take is running so every take is physically continuous.

## Cameras

Nine cameras, all running every tick (so switching never jumps, and all of them are recorded):

| key | camera | |
|---|---|---|
| 1 | chase | lagged spring-arm follow |
| 2 | driver | driver's eye, with the steering wheel in view |
| 3 | heli | high overhead follow, slow heading lag, looking down with lead |
| 4 | front | tracking vehicle ahead, looking back at the car |
| 5 | side | Russian-arm profile alongside, matching speed |
| 6 | wheel | rigid mount low on the left flank, looking at the front wheel |
| 7 | bumper | rigid mount on the nose, looking ahead |
| 8 | trackside | broadcast camera planted ahead; pans and zooms as the car passes, then leapfrogs |
| 9 | orbit | slow orbit |

Tracking cameras never go below the terrain. In a replay they all follow the ghost — watch
any take from any angle; the driver slot becomes the take's recorded camera.

**Recording:** every camera's position, rotation and FOV is stored each tick, plus which one
was on screen (`camera.active` — an edit list). That roughly doubles file size (~600 KB per
10 s); set `record_all_cameras` off on the Recorder node to keep only the active camera.

## Steering wheel and custom chassis

The car has a steering wheel (torus, spoke, marker at 12 o'clock) that turns by the front
wheels' steer angle × `steering_ratio` (default 15:1: full lock ≈ 490°), counter-clockwise from
the seat when turning left. Position, radius and column tilt are in the car profile.

**Custom chassis:** drop a scene (a `.tscn`, or an imported `.glb`/`.gltf`/`.blend`) into the
car profile's `chassis_scene` and fit it with `chassis_transform`. It replaces the proxy box;
the collider is still the `body_size` box, so size that to match (handling is unchanged).
`hide_chassis_in_driver_cam` (default on) hides it from the driver cam — turn it off for a model
with an interior and see-through glass. The replay ghost rebuilds your model from the take.
Maya keeps the proxy cube (it can't read Godot scenes): parent your own model under `chassis`.

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

**World scale:** every rig and scene goes under one group, `DrivingRig_world`, with a single
channel-box attribute **`worldScale`** (1.0 = true size in cm; **0.1 = one unit per 10 cm**, so a
180 cm person is 18 units). Set it in the import dialog, via *Driving Rig ▸ World Scale...*, or
straight in the channel box — any time after import. Spin re-solve and the radius check measure
in world space, so they stay correct at any scale. Rigs imported before 0.7 are adopted into the
group the first time it's created.

**Your own car model** (*Driving Rig ▸ Car Model*):

1. **Create Bind Car** with the take rig selected: a static, unanimated copy in `<ns>_bind:` —
   parked level at the origin, sitting on its tyres at static ride height (weight ÷ spring
   rate), wheels straight, steering centred. It displays in reference mode (visible, not
   selectable) so you can snap to it.
2. Line your model up with it, organised in groups named `chassis`, `wheel_FL`, `wheel_FR`,
   `wheel_RL`, `wheel_RR` and optionally `steering_wheel`. Case, namespaces and a `_grp`/`_geo`
   suffix are ignored; nesting is fine (a steering wheel inside the chassis group, meshes
   named `chassis_geo`…). **Create Model Groups** makes the empty named groups, already placed.
   Scale and move the model's top group freely.
3. Select the model's top group and the rig, **Attach Model**. Each group is parented under
   its animated node — chassis → `chassis`, wheels → `wheel_XX_spin` (so they steer, compress
   and spin about the rig's wheel centre, whatever your pivots), steering wheel →
   `steering_wheel` — with the bind-to-model offset in its `offsetParentMatrix`. Your groups'
   own values, pivots and any animation are untouched; nothing is baked. The proxy geometry
   hides (`root.proxyVisibility`) and so does the bind car.

**Detach Model** puts every group back exactly where you placed it (re-fit, re-attach).
Deleting a rig detaches its model first — it never deletes your car. One model per rig at a
time: duplicate the model for another take.

**Cameras in Maya:** `take_cam` switches like the take did; the dialog's *Import every recorded
camera* adds `cameras/cam_chase … cam_orbit`, and the root gets an enum `activeCamera` keyed
(stepped) to what was on screen — ready to drive a camera sequencer. The steering wheel is
`chassis/steering_column/steering_wheel` (animated `rotateZ`).

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

82 tests (39 inside Maya), including the car-model workflow at world scale 1.0 and 0.1 with a
moved/scaled/rotated model group, nested layouts, detach and delete-keeps-model. Also: the take reader (bit-for-bit vs Godot), the scene reader (Godot-written fixture:
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

## Profiles (tuning)

All tuning lives in `.tres` resources, listed by the start menu straight from disk:

| | project (ships with the rig) | yours |
|---|---|---|
| cars | `res://profiles/cars/` | `%APPDATA%\Godot\app_userdata\Driving Rig\profiles\cars\` |
| worlds | `res://profiles/worlds/` | `...\profiles\worlds\` |

**Make one:** in the editor's FileSystem dock, duplicate a profile, double-click it, edit it
in the Inspector (grouped like the car: Dimensions, Suspension, Tires, Drivetrain, Steering),
save. Hit **Rescan** in the menu (or restart). The menu's *Open my profiles folder* button opens
the user location — use that for profiles you want to keep outside the project, or in an
exported build. Broken files show as *invalid* in the list instead of crashing.

**Car profile** — everything that was on the Car node, plus: `display_name`, `description`,
`body_color` (tints the proxy), `driver_eye`, `tuned_at_hz`, and **`traction_control`**
(caps drive force at the grip left after cornering: full throttle at full lock in the RWD car
peaks at 2.6 deg of body slip with TC, an 18.9 deg power slide without).

**World profile** — terrain (procedural settings or an imported scene) and world physics:
`gravity`, `tick_hz`, **`surface_grip`** (tyre grip multiplier: ~0.7 wet, ~0.5 gravel,
~0.15 snow) and `air_density_scale`. Grip and air are physics, not geometry: *Wet Hills* has
the same collision source as *Default Hills*, so their scene exports and takes pair. Any
change to terrain *shape* gets its own collision source, so the Maya mismatch warning works.

The menu warns if a car's `tuned_at_hz` differs from the world's `tick_hz` (spring behaviour
is rate-dependent). Every take records both profiles (`meta.car_profile`, `meta.world_profile`,
full values in `meta.car_params` / `meta.world_profile.params`); the take browser shows them.

Shipped profiles — all pass the stability tests below:

| car | notes | full lock @80 | flick |
|---|---|---|---|
| Proxy Sedan AWD | the reference: every original test was tuned on it | 4.3 deg slip, 3.3 deg roll | 1.8 deg |
| Hatchback FWD | 1050 kg, 110 kW, soft, short | 5.4 deg, 3.2 deg | 2.0 deg |
| Sports RWD | 1350 kg, 300 kW, stiff, TC on | 2.7 deg, 1.8 deg | 1.3 deg |
| SUV AWD | 2 t, soft and tall (SSF 1.29 g) | 4.4 deg, 4.3 deg | 1.7 deg |

Worlds: **Default Hills**, **Flat Pad** (all 800 m flat), **Rough Country** (seed 777, 22 m
hills, 4 octaves), **Wet Hills** (Default Hills at 70 % grip).

**Other nodes** still tuned in the Inspector: the chase camera (`ChaseCam`: pivot height, arm
length, pitch, FOV, follow sharpness) and the recorder (countdown, max length, handles,
compression, takes folder).

**If you tuned values on the Car node in `main.tscn` before 0.6.0:** those no longer apply —
the profile does. Copy them into a car profile (open `main.tscn` in a text editor; they're the
lines under `[node name="Car" ...]`).

## Tests

After any retune — or after adding a profile — run the suite (Windows: the **console** exe):

    Godot_v4.7-stable_win64_console.exe --headless --path . --fixed-fps 240 --script res://tests/run_tests.gd

Add test names after `--` to run a subset: `car_profiles` checks **every car profile on disk**
(settle, full-lock corner, lift-off flick, no rollover), `world_profiles` every world (builds,
physics applied, car settles), or one profile: `-- car:user://profiles/cars/mine.tres:corner`.
The reference tests always use the sedan and Default Hills, whatever the menu has selected. Each test prints PASS/FAIL with measured values;
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
| menu | lists every profile on disk, selects, warns on tick mismatch, flags invalid files |
| cameras | 9 cameras x 2,400 ticks in the hills: car in frame 100 %, rigid mounts fixed, never under ground, cycle + 1-9 |
| camera_record | active-camera track exact; every camera's recorded path matches live (1 mm, 2e-5 rad) |
| steering_wheel | full left lock: 32.6 deg road wheels → 490 deg wheel, marker to the driver's left |
| custom_chassis | model replaces box, collider unchanged, settles, ghost rebuilds model |
| car_profiles | 4 cars x settle / full lock / flick — see the profile table |
| world_profiles | 4 worlds: build, gravity/tick/grip applied, car settles |

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

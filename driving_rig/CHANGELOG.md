# Changelog

## 0.9.0 — driving modes

- **DriveMode profiles** (`res://profiles/modes`, `user://profiles/modes`), picked in a third
  column of the start menu. Layered on any car as multipliers, so **Standard is exactly
  neutral** - every existing handling number is unchanged and re-verified.
- Shipped: **Standard**, **Loose**, **Drift**, **Low Grip**, **Stunt**.
- New in the car: exponential trigger/stick response (`out = in^gamma`) applied to the
  physics while the take still records the raw device values; `low_speed_hold` toggle;
  `kerb_trip` sideways force when a wheel jams into a steep face (off by default, so Standard
  is bit-identical). Wheel lock-up now reachable by raising brake force with ABS off.
- Takes record `meta.drive_mode` (name, path, all values); the browser shows it.
- Tests: `drive_modes` (every mode on disk), `mode_loose`, `mode_stunt`. 44 Godot tests.

## 0.8.0 — your own car model in Maya

- **Create Bind Car:** static copy of a take rig at rest (`<ns>_bind:`), level at the origin on
  its tyres at static ride height; reference display. Built from metadata now stored on the
  rig root (`drvMeta`), falling back to the take file for older rigs.
- **Create Model Groups:** empty, correctly named groups placed at the bind car's parts.
- **Attach Model:** parents `chassis`, `wheel_FL/FR/RL/RR` and optional `steering_wheel` under
  the animated rig via `offsetParentMatrix` - exact, nothing baked, pivots/animation untouched.
  Forgiving names; top-most match wins for nested layouts; offsets measured before anything
  moves. **Detach Model** restores exactly (parents tracked by UUID).
- `root.proxyVisibility` switch; *Toggle Proxy Geometry*. Deleting a rig detaches its model first.
- 8 new Maya tests; test fake gained UUIDs and offsetParentMatrix.

## 0.7.1 — Maya fix

- **Fix:** the first take or scene imported into a Maya scene raised `TypeError: 'NoneType'
  object is not subscriptable` after keying. Creating `DrivingRig_world` adopted the new rig,
  and parenting it again made Maya return None; the import stopped before writing its report
  (so Re-solve Spin could fail on that rig - re-import it). Now `put_in_world()` checks first.
- Regression test: fresh scene, take then scene and scene then take. The test fake now
  mirrors Maya's "already a child" behaviour, which is why 0.7.0's tests missed it.

## 0.7.0 — cameras, steering wheel, custom chassis, Maya world scale

- **Cameras:** seven new ones (heli, front tracking, Russian-arm side, wheel mount, bumper,
  trackside broadcast, orbit) alongside chase and driver. C / Y cycles, 1-9 jump; all follow
  the replay ghost too. Ground-clamped. The HUD names the camera on each switch.
- **All cameras recorded** every tick (`cams.*`) plus the active camera (`camera.active`).
  Optional v2 channels — older takes load everywhere. `record_all_cameras` on the Recorder.
  Export keeps whatever the source take had.
- **Steering wheel** in the car (and the replay ghost): steer x `steering_ratio`, CCW when
  turning left. Profile: ratio, radius, offset from the driver's eye, column tilt.
- **Custom chassis:** `chassis_scene` + `chassis_transform` in the car profile replace the
  proxy box (collider unchanged); `hide_chassis_in_driver_cam`. Ghost rebuilds it.
- **Maya:** `DrivingRig_world` group with `worldScale` (dialog, menu, channel box; adopts older
  imports); every recorded camera imported plus a stepped `activeCamera` enum; steering wheel
  rig. Spin re-solve verified at any world scale.
- Tests: `cameras`, `camera_record`, `steering_wheel`, `custom_chassis` (Godot), 7 new Maya
  tests, a second Godot-written fixture take with all cameras. 37 Godot tests.

## 0.6.0 — car & world profiles, start menu

- **Car profiles** (`CarProfile` .tres): all car tuning + name, description, body colour,
  driver eye, tuned-at rate, and new **traction control**. The Car node's tuning is no longer
  in the Inspector; it's copied from the selected profile at spawn.
- **World profiles** (`WorldProfile` .tres): terrain settings + gravity, tick rate,
  **surface grip** and air density. Applied before anything else in the scene.
- **Start menu** (new main scene): lists every profile in `res://profiles/*` and
  `user://profiles/*`, shows summaries and descriptions, warns on tick mismatch, flags invalid
  files, remembers the last choice. Gamepad-friendly. **Esc** / Tab > Menu to return.
- Shipped: 4 cars (Sedan AWD reference, Hatchback FWD, Sports RWD, SUV AWD) and 4 worlds
  (Default Hills, Flat Pad, Rough Country, Wet Hills).
- Collision source now includes all terrain shape settings (hashed); the original default
  terrain keeps its old ID so existing takes and scene exports still pair.
- Takes record `car_profile`, `world_profile` (with params); the browser shows them.
- Tests: reference tests pin the sedan + Default Hills; new `menu`, `car_profiles` (every car
  on disk), `world_profiles` (every world on disk). 33 tests.

## 0.5.0 — scene geometry export

- **Godot:** *Export Scene...* in the take browser writes terrain, props and marks (or an
  imported set) as OBJ files + `scene.mtl` + `scene.json`, in the takes' space (world, cm, Y-up),
  CCW faces with normals. Runs on its own thread (~2 s for the 800 m terrain).
- **Physics:** speed bumps now collide against their own render mesh instead of an analytic
  cylinder, so what the wheels touch is exactly what Maya gets (was up to 0.6 mm off). Road
  marks are 2 mm paint and flagged `collides: false`. Handling unchanged (bump test 1.26 deg).
- **Maya:** *Import Scene Geo...* (menu + shelf) builds the meshes through the API from our own
  reader — any scene units, Z-up aware — with a lambert per object and `drvCollides`.
  Take and scene imports warn if they were made on different ground.
- New `scene_io.py` (stdlib reader, validation, winding check, surface height lookup),
  `test_scene_io.py`, 6 new Maya tests, `scene_export` Godot test.

## 0.4.1 — Windows encoding fix

- **Fix:** dropping the installer into Maya on Windows failed with `UnicodeEncodeError`
  (cp1252 can't encode the marker line), and could leave an existing `userSetup.py` empty.
  `userSetup.py` is now read and written as raw bytes (your content round-trips exactly,
  whatever its encoding), our block is pure ASCII (non-ASCII install paths are escaped), and
  the write goes to a side file first, then swaps — it can't be left half-written.
- All Maya-side messages are ASCII (a `mayapy` console on Windows would have hit the same error).
- New `maya/tests/test_hygiene.py` enforces it: no non-ASCII string literals, no `open()`
  without an explicit encoding. Installer round-trip test now uses non-ASCII file content and
  a non-ASCII install path. Whole suite verified under a non-UTF-8 default encoding.

## 0.4.0 — Maya importer (spec phase 3)

- **3.1** `rig.build`: proxy rig from `meta` alone — root offset control, chassis, steer → susp →
  spin → geo ×4, contact locators with grounded/slip attributes, the take's camera. One
  namespace per import, anim curves included.
- **3.2** Point-sampled bake at any rate (23.976–60, exact NTSC timing), keys via
  `MFnAnimCurve.addKeys`, rotate order zxy with continuity unrolling, auto tangents (linear on
  spin, stepped on grounded). Scene linear/angle units handled and restored; Z-up scenes supported.
- **3.3** Spin re-solve from scene travel + keyed slip distance (exact at film rates — replaces the
  frame-averaged slip formula, which drifted up to ~250° at 24 fps). Check Spin: effective-radius
  diagnostic.
- Import dialog (settings remembered), Driving Rig menu, DrivingRig shelf, drag-and-drop
  installer with clean uninstall.
- Pure-Python core (`mathutil`, `bake`) tested outside Maya; 17 Maya tests for mayapy.

## 0.3.0 — take format v2 + Python reader

- **Format v2:** one array per channel (component-major, time last), gzipped:
  `take_####.json.gz`. ~11× smaller than v1 (290 KB per 10 s). Per-channel precision,
  verified against the raw data. `t` is implicit: (i − in_index) / tick_hz.
- Recorder writes v2 (`compress_takes` off → plain `.json`, same layout).
- Browser lists v1 and v2; headers cached in `index.cfg` (gzip can't be read line-by-line).
  `TakeIndex` is now one shared instance owned by the recorder.
- Export always writes v2 (v1 takes upgraded on export), gz or plain by extension.
- `TakeValidator` and `docs/take.schema.json` updated for v2.
- New: `maya/driving_rig/take_io.py` — v2 reader (stdlib only, numpy optional), validation,
  frame grid with handles, linear resampling, CLI. Rejects v1 with instructions.
- New: `maya/tests` — contract tests against a Godot-written fixture (bit-for-bit match).
- Godot tests: `format_compat`, `export`; `record_replay` now checks every channel's precision.

## 0.2.0 — take browser, replay, export (spec 2.3, 2.4)

- Take browser (Tab / LB): list with path thumbnails and stats, favourites filter, labels,
  delete to recycle bin, open folder.
- Ghost replay built from the take's `meta` only, posed from samples (no re-simulation);
  scrub, loop, 0.25–2× speed, chase ↔ recorded camera. Measured against the live drive:
  0.031 mm max wheel-position error across every sample.
- Ghost keeps looping after the browser closes, to drive against a previous take.
- Export via native Save dialog, then in-app validation of the copy.
- `docs/take.schema.json` (JSON Schema) + `TakeValidator` (same rules, plus cross-field ones).
- Shared `TakeFormat` (layout, writer, streaming reader, thumbnails); recorder refactored onto it.
- Take loading and validation run on dedicated threads — Jolt runs physics jobs on
  WorkerThreadPool and a long parse there starved the solver.
- `tests/run_tests.gd`: 13-test headless regression suite with pass/fail thresholds.
- New input actions: `browser_toggle` (Tab, LB), `replay_play_pause` (P, X).

## 0.1.0 — initial project

Phase 1 (1.1–1.5) and recorder capture/persistence (2.1, 2.2).

- ShapeCast sphere suspension with exact contact-plane compression (Jolt cast fractions are
  quantized to ~1/512 of cast length; using them directly causes damper noise).
- Anti-roll bars, bump stops, slip-angle tires on a friction circle, ABS, handbrake.
- Grip-aware steering limit instead of linear speed falloff (removes full-lock yaw wobble).
- Chase SpringArm cam + driver cam (body shell culled on render layer 2).
- 800 m procedural terrain (150 m flat pad, speed bumps, launch ramp, a mark at z = −55),
  or any imported scene with same-triangle trimesh collision.
- Ring-buffer recorder, 3-2-1 countdown, 80-tick handles, threaded JSON writer, line-1 header.
- Deviations from the spec documented in docs/SCHEMA.md.

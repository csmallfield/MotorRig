# Changelog

## 0.16.1 — the monster truck getting stuck

- **Fix (car physics, all vehicles): a car could get stuck on its belly for good.** Each wheel
  finds the ground with a sphere the size of its tyre, swept down from the suspension mount.
  When the body was pressed onto the ground, a big tyre's sphere began *buried* - the monster
  truck's by 0.44 m. The physics engine ignores that initial overlap, so the wheel read "fully
  extended", the springs pushed with zero force, and the car sat there. The monster truck was
  worst hit; the bus and quad were exposed too. The sweep now starts one tyre radius above the
  mount, and a sweep that begins in contact reads as fully compressed, never fully extended.
  Normal driving is unchanged - every reference figure is identical.
- **Fix: bump stops stop growing 12 cm in.** A real bump stop is a few cm deep; counting the
  whole of the impossible "wheel inside the car" state launched a monster truck 11 m up when
  it stood up from its belly. Nothing short of 12 cm into the stop changes.
- **Fix (playground): landing pits had cliffs for sides.** 8-10 m deep with walls of 56-85
  degrees, and they ran into the obstacle course. Pits are now 5 m deep (still below where
  the matched landings happen) with sides of at most 22 deg, the two jump lanes are 60 m
  apart, and the bowl has moved to the south-west - it had been sitting under the kicker
  park. Landings are unchanged (1.6-2.2 m/s into the surface).
- Tests: a `belly` check for every vehicle; the playground test now also checks the landing
  valleys' side angles and that every obstacle sits on level ground.

## 0.16.0 — monster truck, dune buggy, vehicle playground

- **Monster Truck** (5.2 t, 1.7 m tyres, 70 cm travel, 700 kW AWD) and **Dune Buggy** (900 kg,
  50 cm travel, RWD), with proxy models. Suspension sized from static sag and damping ratio for
  a ~1.1-1.3 Hz ride; the buggy's rear spring is set to its axle load so it sits level.
  Measured: the buggy takes a 1.5 m drop and the monster truck 2.0 m without bottoming, against
  0.25 m for the sedan.
- **Vehicle Playground** world: a 42 m, 20 % hill that brings every vehicle to ~100 km/h by
  gravity alone; a tabletop and a mega jump at its foot with ski-jump-style landing hills
  (landing pits and run-outs), each calibrated from measured launches; and an obstacle course
  - whoops, moguls, kickers, step-up, stairs, logs, rock garden, tunnel, bowl, off-camber
  strip, slalom and loose crates.
- **Start points**: D-pad up / F2 cycles the car between a world's named starts (the
  playground has six). Generic - any world can define them.
- SurfaceBuilder gained orientation-safe solids (every face points away from its solid's
  centre), rotated boxes, wedges, logs and an indexed heightfield (110 k vertices for the
  playground instead of 650 k).
- Tests: `playground`, `playground_hill`, `playground_landings`, `long_travel`. 94 Godot tests.

## 0.15.3 — z-fighting on the vehicle bodies

- **Fix:** roofs flickered. The glass came up to the same height as the roof panel over it, so
  their top faces shared a plane. The glass now stops under the panel.
- **Fix:** headlights and tail lights were each built twice, one inside the other, on the centre
  line. The box builder ignored its x position, so every mirrored pair landed in the middle - a
  single light box per end instead of a pair, and flickering. Lights are now actual pairs.
- The model builder now refuses to write any two pieces that show the same face at the same
  depth. That found 24-28 overlapping pairs per vehicle: the roof on the cars, and the doubled
  lights on all eight.

## 0.15.2 — vehicle bodies were inside-out

- **Fix:** every triangle of all eight proxy bodies faced inward, so you saw the inside of the
  far walls. The corners were listed counter-clockwise as seen from *inside* each solid; glTF
  wants counter-clockwise from outside. Twisted faces (a solid tapering differently top and
  bottom) now get a normal per triangle rather than one shared one.
- The builder now refuses to write a face that points into its solid or a triangle that winds
  against its normal.
- New `vehicle_models` test: each material surface of each body must enclose a positive signed
  volume, measured against a box Godot built itself. A winding-vs-normal check was tried first
  and passed on the broken models - they were *consistently* inside-out, winding and normals
  agreeing, both pointing in - so it could never have caught this. Signed volume does, and
  was confirmed to fail on the 0.15.0 files.

## 0.15.1 — interchange fixes

- **Fix: ramp rails sat crossways to the road.** They were axis-aligned boxes, so on any ramp not
  heading north-south they ran perpendicular to it - and their colliders *were* rotated, so the
  wall you hit was not the wall you saw. Rails are now one continuous wall per run, extruded
  along the ramp, with a trimesh collider built from the same triangles. They stop where a ramp
  comes alongside the arterial, which is where you merge.
- **Fix: z-fighting.** The grass and every at-grade road were both at exactly y = 0; ramps were
  laid *on top of* the carriageway where they left it; the bridge deck's top was level with the
  road on it; and the Hermite ramps overshot a few mm below grade near their ends. The ground now
  sits 8 cm down, ramps start beside the carriageway, the deck is 3 cm thinner (clearance still
  5.00 m), and ramp heights ease between their ends instead of following the curve's overshoot.
- New `interchange_finish` test: sideways rays from every raised ramp must hit its rail at the
  same distance all the way round, and a sweep of 9,000+ points finds no two surfaces within
  5 mm. Both halves were checked against the old bugs (rails 3 m out; 267 coplanar points).

## 0.15.0 — proxy bodies for every vehicle

- **Low-poly proxy models** for all eight vehicles (`models/vehicles/*.glb`, 132-192 tris),
  assigned to their profiles. Built from each profile's own dimensions: inside the collision
  box in length and height, out to the track in width with the sills inside the tyres so the
  wheels sit in open arches, body colour baked from the profile. Glass, lights and trim are
  separate materials.
- Physics is untouched - the collider is still the `body_size` box, and every handling number
  is identical (0-100 in 4.35 s, 120-0 in 52.1 m, 1.26 deg over the bumps).
- `tools/build_vehicles.py` + `tools/glb.py` regenerate them from the profiles (a small glTF
  writer; no Blender needed).

## 0.14.0 — highway interchange

- **New world: Highway Interchange.** Six-lane mainline, an arterial 6.4 m above it on a 92 m
  bridge (5.00 m clearance, solid deck), and a partial cloverleaf - two direct ramps
  (365 m, 101 m radius, 2.6 % grade) and two loops (395 m, 52 m radius, 3.9 %). Dimensions are
  AASHTO-ish: 12 ft lanes, 10 ft shoulders, 12 m median, 16 ft 6 in clearance, and a loop
  radius that suits its 40 km/h design speed. Barriers where a ramp is high enough to fall off.
- Ramps are built as geometry and then *measured*: length, tightest radius and steepest grade
  are printed on build and asserted by the tests.
- Roads use trimesh colliders taken from the same triangles as the visible surface, so a wheel
  on a banked, climbing ramp is on exactly what it looks like it is on.
- **Fix (harness):** a per-test time limit was compared against the old fixed one, so a long
  test reported a false timeout after it had already passed.
- Tests: `interchange` (geometry, surfaces, clearance, no ramp clashes) and
  `interchange_drive` (all four ramps driven mainline to arterial).

## 0.13.0 — sound

- **Engine, tyres, wind and impacts.** Files are found by name in `audio/default/` or
  `audio/<car profile>/` (or `user://audio/…`), with per-vehicle overrides and a fallback;
  anything missing is silent. See `audio/README.md`. Engine layers named for the rpm they were
  recorded at are crossfaded and pitched to the current rpm, which comes from a pretend gearbox
  (`engine_idle_rpm`, `engine_redline_rpm`, `gear_count` per profile). Skid, roll, wind and
  scrape follow the physics; impacts and bumps pick a random variant with pitch variance.
- **Impact reporting** on the car (`impacted` signal): the loudest contact per step as a
  velocity change, so it means the same thing on a quad and a 16 t truck. The tyres never
  trigger it - they are shape casts, not colliders.
- **Audio recorded with the take**: the master mix is captured to a .wav beside the take,
  carried along by Export, and loaded onto the Maya time slider lined up with the animation.
  Real-time only: a headless run has no audio clock and it does nothing.
- Tests: `audio_files`, `audio_engine`, `audio_impact` (Godot) and three Maya tests for the
  sound node's placement, a take without audio, and a missing .wav.

## 0.12.1 — tall vehicles could not move

- **Fix:** the City Bus and Garbage Truck sat on the road and would not drive. `main.tscn`
  spawns every vehicle at 1.5 m, which suits a sedan; a bus rests at 1.87 m, so it started
  with its body 2 cm inside the road and the solver held it there. The car now measures its
  own rest height and lifts itself clear of the ground on the first physics tick (it never
  lowers itself, so dropping a car onto its wheels still works). *Recover upright* used a
  fixed 1 m drop and had the same problem; it now uses the vehicle's rest height too.
- 0.12.0 hid this: the tests spawned each vehicle at its own ride height instead of using the
  scene's. New `spawn` check per vehicle does what a player does - pick it, hold the throttle -
  and asserts it reaches 20 km/h with all four wheels down and its body clear of the road.

## 0.12.0 — four more vehicles and a city

- **Vehicles:** Quad ATV (320 kg), Stretch Limo (2.6 t, 8.5 m), City Bus (12 t, 12 m) and
  Garbage Truck (16 t). All pass the settle / full-lock / flick checks. Rear spring rates are
  set so each sits level under its own weight bias.
- **City worlds:** a New York grid at real dimensions (900 x 264 ft blocks, 100 ft avenues,
  60 ft streets, 15 ft sidewalks, 6 in curbs). 10 blocks (640 x 512 m) or 18 (945 x 611 m).
  Buildings, curbs, hydrants and poles collide; markings are visual only. Merged render meshes
  keep it to six meshes and 662 colliders - 15x real time headless.
- **Cameras scale with the vehicle**: the framing tuned for a 4.4 m sedan put the side camera
  inside a 9.5 m truck.
- Tests: the full-lock check now allows a vehicle to tip when its centre of mass is genuinely
  above what its tyres can hold (quad, truck) instead of assuming sedan proportions; each
  vehicle is dropped from its own ride height; the ride-height prediction accounts for weight
  bias (it was 9 mm out on the limo). 8 cars x 3 checks, 6 worlds, all pass.

## 0.11.0 — constrained models, skid curves, five more cameras

- **Maya: attaching a car model now uses parentConstraints.** The model stays in its own
  hierarchy instead of being moved into the rig; only its top group is placed under
  `DrivingRig_world` so it still picks up world scale. Detach deletes the constraints and puts
  everything back exactly where you placed it.
- **Maya: Create Skid Curves.** NURBS curves for every stretch where a tyre was sliding, built
  from data the take already carries (contact point, grounded, slip). Each has the wheel, start
  and end frame, peak slip, length, and a keyed `drvIntensity` for smoke or dust.
- **Five more cameras** (14 total): crane, drone, lowchase, pan, rearwheel. All recorded into
  takes and available in watch mode, so a replay now offers 28 angles.
- **Fix:** adding cameras without moving `O_ACTIVE` made the extra ones overwrite the next
  field and corrupted every take written. New `layout` test asserts the two agree.
- `.gitignore` now covers `__pycache__/` and `*.pyc` - Maya rewrites those on every import.

## 0.10.0 — watch mode

- **RB / V: watch a replay full screen.** The browser panel hides, the car parks, and the take
  plays with the whole screen free. Y/C cycles the nine live cameras aimed at the ghost *and*
  the nine angles the take recorded (`cams.*`), so you can watch it back as shot or from any
  other angle. The HUD shows the take time and camera name. RB or Tab returns to the browser.
- Camera cycling now goes backwards too (D-pad left / Z).
- Ghost play/pause moved to L3 (P on the keyboard) to free RB.
- New `watch_mode` test: panel hidden, car parked, ghost still running, 9 + 9 cameras, each
  recorded camera matching the file to 0.0000 m, and Tab returning to the browser.

## 0.9.2 — grip feel, and reverse on its own button

- **The modes felt like ice because of the tyre curve, not the grip level.** 0.9.1 moved the
  peak slip angle from 8 to 12.8 deg to add warning; that cut grip at the small slip angles
  normal cornering uses by about 30 % (0.61 g vs 0.86 g at 4 deg), so the car slid before it
  bit. Peak is back at 8 deg - identical to Standard up to the limit - with a high falloff
  floor instead, so grip holds at 1.12 g at 32 deg of slip where Standard falls to 0.94.
- Brake boost cut from x2.6 to x1.7: the wheels used to lock at about a third of the pedal.
  They now lock past ~70 %, so you can threshold-brake and still lock them if you stamp.
- Low Grip is a wet road (0.90 mu) rather than sheet ice (0.63).
- **Reverse is its own gear.** Gamepad X / keyboard X selects it at a standstill; holding the
  brake now only ever brakes. Ghost play/pause moved to RB. New `reverse_gear` test.

Standard is untouched again: 0-100 in 4.35 s, 120-0 in 52.1 m at 1.09 g, 1.26 deg over the bumps.

## 0.9.1 — drive modes made drivable

0.9.0's non-Standard modes fishtailed on any corner and plowed at full lock. Causes and fixes:

- **One grip-falloff floor for all four tyres.** Past peak slip, front and rear grip collapsed
  together: the front stopped steering (plow) and the rear never recovered (spin). Now set
  **per axle** (`falloff_floor_front_scale`, `falloff_floor_rear_scale`), with the front kept
  high so the car still turns when the wheels are wound well past their best angle.
- **Tyres gave almost no warning.** Added `peak_slip_angle_scale` and `falloff_width_scale`;
  the loose modes use 1.6-2.0 for a far wider, more progressive limit.
- **`com_raise` 0.20 in Loose** unloaded the inside wheels to zero in any corner and made the
  car skate (52 deg of slip at a quarter lock). Now 0 for Loose; only Stunt is top-heavy.
- **Drift had too much power for its rear grip** and spun out *in a straight line*. Rebalanced.
- `low_speed_hold` back on everywhere: a slide can be recovered without stopping.
- New `mode_drivable` test on every mode: straight-line tracking, a steady corner that stays a
  corner, and full lock that turns rather than plows. 47 Godot tests.

Standard is untouched and re-verified: 0-100 in 4.35 s, 120-0 in 52.1 m at 1.09 g, 1.26 deg
over the bumps - identical to every earlier release.

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

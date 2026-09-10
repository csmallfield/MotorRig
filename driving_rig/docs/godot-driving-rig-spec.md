# Godot Driving Rig → Maya Pipeline — Build Spec

**Goal:** Drive a proxy car with a gamepad in Godot, record takes, export JSON, rebuild the take on a proxy rig in Maya. A DIY Craft Director replacement, VFX-oriented.

**Non-goals:** Final car geometry, materials, sound, AI traffic, multiplayer, real-time Maya link. No FBX/Alembic export from Godot — neither exists. JSON is the interchange format.

---

## Locked conventions

| | |
|---|---|
| Engine | Godot 4.5+, GDScript, typed vars throughout |
| Physics tick | **240 Hz** (`physics/common/physics_ticks_per_second = 240`). Divides exactly into 24/30/48/60/120. Tune handling *at* 240, not 60. |
| Units | Godot metres. `meta.unit_scale: 100` for Maya cm. |
| Axes | Both apps are right-handed, Y-up, −Z forward. Conversion is a **pure scale** — no axis flip, no quaternion reorder (both xyzw). |
| Rotations | Quaternions on the wire. Never Euler. |
| Interchange | JSON only, one file per take. |
| Car geo in Maya | Importer **builds the proxy from `meta`**. No mesh export. |

**Handling target — "arcade but physical."** Physicality lives in the suspension: real spring-damper per wheel, anti-roll bars, visible dive/squat/roll. Forgiveness lives in the tire model: generous, gently-falling-off grip curve, no snap oversteer, no stall. Should be possible to hit a mark on the third take, not the thirtieth.

---

## Phase 1 — Drivable proxy

**1.1 Scene + shader.** `RigidBody3D` chassis (box mesh + `BoxShape3D`), four cylinder wheel meshes (visual only — no wheel colliders). Triplanar world-space grid shader as a `.gdshader`, applied to both car and terrain in different hues, so scale and slip read at a glance.
*Test:* car falls, lands on a flat plane, rests level.

**1.2 Suspension.** Four `ShapeCast3D` (sphere, radius = wheel radius — the wheel climbs kerbs instead of stabbing through them), cast down from hardpoints. Spring force `F = k·compression − c·compression_velocity` applied at contact point via `apply_force`. Add anti-roll bar coupling per axle.
*Test:* car settles at rest height; push it and it oscillates and damps out; no jitter at rest.

**1.3 Tires + drive.** Per-wheel longitudinal and lateral forces from a slip-clamped friction circle. Throttle/brake torque to rear (or all four). Ackermann steering geometry from `wheelbase`/`track`.
*Test:* accelerates, brakes, turns; body dives under braking, rolls in corners; recoverable slide, no spin-out from a light input.

**1.4 Wheel visuals.** Wheel node chain `steer → susp → spin`, driven from cast results. Spin from contact-patch arc length ÷ radius, **cumulative, never wrapped**.
*Test:* wheels sit on the ground over bumps, steer correctly, spin at a speed that matches the ground.

**1.5 Cameras + terrain.** `SpringArm3D` chase cam with lag, plus a driver-eye cam parented to the chassis. Toggle on gamepad Y / keyboard C. Terrain: procedural heightmap `MeshInstance3D` + matching `ConcavePolygonShape3D`, built so the collision source is swappable for an imported glTF later.
*Test:* Xbox controller drives it (triggers = throttle/brake, left stick = steer), both cams work, car climbs and descends slopes without launching or clipping.

---

## Phase 2 — Recorder

**2.1 Capture.** Ring buffer in `_physics_process`, one sample per tick. Gamepad Start begins a 3-2-1 countdown, then records. Record **8 frames of handle** before and after the marked in/out. Stop on Start again or a max-length cap. Buffer is pre-allocated — no allocation in the physics loop.
*Test:* drive, record 10s, confirm sample count ≈ 240 × 10 + handles.

**2.2 Persistence.** Write to `user://takes/take_####.json`. Include a summary header the browser can read without parsing all samples.
*Test:* file on disk, valid JSON, reopens cleanly.

**2.3 Browser UI.** List of takes with duration, distance, peak speed, max lateral g, airtime frames, thumbnail. Select → replay in-viewport by playing the samples back onto a ghost car (no re-simulation — this validates that the recorded channels are sufficient to reconstruct the take). Delete, rename, mark as favourite.
*Test:* replayed ghost is visually indistinguishable from the live drive.

**2.4 Export.** Copy JSON to a user-chosen path via `FileDialog`.
*Test:* file lands outside `user://` and validates against the schema.

---

## Phase 3 — Maya importer

**3.1 Rig builder.** Python (`maya.api.OpenMaya` + `cmds`). From `meta` alone, build:
`root → chassis → [wheel_FL_steer → wheel_FL_susp → wheel_FL_spin → geo]` ×4, with cube body and cylinder wheels at the recorded dimensions. Locators at contact points. Everything scaled by `unit_scale`.
*Test:* rig appears at correct proportions, hierarchy is clean, nothing skewed.

**3.2 Curve writer.** Resample 240 Hz → target fps **at import time** (raw stays in the JSON so takes can be re-cut later). Build `MTimeArray`/`MDoubleArray` and use `MFnAnimCurve.addKeys()` — not `cmds.setKeyframe` in a loop; on 30 channels that's seconds vs minutes. Chassis quaternion → Euler with continuity unrolling. Suspension → `translateY` on `_susp`. Steer → `rotateY` on `_steer`. Linear tangents on monotonic channels.
*Test:* scrub the timeline; car matches the Godot replay; no flips at ±90° pitch.

**3.3 Spin solve.** Derive spin in Maya rather than reading the baked channel: per frame, project contact-patch delta onto wheel forward, ÷ radius, accumulate; modulate by `ω × (1 + slip_long)` to preserve lockup and wheelspin. Exposed as a re-solve button so it survives retimes and animator-added chassis offsets. Diff against the exported `spin_cumulative` to catch a wrong radius or bad contact offset.
*Test:* wheels don't skate; retiming the chassis 8 frames later keeps spin correct after re-solve.

---

## Schema

```json
{
  "meta": {
    "take": 3, "tick_hz": 240, "unit_scale": 100,
    "up_axis": "Y", "forward": "-Z",
    "collision_source": "proc_heightmap_seed1234",
    "handles": 8, "godot_version": "4.5",
    "body": { "extents": [1.8, 1.2, 4.4], "com_offset": [0, -0.2, 0] },
    "wheelbase": 2.65, "track_f": 1.58, "track_r": 1.56,
    "wheel_radius": 0.34, "wheel_width": 0.24,
    "susp_rest": 0.32, "susp_max_travel": 0.18,
    "hardpoints": [[x,y,z], [x,y,z], [x,y,z], [x,y,z]]
  },
  "samples": [{
    "t": 0.004166,
    "chassis": { "p": [x,y,z], "q": [x,y,z,w] },
    "wheels": [{
      "compression": 0.043,
      "steer": -0.21,
      "spin_cumulative": 14.882,
      "grounded": true,
      "contact_p": [x,y,z],
      "contact_n": [x,y,z],
      "slip_long": 0.02,
      "slip_lat": 0.11
    }],
    "input": { "throttle": 0.8, "brake": 0.0, "steer": -0.3, "handbrake": false },
    "vel": [x,y,z], "angvel": [x,y,z],
    "camera": { "p": [x,y,z], "q": [x,y,z,w], "fov": 50.0 }
  }]
}
```

Wheel order is always **FL, FR, RL, RR**.

Why each field earns its place: `compression` not world wheel position, so Maya stays a *rig* an animator can offset. `input` retained so a take can be re-simulated with retuned car parameters instead of re-driven. `slip_*` and `grounded` are free and give FX their dust/skid/spark triggers. `contact_p` is what the spin solve needs — inner and outer wheels travel measurably different distances through a corner, so chassis translation would give all four the same spin and read wrong. `camera` is optional but cheap, and useful for layout.

---

## Traps

- **`spin_cumulative` must never wrap.** Let it run to 40,000 rad. Wrapping causes a stutter at every wrap in Maya.
- **No allocation inside `_physics_process`.** Pre-size the buffer or the recording itself changes the handling.
- **Don't set RigidBody transforms directly** — forces only, or the sim fights you.
- **When terrain is swapped for real geo**, the Godot collision mesh must be the *same* geometry as the Maya set, not a simplified proxy. Centimetres of difference read instantly as floating or sunken wheels.
- **`VehicleBody3D` is deliberately unused** — still prototype-grade in Godot 4, and it hides the per-wheel compression and slip values this whole pipeline is built to export.
- **Retune handling if `tick_hz` ever changes.** Spring behaviour is rate-dependent.

---

## Order of work

Close the loop before polishing anything: a cube on a plane → record → JSON → Maya locator with keys. Once that round trip works end to end, every later step is tuning inside a system that's already proven.

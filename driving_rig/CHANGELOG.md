# Changelog

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

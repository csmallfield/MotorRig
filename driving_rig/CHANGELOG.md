# Changelog

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

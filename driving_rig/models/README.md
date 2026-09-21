# Vehicle proxy bodies

Low-poly stand-ins for the eight vehicles — better than a cube, deliberately not a hero asset.
Already assigned: each car profile's `chassis_scene` points at its `.glb`.

| file | vehicle | triangles | size (W × H × L) |
|---|---|---|---|
| `vehicles/sedan_awd.glb` | Proxy Sedan AWD | 192 | 1.70 × 1.00 × 4.40 m |
| `vehicles/hatch_fwd.glb` | Hatchback FWD | 192 | 1.60 × 0.95 × 4.00 m |
| `vehicles/sports_rwd.glb` | Sports RWD | 192 | 1.76 × 0.80 × 4.50 m |
| `vehicles/suv_awd.glb` | SUV AWD | 192 | 1.79 × 1.25 × 4.80 m |
| `vehicles/limo.glb` | Stretch Limo | 192 | 2.00 × 1.45 × 8.50 m |
| `vehicles/city_bus.glb` | City Bus | 144 | 2.55 × 3.10 × 11.97 m |
| `vehicles/garbage_truck.glb` | Garbage Truck | 156 | 2.50 × 3.40 × 9.49 m |
| `vehicles/quad_atv.glb` | Quad ATV | 132 | 0.66 × 0.55 × 1.83 m |

Metres, Y up, −Z forward, origin at the chassis centre — the rig's convention, so they drop
straight in with no transform.

Each body is built from its own profile's numbers:

- **Length and height stay inside the collision box** (`body_size`), so what you see is still
  what the physics uses. Nothing sticks out past the collider.
- **Width goes out to the track** — wider than the collision box, which is narrower than a real
  car — with the sills pulled in inside the tyres' inner faces so the wheels sit in open arches.
- **The body colour comes from the profile** (`body_color`), baked into the glb's material.
  Glass, lights and trim are separate materials.

## Replacing one

Model whatever you like, export as `.glb`, and set `chassis_scene` on the car profile. Keep it
inside `body_size` (or change `body_size` to match, which does change the collider), point −Z
forward with the origin at the chassis centre, and use `chassis_transform` on the profile to
nudge the fit without re-exporting. `hide_chassis_in_driver_cam` is on for these because they
have no interior — turn it off for a model with a modelled cabin and see-through glass.

## Rebuilding these

`tools/build_vehicles.py` generates them from the profiles (`tools/glb.py` is a small glTF
writer, no Blender needed). Every shape is a hexahedron between two cross-sections, which is
all a car silhouette needs.

# Vehicle proxy bodies

Low-poly stand-ins for the ten vehicles — better than a cube, deliberately not a hero asset.
Already assigned: each car profile's `chassis_scene` points at its `.glb` - except the city bus,
garbage truck, quad, dune buggy and hatchback, which now use full models (below).

## Full models

| folder | vehicle | triangles | notes |
|---|---|---|---|
| `vehicles/city_bus/` | LINEA 12 city bus | 329,836 | textured PBR, cabin with 31 seats, see-through glass, its own wheels and steering wheel - see its README |
| `vehicles/garbage_truck/` | ORDA R9 rear-loading refuse truck | 321,238 | textured PBR, three-seat cab, see-through glass, static compactor and bin lifter, its own wheels and steering wheel - see its README |
| `vehicles/quad_atv/` | ROVE Q4 utility-sport quad | 870,609 | textured PBR, open rider station, racks and winch, static suspension and powertrain detail, its own wheels, brake calipers (steer and travel, don't spin) and handlebars on the steering-wheel node - see its README |
| `vehicles/dune_buggy/` | SABLE X4 two-seat dune buggy | 611,988 | textured PBR, open cockpit with two bucket seats, roll cage, exposed rear engine, its own wheels, brake calipers and steering wheel - see its README |
| `vehicles/hatch_fwd/` | VELA 1600 S late-80s three-door hatchback | 1,051,578 | textured PBR, full cabin, see-through glass, 608 separate meshes (each wheel is a group of 33), its own wheels, front calipers and steering wheel. **Roof is 33 cm above the 0.95 m collision box** - accepted for now, so in a rollover the roof sinks into the ground - see its README |

All five are built on the rig hierarchy, so the car drives the model's own wheels (see the main README,
"Models with their own wheels"). Their embedded textures are extracted next to the `.glb` on import;
`review/` holds offline renders and is kept out of the game with a `.gdignore`.

| file | vehicle | triangles | size (W × H × L) |
|---|---|---|---|
| `vehicles/sedan_awd.glb` | Proxy Sedan AWD | 192 | 1.70 × 1.00 × 4.40 m |
| `vehicles/hatch_fwd.glb` | Hatchback FWD (not used - see below) | 192 | 1.60 × 0.95 × 4.00 m |
| `vehicles/sports_rwd.glb` | Sports RWD | 192 | 1.76 × 0.80 × 4.50 m |
| `vehicles/suv_awd.glb` | SUV AWD | 192 | 1.79 × 1.25 × 4.80 m |
| `vehicles/limo.glb` | Stretch Limo | 192 | 2.00 × 1.45 × 8.50 m |
| `vehicles/city_bus.glb` | City Bus (not used - see below) | 144 | 2.55 × 3.10 × 11.97 m |
| `vehicles/garbage_truck.glb` | Garbage Truck (not used - see below) | 156 | 2.50 × 3.40 × 9.49 m |
| `vehicles/quad_atv.glb` | Quad ATV (not used - see below) | 132 | 0.66 × 0.55 × 1.83 m |
| `vehicles/monster_truck.glb` | Monster Truck | 192 | 2.60 × 1.25 × 4.95 m |
| `vehicles/dune_buggy.glb` | Dune Buggy (not used - see below) | 204 | 1.54 × 1.04 × 3.46 m |

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

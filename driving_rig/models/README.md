# Vehicle proxy bodies

Low-poly stand-ins for the ten vehicles — better than a cube, deliberately not a hero asset.
None of these are assigned any more: every profile now uses a full model (below). They stay
here, and `tools/build_vehicles.py` still builds them, as simple stand-ins to fall back on.

## Full models

| folder | vehicle | triangles | notes |
|---|---|---|---|
| `vehicles/city_bus/` | LINEA 12 city bus | 329,836 | textured PBR, cabin with 31 seats, see-through glass, its own wheels and steering wheel - see its README |
| `vehicles/garbage_truck/` | ORDA R9 rear-loading refuse truck | 321,238 | textured PBR, three-seat cab, see-through glass, static compactor and bin lifter, its own wheels and steering wheel - see its README |
| `vehicles/quad_atv/` | ROVE Q4 utility-sport quad | 870,609 | textured PBR, open rider station, racks and winch, static suspension and powertrain detail, its own wheels, brake calipers (steer and travel, don't spin) and handlebars on the steering-wheel node - see its README |
| `vehicles/dune_buggy/` | SABLE X4 two-seat dune buggy | 611,988 | textured PBR, open cockpit with two bucket seats, roll cage, exposed rear engine, its own wheels, brake calipers and steering wheel - see its README |
| `vehicles/hatch_fwd/` | VELA 1600 S late-80s three-door hatchback | 1,051,578 | textured PBR, full cabin, see-through glass, 608 separate meshes (each wheel is a group of 33), its own wheels, front calipers and steering wheel. **Roof is 33 cm above the 0.95 m collision box** - accepted for now, so in a rollover the roof sinks into the ground - see its README |
| `vehicles/sedan_awd/` | VAEL S26 AWD sedan (the reference car) | 1,650,778 | textured PBR, full cabin, see-through glass, 755 meshes (each wheel a group of 71), its own wheels, four calipers and steering wheel. Roof 26 cm above the 1.0 m collision box, nose/tail 9 cm past it - same as the hatchback, accepted. The file also carries the six original proxy meshes, unused by any node, so they never appear. `renders/` is the artist's review set |
| `vehicles/sports_rwd/` | VANTA V87 GT late-80s sports coupe | 820,420 | textured PBR, 2+2 cabin, alpha glass (its transmission extension is ignored by Godot; the alpha fallback is what shows), its own wheels, calipers and steering wheel. Roof 29 cm above the 0.85 m collision box - accepted, like the hatchback |
| `vehicles/suv_awd/` | Kestrel S6 five-seat SUV | 1,766,101 | textured PBR, full cabin, nine glass panes, its own wheels, calipers (with pistons and wordmarks) and steering wheel |
| `vehicles/limo/` | AUREL Regent 600 stretch limousine | 1,542,411 | textured PBR, formal cabin, its own wheels; calipers, control arms and dampers ride on `_susp`. Its visible steering wheel sits under `steering_visual_pivot`, moved to where the cabin really is, so the profile's `driver_eye` was moved to match (z -3.2 -> -1.27) |
| `vehicles/monster_truck/` | BRONT M5 monster truck | 992,522 | textured PBR, pickup cab with roll cage, single-mesh 0.84 m wheels with calipers on `_susp`. Body fits the collision box; frame, axles and powertrain hang 41 cm below it between the wheels |

All ten are built on the rig hierarchy, so the car drives the model's own wheels (see the main README,
"Models with their own wheels"). Their embedded textures are extracted next to the `.glb` on import;
`review/` holds offline renders and is kept out of the game with a `.gdignore`.

| file | vehicle | triangles | size (W × H × L) |
|---|---|---|---|
| `vehicles/sedan_awd.glb` | Proxy Sedan AWD (not used - see below) | 192 | 1.70 × 1.00 × 4.40 m |
| `vehicles/hatch_fwd.glb` | Hatchback FWD (not used - see below) | 192 | 1.60 × 0.95 × 4.00 m |
| `vehicles/sports_rwd.glb` | Sports RWD (not used - see below) | 192 | 1.76 × 0.80 × 4.50 m |
| `vehicles/suv_awd.glb` | SUV AWD (not used - see below) | 192 | 1.79 × 1.25 × 4.80 m |
| `vehicles/limo.glb` | Stretch Limo (not used - see below) | 192 | 2.00 × 1.45 × 8.50 m |
| `vehicles/city_bus.glb` | City Bus (not used - see below) | 144 | 2.55 × 3.10 × 11.97 m |
| `vehicles/garbage_truck.glb` | Garbage Truck (not used - see below) | 156 | 2.50 × 3.40 × 9.49 m |
| `vehicles/quad_atv.glb` | Quad ATV (not used - see below) | 132 | 0.66 × 0.55 × 1.83 m |
| `vehicles/monster_truck.glb` | Monster Truck (not used - see below) | 192 | 2.60 × 1.25 × 4.95 m |
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

Model whatever you like, export as `.glb`, and set `chassis_path` on the car profile. Keep it
inside `body_size` (or change `body_size` to match, which does change the collider), point −Z
forward with the origin at the chassis centre, and use `chassis_transform` on the profile to
nudge the fit without re-exporting. `hide_chassis_in_driver_cam` is on for these because they
have no interior — turn it off for a model with a modelled cabin and see-through glass.

## Rebuilding these

`tools/build_vehicles.py` generates them from the profiles (`tools/glb.py` is a small glTF
writer, no Blender needed). Every shape is a hexahedron between two cross-sections, which is
all a car silhouette needs.

## Textures live beside the models

Each full model's `.glb` holds geometry and materials only; its textures are the PNGs next to it
(`<model>_<texture>.png`), referenced by name. That keeps every file under GitHub's 100 MB
limit (they were 35–135 MB with the textures embedded, now 13–62 MB) and stops each texture
being stored twice, since Godot extracts them there on import anyway. Godot and the Maya car
builder both read them from there; keep them together when moving a model.

A new model that arrives with embedded textures: open it in Godot once (which extracts them),
then run `python tools/strip_glb_textures.py models/vehicles/<car>/<model>.glb`. It points the
.glb at those PNGs (writing any that are missing first) and checks nothing else changes. Arnold's
`.tx` conversions also land beside them and are git-ignored.


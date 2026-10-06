# BRONT / M5 - monster truck, review v01

Fictional two-seat pickup-style monster truck built around the supplied
`monster_truck_bind.glb`. Slate-blue and ivory paint, orange mechanical accents,
clear separate glazing, an open ribbed cargo bed, and exposed running gear.

This is an art-review asset, not an engine-tested release. It has not been opened
in Unreal Editor or run in the user's game. The review images are renders of this
model's geometry and materials, not generated concept illustrations.

## Files

- `BRONT_M5_monster_truck_v01.glb`: complete GLB with all 26 PNG images embedded.
- `review/`: front, rear, driver-station and rear-axle detail PNGs, 2000 x 1250 each.
- `textures/`: standalone editable copies of all embedded maps.
- `reference/monster_truck_bind.glb`: the unchanged original rig/proxy.
- `asset_manifest.json`: geometry statistics, group breakdown, bounds and checksum.
- `validation_report.json`: checks on the serialized GLB and their limitations.
- `review_manifest.json`: review method, dimensions and checksums.
- `material_manifest.json`: material parameters and texture assignments.
- `source/`: deterministic geometry, texture, export, validation and rendering scripts.

The studio floor, lighting environment, contact-shadow card and review cameras
are not exported. No website, Unreal project, native material graphs or Blender
scene is included; the editable source is procedural Python and the GLB mesh data.

## Statistics

| Item | Value |
|---|---:|
| Triangles | 992,522 |
| Exported vertices | 696,440 |
| Mesh nodes | 22 |
| Material definitions | 29 |
| Material primitives | 118 |
| Embedded PNG images | 26 |
| Total nodes | 39 |
| Original nodes retained | 25 |
| Added groups | 10 chassis children + 4 brake-caliper children |
| Seats | 1 driver + 1 passenger |
| GLB size, decimal MB | 72.76 |

One high-detail version is supplied. There is no LOD reduction, draw-call
consolidation, lightmap-UV pass, engine-generated collision or texture-streaming
conversion. Tyre paddles, springs, rim spokes and most mechanical hardware are
modelled geometry rather than normal-map-only detail.

## Original dimensional and binding contract

Metres, Y up, -Z forward. All 25 original node names, exact local translations,
rotations, scales and original parent relationships are retained. Original
world-space pivot matrices and axes were independently compared and match exactly.

| Supplied constraint | Retained value |
|---|---|
| Collision-body width x height x length | 2.60 x 1.30 x 5.00 m |
| Wheelbase | 3.30 m |
| Front / rear wheel-centre track | 3.10 / 3.10 m |
| Four tyre radii | 0.84 m |
| Four wheel widths | 0.90 m |
| Wheel-to-wheel visual width | 4.00 m |
| Original chassis bind-pose Y | 1.7201206896551724 m |
| Top of original body collision box | 2.3701206896551724 m above world ground |

The 1.30 m collision height is the body box itself, not the truck's height above
its wheels. The large original tyres already extend outside its 2.60 m width.
Neither the wheels nor the rig have been repositioned to suit the new design.

The main pickup shell and cargo bed fit inside the original collision envelope.
Exposed axles, suspension links, lower chassis members and skid plates extend
below the body-only box. Mirrors, step rails and other fittings are separate
visual accessories. The complete visual bounds are recorded in the manifest;
do not substitute those bounds for the game's original collision dimensions.

`body_geo` contains the detailed shell rather than an opaque cube. `nose_geo`
remains as an empty original transform. The supplied collision dimensions remain
in metadata and the unchanged reference file. Continue using the game's existing
collision shape; no new collider has been generated.

### Moving and static parts

All ordinary additions are children of `chassis`. Tyres, rims and brake rotors
remain on the original wheel mesh/spin nodes. The steering rim, spokes and marker
retain the original steering-wheel hierarchy and local coordinate frames.

`brake_FL_geo`, `brake_FR_geo`, `brake_RL_geo` and `brake_RR_geo` are attached beneath
the corresponding original `wheel_*_susp` nodes. They inherit existing steering
and suspension transforms but do not spin with the tyres. No new controls are
required for these groups.

Axle housings, links, coil springs, dampers, rods, brake lines and driveshafts are
static bind-pose detail. They do not articulate or deform during suspension
travel. Doors, tailgate, wipers, mirrors, lights, engine details, seat belts and
bed equipment are also static. No skins or animation clips were added. Preserve
the complete hierarchy when importing; merging all geometry would remove the
independent wheel and steering behaviour.

## Geometry and visual finish

The body includes a crowned bonnet, contrasting centre stripe, real louvred vent
openings, shaped fenders with return lips, inner arch liners, fixed door seams,
handles, separate window frames/seals, a crowned roof, mirrors, two parked wipers,
recessed projector lights and radiator grille, bumpers and recovery eyes.

The cab has two bucket seats with actual shoulder-harness slots, separate padded
inserts, stitched four-point belts, a cage, sealed footwell liners, dashboard,
static instrument display, switches, perforated pedals, shifter, handbrake,
cupholders, door cards, grab handles, sun visors, mirrors and an extinguisher.
The instrument artwork is a static authored texture, not game telemetry.

The cargo bed has an actual open interior, ribbed floor, wheel tubs, cutouts around
the rear suspension towers, tie-down rings, a fuel cell, filler hardware, battery
case, hoses and tubular bracing. The tailgate has a recessed panel, handle, hinge
hardware and separate rear-light assemblies. The tailgate does not animate.

Underbody detail includes a triangulated ladder-style chassis, two axles,
bolted differential covers, driveshafts, transmission/sump housings, four-link
visual suspension, eight coil-over assemblies, remote reservoirs, hoses,
exhaust collectors, silencers, perforated shields and genuinely open tailpipes.
These are plausible fictional visual assemblies, not engineering-certified parts.

The wheels have balloon-profile tyres, large individually modelled chevron
paddles, shoulder protection, moulded sidewall artwork, deep-dish split-spoke
rims, beadlock rings, separate bolts, hubs and drilled brake rotors. No additional
axle, dual-wheel set or spare tyre was added.

## Materials and textures

Materials use glTF metallic/roughness PBR with embedded UVs, normals and tangent
vectors. Paint also carries `KHR_materials_clearcoat` (factor 0.17, roughness 0.20)
with core metallic/roughness values present as a fallback. No Unreal-native
shader graph, light-switch logic or runtime instrument control is supplied.

| Texture set | Resolution / maps |
|---|---|
| Blue exterior paint | 4096 x 4096 base colour, ORM, normal |
| Ivory paint | 2048 x 2048 base colour, ORM, normal |
| Carbon twill | 2048 x 2048 base colour, ORM, normal |
| Seat upholstery | 2048 x 2048 base colour, ORM, normal |
| Rubber floor | 2048 x 2048 base colour, ORM, normal |
| Brushed metal | 2048 x 2048 base colour, ORM, normal |
| Tyre sidewall | 2048 x 2048 base colour, ORM, normal |
| Tread rubber | 2048 x 2048 base colour, ORM, normal |
| Decal atlas | 2048 x 2048 RGBA |
| Instrument display | 1024 x 512 |

ORM packs red = occlusion, green = roughness, blue = metallic. Occlusion is
neutral white, not baked scene lighting. Base-colour and emissive images are
colour textures; normal and ORM images are data maps. Normals follow the glTF
tangent-space convention. Check the target importer's normal-map handling.

Separate glass groups:

| Node | Material | Alpha / roughness |
|---|---|---|
| `glass_windshield_geo` | `Glass_Windscreen` | 0.065 / 0.060 |
| `glass_windows_geo` | `Glass_Side` | 0.095 / 0.075 |

Both use double-sided core `BLEND` materials and are intentionally very clear.
The side group includes door, quarter and rear-cab glazing. Window openings are
real opaque-shell apertures, not alpha-painted regions of a solid body cube.
Final glass appearance, sorting and shader import remain engine-side checks.

All new geometry and texture artwork were authored for this vehicle; no
third-party vehicle meshes or photographic textures are included. The underlying
binding hierarchy is from the user's supplied file. Font files are not included.

## Validation performed

The delivered GLB passed exact original-name, local/world transform, parenting
and metadata checks; four wheel-radius and width checks; wheelbase and track
checks; main shell/bed envelope checks; valid buffer ranges and indices; finite
unit normals/tangents; tangent orthogonality; accessor bounds; zero degenerate
triangles after export; PNG decoding and byte parity with the standalone maps;
separate low-alpha glass checks; 17 ray samples through the window apertures;
and an independent Trimesh import reproducing 992,522 triangles.

All 118 review-render primitives were additionally compared against the
serialized GLB for positions, UVs and indices and matched exactly.

Not performed: Unreal import/material compilation, runtime animation binding,
full steering/suspension articulation clearance, exhaustive self-intersection
or manifold inspection, or formal Khronos glTF Validator validation. The attempt
to install that validator was blocked by network resolution in this environment.
The model is an assembly with openings and separate surfaces, not a single
watertight manufacturing mesh.

## Rebuilding and editing

Run from the package directory with a compatible Python environment:

```sh
python -m pip install -r source/requirements.txt
python source/build_monster.py
python source/export_glb.py
python source/validate_asset.py
```

These commands use the delivered textures. To regenerate artwork first:

```sh
python source/make_textures.py
```

Font discovery includes common Linux, Windows and macOS paths. Different fonts
change the label artwork. Existing delivered textures do not need fonts installed.

Review rendering, sequentially to limit peak memory:

```sh
python source/render_monster.py front final
python source/render_monster.py rear final
python source/render_monster.py driver final
python source/render_monster.py mechanical final
```

The renderer uses VTK PBR, an analytic studio environment, SSAO, tone mapping and
a studio-only contact-shadow card. It selects EGL on Linux and a standard VTK
window elsewhere. A working offscreen graphics context is required. The delivered
PNGs can be reviewed without installing these dependencies.

Build/export generate intermediate pickle files. The optional local wheel cache
is only for caches generated by the authoring process. Never load an untrusted
pickle. No pickle caches, runtime executables, third-party packages or font files are
included in the archive.

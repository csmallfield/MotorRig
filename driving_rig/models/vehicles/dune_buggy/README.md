# SABLE / X4 - dune buggy, review v01

Fictional two-seat, open-sided dune buggy authored around the supplied
`dune_buggy_bind.glb`. Sage and ivory bodywork, orange trim, graphite tubular
frame, exposed mechanical assemblies, and clear separate glazing.

This is an art-review asset. It has not been imported into Unreal Editor or
run inside the user's game. The review PNGs are offline renders of the exported
geometry and authored materials, not generated concept illustrations.

## Files

- `SABLE_X4_dune_buggy_v01.glb`: the complete, self-contained asset.
- `review/`: front, rear, mechanical-detail and driver-station PNGs, 2000 x 1250 each.
- `textures/`: standalone editable copies of every embedded texture.
- `reference/dune_buggy_bind.glb`: the unchanged supplied proxy and original rig.
- `asset_manifest.json`: mesh statistics, bounds, group breakdown and SHA-256.
- `validation_report.json`: checks against the serialized GLB and their limits.
- `review_manifest.json`: image sizes and hashes, render method and model checksum.
- `material_manifest.json`: authored material settings and texture assignments.
- `source/`: procedural geometry, artwork, export, validation and render scripts.

The studio floor, environment, soft contact-shadow card and review cameras are
not part of the GLB. There is no review website, Unreal project or Blender scene.
The source is procedural Python; the GLB is editable in a compatible DCC.

## Statistics

| Item | Value |
|---|---:|
| Triangles | 611,988 |
| Exported vertices | 455,028 |
| Mesh nodes | 21 |
| Material definitions | 29 |
| Material primitives | 109 |
| Embedded PNG textures | 26 |
| Total nodes | 38 |
| Original nodes retained | 25 |
| Added groups | 9 chassis children + 4 brake-caliper children |
| Seats | 1 driver + 1 passenger |
| GLB size, decimal MB | 58.89 |

This is one high-detail version, with no LOD reductions, draw-call consolidation,
lightmap-UV pass, texture-streaming conversion or engine-generated collision.
The tread blocks, beads, rims, fasteners and brake rotors are modelled geometry.
The four wheel assemblies account for 376,208 of the triangles.

## Dimensional and binding contract

Metres, Y up, -Z forward. All 25 original node names, exact local translations,
rotations and scales, original parent relationships and scene metadata remain
unchanged. Original world-space pivots and axes were compared independently.

| Supplied constraint | Preserved value |
|---|---|
| Collision-body width x height x length | 1.60 x 1.10 x 3.60 m |
| Wheelbase | 2.60 m |
| Front / rear wheel-centre track | 1.80 / 1.80 m |
| All four tyre radii | 0.40 m |
| All four wheel widths | 0.32 m |
| Chassis bind-pose Y | 0.9618053097120214 m |
| Original collision-body top above world ground | 1.5118053097120214 m |
| Overall wheel-to-wheel width | 2.12 m |

The 1.10 m collision-body height is not the vehicle's height above the road.
The wheels already extend outside the original 1.60 m collision width; their
positions and width have not been changed to suit the new design.
The few-micron front/rear bind-height difference is retained rather than fixed.

The main opaque shell fits inside the original collision volume. Rock rails
extend approximately 35.4 mm beyond each collision side; a lower skid fastener
extends less than 1 mm below it. Mirrors and other small fittings are accessories.
The complete visible asset bounds are recorded in `asset_manifest.json`.

The original `body_geo` cube has been replaced by the detailed shell. `nose_geo`
is retained as an empty transform. The original collision dimensions remain in
metadata and the unchanged reference file, not as an opaque cube inside the car.
Continue using the game's existing collision shape.

### Moving and static parts

All ordinary new body, frame, engine, trim, glass and interior groups are children
of `chassis`. The tyre, wheel and rotor meshes remain under their original
`wheel_*_geo` / spin hierarchy. Steering rim, spokes and marker retain their
original steering-wheel nodes and local frames.

The four added `brake_FL_geo`, `brake_FR_geo`, `brake_RL_geo` and `brake_RR_geo`
groups are children of the corresponding original `wheel_*_susp` nodes. They
inherit existing steering and suspension transforms but do not inherit wheel
spin. No new animation controls are required for them.

Exposed wishbones, springs, dampers, half-shafts and hoses are static bind-pose
chassis details. They do not deform or articulate as the wheels travel. Doors,
wiper, mirrors, engine components, radiator fans, shifter and harnesses are also
static. No skins or animation clips have been added. Preserve the complete
hierarchy when importing; merging everything into one mesh would remove the
independent wheel and steering behaviour.

## Geometry and finish

The body has a compound-curved hood, separate ivory centre section, modelled
vent apertures and louvres, wheel openings, inset half-door seams, side intake
openings, fasteners, a thin composite roof and tubular recovery bars.

The cockpit has two composite bucket-seat shells with real shoulder-harness
slots, upholstered inserts and bolsters, four-point harnesses, dashboard,
instruments, switchgear, pedals, a shifter, handbrake, passenger grab handle,
rubber floor and a small extinguisher. It is a simple occasional interior-view
cockpit, not a fully operable simulation. The dashboard is a static texture.

Rear mechanical details include cast housings, cooling fins, a bolted sump,
intake plumbing, coolant hoses, wiring, a twin-fan radiator, fuel cell, battery,
exhaust headers, muffler, perforated heat shield and a hollow tailpipe opening.
All are authored visual representations, not an engineering-certified assembly.

The off-road wheels have chevron tread blocks, shoulder lugs, moulded sidewall
lettering, recessed split-spoke rims, beadlock hardware, drilled brake discs,
hubs, valve stems and separate non-spinning calipers.

## Materials and textures

Materials use glTF metallic/roughness PBR with UVs, normals and tangent vectors.
Paint also includes `KHR_materials_clearcoat` with factor 0.17 and roughness 0.20;
core metallic/roughness values remain present as a fallback. No Unreal-native
material graph or runtime light-switch logic is included.

| Set | Resolution / maps |
|---|---|
| Sage exterior paint | 4096 x 4096 base colour, ORM, normal |
| Ivory paint | 2048 x 2048 base colour, ORM, normal |
| Carbon twill | 2048 x 2048 base colour, ORM, normal |
| Upholstery | 2048 x 2048 base colour, ORM, normal |
| Rubber floor | 2048 x 2048 base colour, ORM, normal |
| Brushed metal | 2048 x 2048 base colour, ORM, normal |
| Tyre sidewall lettering | 2048 x 2048 base colour, ORM, normal |
| Tread rubber | 2048 x 2048 base colour, ORM, normal |
| Decal atlas | 2048 x 2048 RGBA |
| Instrument display | 1024 x 512 |

ORM packs red = occlusion, green = roughness, blue = metallic. Occlusion is
neutral white; no scene lighting is baked into these channels. Base-colour and
emissive maps are colour images; ORM and normal maps are data images. Normals
were authored for the glTF tangent-space convention. Material appearance and
normal-map handling still need checking in the target importer.

Separate glass nodes:

| Node | Material | Alpha / roughness |
|---|---|---|
| `glass_windshield_geo` | `Glass_Windscreen` | 0.065 / 0.060 |
| `glass_deflectors_geo` | `Glass_Deflectors` | 0.095 / 0.075 |

These are double-sided core `BLEND` materials, intentionally very transparent.
The cockpit sides are mostly open; only the front screen and small side wind
deflectors are glazed. Opaque frames and seals are geometry, not painted
window cutouts. Glass sorting and final engine shading have not been tested.

The livery, model geometry and texture artwork were authored for this vehicle;
no third-party vehicle meshes or photographic textures are included. Font files
are not distributed.

## Validation performed

`validation_report.json` records checks on the serialized GLB, including original
node names and local/world transforms; original metadata and parent links;
wheel radius, width, wheelbase and track; main-body bounds; valid buffer ranges
and indices; finite unit normals and tangents; normal/tangent orthogonality;
accessor bounds; no degenerate triangles after export; decoding and byte parity
of all embedded PNGs; separate low-alpha glass; eight ray samples through the
windshield/deflector openings; and independent Trimesh import reproducing
611,988 triangles.

Not performed: Unreal import/material compilation, runtime animation binding,
full steering/suspension clearance, exhaustive self-intersection/manifold checks,
or formal Khronos glTF Validator validation. Installing that validator was not
available in this environment. This assembled asset intentionally has open
surfaces, layered trim and separate mechanical parts; it is not one watertight
manufacturing mesh.

## Rebuilding

Run from the package directory in a compatible Python environment:

```sh
python -m pip install -r source/requirements.txt
python source/build_buggy.py
python source/export_glb.py
python source/validate_asset.py
```

The above uses the included texture images. To regenerate the artwork first:

```sh
python source/make_textures.py
```

Font discovery supports common Linux, Windows and macOS paths. Different fonts
will change the artwork. Existing delivered textures need no font installation.

Render review images sequentially to limit memory use:

```sh
python source/render_buggy.py front final
python source/render_buggy.py rear final
python source/render_buggy.py mechanical final
python source/render_buggy.py driver final
```

The renderer uses VTK PBR, an analytic studio environment, screen-space ambient
occlusion and a studio-only soft contact-shadow card. It is not an Unreal render
or a path-traced render. It selects EGL on Linux and a standard VTK window on
other platforms; a working graphics/offscreen context is required locally.

Build/export create intermediate pickle files. Only load caches you generated
yourself. No pickle caches, third-party packages, runtime executables or font
files are included in this delivery.

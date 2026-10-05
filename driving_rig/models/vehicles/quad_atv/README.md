# ROVE / Q4 - quad ATV, review v01

Fictional single-rider utility-sport ATV built around the supplied
`quad_atv_bind.glb`. Clay-red panels, ivory accents, graphite utility racks,
real off-road tread, exposed powertrain and suspension, and an open rider station.

This is an art-review asset, not an engine-tested release. It has not been
opened in Unreal Editor or run in the user's game. The review images are
renders of this asset's geometry and materials, not generative concept images.

## Files

- `ROVE_Q4_quad_atv_v01.glb`: self-contained model with all 23 PNG textures embedded.
- `review/`: four 2000 x 1250 PNGs: front, rear, rider station and mechanical detail.
- `textures/`: standalone editable copies of every embedded map.
- `reference/quad_atv_bind.glb`: unchanged original proxy and binding hierarchy.
- `asset_manifest.json`: mesh statistics, per-group counts, bounds and checksum.
- `validation_report.json`: checks on the serialized GLB and their limitations.
- `material_manifest.json`: material parameters and texture/image indices.
- `review_manifest.json`: rendering method, image dimensions and checksums.
- `source/`: deterministic geometry, artwork, export, validation and render scripts.

The studio floor, lighting environment, contact-shadow card and review cameras
are not included in the GLB. There is no review website, Unreal project or
Blender scene. The editable source is procedural Python plus ordinary GLB mesh data.

## Statistics

| Item | Value |
|---|---:|
| Triangles | 870,609 |
| Exported vertices | 592,700 |
| Mesh nodes | 21 |
| Material definitions | 25 |
| Material primitives | 116 |
| Embedded PNG images | 23 |
| Total nodes | 38 |
| Original nodes retained | 25 |
| Added groups | 9 chassis children + 4 brake-caliper children |
| Rider positions | 1 |
| GLB size, decimal MB | 62.64 |

This is one deliberately high-detail version. There is no LOD reduction,
lightmap-UV pass, draw-call consolidation, engine-generated collision or
texture-streaming conversion. The four wheel assemblies account for
474,400 triangles. Tread blocks, brake-rotor holes, springs and most
fasteners are actual geometry, not normal-map-only details.

## Original dimensional and rig contract

Metres, Y up, -Z forward. All 25 original node names, exact local translations,
rotations, scales and original parent relationships are preserved. Original
world-space pivots and axes were recomputed independently and compared exactly.

| Supplied constraint | Retained value |
|---|---|
| Collision-body width x height x length | 0.90 x 0.75 x 1.90 m |
| Wheelbase | 1.27 m |
| Front wheel-centre track | 1.15 m |
| Rear wheel-centre track | 1.12 m |
| Four tyre radii | 0.28 m |
| Four wheel widths | 0.22 m |
| Maximum wheel-to-wheel width | 1.37 m |
| Chassis bind-pose Y | 0.6252571428571428 m |
| Original collision-body top above ground | 1.000257142857143 m |

The 0.75 m height is the original body box itself, not the full ATV height above
the road. The wheels already extend outside the 0.90 m collision-body width.
No wheel, wheel pivot or original control has been moved to suit the design.

The complete primary opaque bodywork fits inside the original collision box.
Front/rear bumpers, the winch hook, foot rails, handlebars, handguards and the
small flyscreen are protruding fittings. The original proxy already placed its
steering-column pivot above the main body box. The complete visible asset spans
approximately 1.37 m across the wheels and reaches 1.143 m above ground at the
handguards. These visual bounds must not replace the existing collision box.

`body_geo` contains the detailed bodywork rather than a solid cube. `nose_geo`
remains as an empty original transform. Collision dimensions remain unchanged
in scene metadata and in the reference file. Continue using the game's current
collision shape; no new collider has been generated.

### Handlebars on the existing steering hierarchy

The quad has handlebars, not a round car steering wheel. The handlebar tube,
grips, levers, handguards, thumb throttle and control pods are bound under the
original `steering_rim_geo` / `steering_wheel` hierarchy. Clamp and marker
geometry use the original `steering_spoke_geo` and `steering_marker_geo` nodes.
Their transforms, parent relationships and underlying steering-column axis have
not been modified. Mesh coordinates compensate for those original transforms.

No additional game animation control is required, but verify that the existing
steering animation uses a suitable handlebar rotation range. A car-style
multi-turn steering-wheel animation would make these handlebars over-rotate.
No script changing the game's steering ratio or clamp angle is included.

### Static and moving parts

Tyres, rims and brake rotors remain under the original wheel-spin nodes.
The four `brake_*_geo` groups are attached beneath the corresponding existing
`wheel_*_susp` nodes; they follow steering/suspension without spinning with tyres.
All other new named groups are children of `chassis`.

Wishbones, coilovers, reservoirs, axle boots, driveshafts, steering links, hoses,
engine components, exhaust, racks, winch, fuel cap, saddle, instrument display
and foot controls are static visual detail. Suspension links do not articulate
with wheel travel, and hoses do not deform. Hoses on the handlebars move with
the handlebars as a rigid visual part. Brake levers and thumb throttle do not
have independent animation. No skins or animation clips were added.

Keep the complete hierarchy when importing; merging all geometry would remove
independent wheel and handlebar behaviour.

## Geometry and finish

The body uses crowned front panels, shaped front/rear mudguards, tapered knee
shrouds, separate contrasting inserts, modelled trim and fasteners. Cooling
vents, radiator grille cells, footboard slots, exhaust outlet, wheel-spoke
openings and drilled brake rotors are real geometric openings.

The graphite front and rear cargo racks have tubular outer rails, open crossbar
decks, mounting feet, tie-down loops and slotted centre plates. Other equipment
includes a front winch with cable windings and recovery hook, roller fairlead
frame, impact bars, rear grab bar, skid plate, lights, reflectors and product
labels. The winch and racks are fixed, not functional gameplay mechanisms.

The open rider station has a contoured saddle with material grain, piping,
individual seam stitches and grip ribs; a sculpted tank cover and fuel cap;
handlebar grips, clamp hardware, brake levers and reservoirs; switch pods,
handguards, a thumb throttle, gear selector, rear-brake pedal and instrument pod.
The display is a static authored image, not connected to game telemetry.

Powertrain details include cast covers, cooling ribs, sump fasteners, airbox,
intake hose, starter motor, battery, wiring, header pipe, a right-side silencer,
perforated heat shield and hollow tailpipe. Four static double-wishbone
assemblies include coilovers, reservoirs, pivot hardware and corrugated CV boots.
These are plausible fictional visual assemblies, not engineering-certified parts.

Wheels have sculpted carcasses, individually modelled staggered chevron tread,
shoulder lugs, fictional sidewall lettering, open alloy barrels, six paired
spokes, fastened outer rings, hubs, wheel nuts, valve stems and drilled rotors.
No additional wheel, spare, axle or dual-wheel set was added.

## Materials and textures

Core glTF metallic/roughness PBR, with UVs, vertex normals and tangent vectors.
Paint additionally includes `KHR_materials_clearcoat` (factor 0.17, roughness
0.20), retaining the core material as a fallback. No Unreal-native shader
network, dynamic instrument logic or runtime light switching is included.

| Texture set | Resolution / maps |
|---|---|
| Clay-red body paint | 4096 x 4096 base colour, ORM, normal |
| Ivory paint | 2048 x 2048 base colour, ORM, normal |
| Carbon/composite rack inserts | 2048 x 2048 base colour, ORM, normal |
| Saddle upholstery | 2048 x 2048 base colour, ORM, normal |
| Brushed metal | 2048 x 2048 base colour, ORM, normal |
| Tyre sidewalls | 2048 x 2048 base colour, ORM, normal |
| Tread rubber | 2048 x 2048 base colour, ORM, normal |
| Product and safety-label atlas | 2048 x 2048 RGBA |
| Instrument display | 1024 x 512 |

ORM packs red = occlusion, green = roughness, blue = metallic. Occlusion is
neutral white, not baked scene illumination. Colour/emissive maps are colour
images; ORM and normal maps are data images. The normals are authored for the
glTF tangent-space convention; verify target importer handling.

The `glass_deflector_geo` group is a separate small clear flyscreen, using
`Glass_Windscreen`: double-sided core `BLEND`, base-colour alpha 0.065,
roughness 0.060. It does not rely on a transmission extension. The rest of the
riding position is open: there is no enclosed cab or opaque fake window surface.
Glass blending, sorting and final engine shading require an import check.

All new vehicle geometry and texture artwork were authored for this project;
no third-party vehicle meshes or photographic textures are included. The
binding hierarchy is from the supplied proxy. No font files are distributed.

## Validation performed

The serialized GLB passed exact original-name, local/world transform, parenting
and scene-metadata checks; four wheel-radius/width checks; wheelbase/track
checks; primary body-envelope checks; buffer ranges, index and accessor checks;
finite unit normals/tangents and tangent orthogonality; zero degenerate triangles
after export; decoding and byte parity for all embedded PNGs; separate low-alpha
glass checks; nine local ray spot-checks through the flyscreen; and independent
Trimesh import reproducing 870,609 triangles.

All 116 review primitives were compared with the serialized GLB for
positions, UVs and triangle indices and matched exactly.

Not performed: Unreal Editor import/material compilation, the user's runtime
animation binding, a full steering/suspension clearance sweep, exhaustive
self-intersection/manifold checks or formal Khronos glTF Validator validation.
The ATV is an assembly with holes, thin panels and separate parts, not a single
watertight manufacturing mesh. Runtime handlebar rotation range needs checking.

## Rebuilding

Run from the extracted package directory:

```sh
python -m pip install -r source/requirements.txt
python source/build_atv.py
python source/export_glb.py
python source/validate_asset.py
```

These commands use the delivered textures. To regenerate the authored artwork
first, run `python source/make_textures.py`. Font discovery supports common
Linux, Windows and macOS paths; different fonts will change label artwork.
Delivered textures do not require font installation.

Render the review images sequentially to limit memory use:

```sh
python source/render_atv.py front final
python source/render_atv.py rear final
python source/render_atv.py driver final
python source/render_atv.py mechanical final
```

The `driver` view is the ATV's rider-station camera. The renderer uses VTK PBR,
an analytic studio environment, SSAO, tone mapping and a studio-only contact
shadow card. These are neither Unreal screenshots nor path-traced renders.
A working EGL/OpenGL offscreen context is needed locally; none is required to
view the included PNG files.

Build/export generate intermediate pickle files. Only read caches generated by
these scripts; never load an untrusted pickle. No pickle caches, third-party
packages, runtime executables or font files are included in the delivery ZIP.

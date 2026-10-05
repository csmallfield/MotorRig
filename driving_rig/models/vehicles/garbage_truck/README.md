# ORDA / R9 - garbage truck, review v01

Fictional contemporary two-axle rear-loading refuse truck, authored around the supplied
`garbage_truck_bind.glb`. Ivory cab, orange municipal-service livery, clear separate
windows, a simple three-seat cab, and static rear-loading equipment.

This is an art-review asset. It has not been imported into Unreal Editor or tested
inside the user's game. The provided review images are offline PBR mesh renders,
not Unreal screenshots, generated concept images, or texture-only impostors.

## Files

- `ORDA_R9_garbage_truck_v01.glb`: self-contained asset with all 21 PNG textures embedded.
- `review/`: front, rear, loader detail and driver-station PNGs, each 2000 x 1250.
- `textures/`: editable standalone copies of the embedded maps.
- `reference/garbage_truck_bind.glb`: unchanged original rig/proxy file.
- `asset_manifest.json`: geometry counts, group breakdown, bounds and checksum.
- `validation_report.json`: independent serialized-file checks and their limits.
- `source/`: deterministic geometry, texture, export, validation and render scripts.

The studio floor, contact-shadow card, environment and review cameras are not
exported into the GLB. No review website or external viewer is required.

## Statistics

| Item | Value |
|---|---:|
| Triangles | 321,238 |
| Exported vertices | 248,645 |
| Mesh nodes | 18 |
| Material definitions | 27 |
| Material primitives | 82 |
| Embedded PNG images | 21 |
| Total nodes | 35 |
| Original nodes retained | 25 |
| Added static mesh groups | 10 |
| Cab seats | 1 driver + 2 passenger |
| GLB size | 37.09 MB |

One high-detail version is supplied. There has been no LOD reduction, lightmap-UV
pass, engine-specific draw-call consolidation or texture-streaming pass.

## Dimensional and rig contract

The authored file preserves metres, Y up and -Z forward. All original node names,
translations, rotations, scales, original parent relationships and scene metadata
are retained exactly. World-space pivot matrices were independently compared
against the source rig and matched exactly.

| Constraint | Original value retained |
|---|---|
| Collision body width x height x length | 2.50 x 3.40 x 9.50 m |
| Chassis bind-pose Y | 1.950856833753952 m |
| Top of original collision body above world ground | 3.650856833753952 m |
| Wheelbase | 4.60 m |
| Front / rear wheel-centre track | 2.05 / 1.95 m |
| All four wheel radii | 0.55 m |
| All four wheel widths | 0.34 m |

The two-axle, four-wheel layout is intentional: no extra axle or dual-wheel set
has been added. The source's few-micron front/rear bind-height difference is
retained, not silently corrected.

The main body remains within the original envelope; tiny welds and fasteners
are treated as hardware. Mirrors, access steps, rails and some fittings protrude
slightly. Overall visual width including mirrors is approximately 3.316 m; this
must not replace the original 2.50 m collision width.

`body_geo` contains detailed cab geometry rather than the original solid cube.
`nose_geo` remains an empty original transform. The collision envelope remains
in metadata and in the unchanged reference file. No new engine collision object
has been generated: continue using the game's existing collision shape.

All additions are chassis children. The wheels remain on their original wheel
mesh/spin nodes. The steering rim, spokes and marker remain under the original
steering-wheel hierarchy. Doors, wipers, beacons, compactor, tailgate, cylinders,
hoses and bin lifter are static. No animation clips or skins are added.

## Geometry

The cab has actual window openings, perimeter seals and frames, curved separate
windscreen glazing, door glass, mirrors, wiper arms, recessed grilles, lamp
assemblies, perforated entry treads and service-panel seams.

The interior has three upholstered seats, seat belts, headrests, a rubber floor,
door liners, grab handles, dashboard, vents, pedals, sun visors, interior mirror,
instrument display and reversing-monitor graphic. It is a simple interior for
occasional driver views rather than a fully operable cockpit. Displays are static
textures, not game telemetry or a live reversing-camera feed.

The compactor uses a rounded cross-section with formed rails and a service hatch.
The rear loader has a genuinely open hopper, an interior throat with metal
liners, a packer blade, recessed external rams, chrome rods, pins, hoses, line
clips, stationary bin-lifter links, comb rail, worker steps, controls, rear lights
and safety markings. The interior steel maps include directional rub marks.

The underbody includes frame rails, crossmembers, axle/differential housings,
simplified leaf springs, propshaft, fuel tank, storage cases, protective side
rails and mudguards/mudflaps. These parts are static bind-pose detail; they are
not a deforming suspension simulation.

## Materials and textures

Materials use core glTF metallic/roughness PBR. No Unreal-native material graph
or project is included. UVs, normals and tangents are embedded.

| Texture set | Resolution / maps |
|---|---|
| Compactor livery / body paint | 4096 x 4096 base colour, ORM, normal |
| Ivory cab paint | 2048 x 2048 base colour, ORM, normal |
| Tyre sidewall | 2048 x 2048 base colour, ORM, normal |
| Seat upholstery | 2048 x 2048 base colour, ORM, normal |
| Cab floor | 2048 x 2048 base colour, ORM, normal |
| Worn hopper steel | 2048 x 2048 base colour, ORM, normal |
| Decal and safety-label atlas | 2048 x 2048 RGBA |
| Instrument display | 1024 x 512 |
| Reversing monitor graphic | 1024 x 512 |

ORM packs red = occlusion, green = roughness, blue = metallic. Occlusion is
neutral white, not baked scene lighting. Base-colour/emissive images are colour
textures; ORM and normal images are data maps. Normal maps were authored for the
glTF tangent-space convention; check the target importer's normal-map handling.

Separate glass nodes:

- `glass_windshield_geo`: `Glass_Windscreen`, alpha 0.065, roughness 0.060.
- `glass_windows_geo`: `Glass_Side`, alpha 0.105, roughness 0.075.

Both glass materials are double-sided core `BLEND` materials. This keeps the
windows very clear without requiring a transmission extension. Glass appearance,
sorting and material import still require an engine-side check. Window openings
and opaque frames are geometry, not transparent regions in an opaque body box.

All livery, vehicle geometry and texture artwork were authored for this asset;
no third-party vehicle meshes or photographic textures are included. No font
files are distributed.

## Validation performed

The serialized GLB, not just the authoring scene, passed:

- Original node names, exact local/world transforms, parenting and metadata checks.
- Four wheel-radius and width checks at 1e-6 m tolerance; wheelbase and track checks.
- Buffer ranges, triangle indices, finite values, accessor bounds, unit normals,
  unit tangents and normal/tangent orthogonality checks.
- Successful decoding of all 21 embedded PNGs; byte parity with standalone maps.
- Separate highly transparent glass-material checks and seven structural-shell
  ray samples through the side-glass apertures and windscreen.
- An independent Trimesh import reproducing 321,238 triangles.

Not performed: Unreal Editor import/material compilation, the user's runtime
animation binding, full steering/suspension articulation clearance, formal
Khronos glTF Validator validation, or an exhaustive self-intersection/manifold
inspection. The file intentionally includes separate thin surfaces, decals,
openings and overlapping mechanical assemblies; it is not a single watertight
manufacturing mesh.

## Rebuilding and review rendering

With Python and the requirements installed, run from the package directory:

```sh
python -m pip install -r source/requirements.txt
python source/build_truck.py
python source/export_glb.py
python source/validate_asset.py
```

These commands use the delivered textures. To regenerate the artwork first,
run `python source/make_textures.py`. Font discovery supports common Linux,
Windows and macOS fonts, but changing fonts will change decal artwork.

Review renders are produced sequentially (parallel renders can require a large
amount of memory):

```sh
python source/render_truck.py front final
python source/render_truck.py rear final
python source/render_truck.py hopper final
python source/render_truck.py driver final
```

The renderer uses VTK PBR, environment reflections and screen-space ambient
occlusion, plus a studio-only soft contact-shadow card. It selects EGL on Linux
and the default VTK window on other platforms. Availability of a working
OpenGL/offscreen context depends on the local installation. The delivered PNGs
can be reviewed without installing any of these dependencies.

Geometry generation creates local intermediate pickle files. Only load pickles
you generated yourself. No pickle caches, third-party packages, runtime binaries
or font files are included in the delivered archive.

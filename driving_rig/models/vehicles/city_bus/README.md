# LINEA / 12 - city bus, review v01

Fictional contemporary single-deck city bus, authored around the supplied
`city_bus_bind.glb`. This is the first modelled and textured art-review build.
The asset has not been opened or tested inside Unreal Editor or the user's game.

## Main files

- `LINEA12_city_bus_v01.glb`: self-contained model with all 17 PNG textures embedded.
- `review/`: four 2000 x 1250 PNG renders: front/entry side, rear/driver side,
  passenger cabin and driver station. These are offline PBR mesh renders, not
  Unreal screenshots or generative concept art. Stage lighting and floor are not
  part of the GLB.
- `textures/`: standalone copies of the embedded textures for editing.
- `asset_manifest.json`: exported mesh counts and SHA-256 checksum.
- `validation_report.json`: structural, dimension and independent import checks.
- `reference/city_bus_bind.glb`: unchanged supplied bus proxy, including its
  original collision dimensions and binding hierarchy.
- `source/`: deterministic geometry, texturing, export and review-render scripts.

## Asset statistics

| Property | Value |
|---|---|
| Triangles | 329,836 |
| Exported vertices | 259,925 |
| glTF mesh nodes | 17 |
| Material definitions | 27 |
| Material primitives | 79 |
| Embedded images | 17 |
| Total nodes | 34 |
| Original nodes retained | 25 |
| Seats | 30 passenger + 1 driver |
| GLB size | 70.59 MB |

This is one high-detail version. No LOD reduction, draw-call consolidation pass,
collision generation, lightmap UV pass or streaming-specific texture packaging
has been performed. Those were not priorities for this review request.

## Dimensions and binding

The GLB retains metres, Y up, -Z forward. All 25 original node names and the exact
original local translations, rotations, scales and original parent relationships
are preserved. Geometry is replaced; extra static mesh children are added under
`chassis`. `nose_geo` remains as an empty transform rather than retaining the
proxy's coloured nose cube.

The original body collision box is 2.55 m wide x 3.10 m high x 12.00 m long.
Its chassis placement is unchanged. It is NOT included as an opaque visible cube
inside the detailed model; its dimensions remain in scene metadata and its
original geometry is included in the reference file.

Wheelbase remains 6.00 m. Each complete wheel measures 0.55 m radius and 0.32 m
width in its unchanged local frame. Front track remains 2.10 m and rear track
2.00 m. Front and rear bind-pose wheel-centre heights differ by about 16 microns
in the input; that original difference is retained rather than silently fixed.

The body is built inside the supplied main envelope. Small mirrors, lamp trim
and number plates are protruding accessories. The overall visual width including
mirrors is about 3.505 m; this must not be substituted for the collision width.

All static bodywork, glazing, furniture, doors, lamps, displays, mirrors and
wipers follow `chassis`. Wheel meshes remain under their original spin nodes;
steering meshes remain under the original steering-wheel hierarchy. There are
no animation clips, skin, new door controls or additional moving-part controls.
Do not merge the wheel and steering meshes into the body when independent node
animation is required.

## Geometry and materials

Window openings, wheel openings, rim ventilation holes, door glazing openings,
major vents and roof fan apertures are real mesh openings, not painted cutouts.
Window frames and seals have their own opaque geometry. The floor and wheel
housings are cut back around the tyres, rather than intersecting their centres.

Separate glass nodes:

| Node | Contents |
|---|---|
| `glass_windshield_geo` | Front windscreen |
| `glass_windows_geo` | Side and rear glazing; driver partition |
| `glass_doors_geo` | Fixed passenger-door glazing |

The glass uses double-sided, core glTF `BLEND` materials rather than relying on a
transmission extension. `Clear_Window_Glass` has base-colour alpha 0.105 and
roughness 0.075. `Clear_Windscreen` has alpha 0.065 and roughness 0.055. These are
intentionally very clear defaults. Glass appearance still needs checking through
the target engine's importer/material setup; no Unreal-native material graph is
included.

Opaque surfaces use metallic/roughness PBR. UVs, normals and tangent vectors are
included. Textures:

| Set | Resolution / maps |
|---|---|
| Exterior | 4096 x 4096 base colour, ORM, normal |
| Tyre sidewall | 2048 x 2048 base colour, ORM, normal |
| Upholstery | 2048 x 2048 base colour, ORM, normal |
| Floor | 2048 x 2048 base colour, ORM, normal |
| Decals | 2048 x 1024 RGBA |
| Front route sign | 2048 x 256 |
| Side route sign | 1024 x 128 |
| Rear route sign | 512 x 256 |
| Dashboard | 1024 x 512 |

ORM packs red=occlusion, green=roughness, blue=metallic. The occlusion channels
are neutral white, not baked lighting. Normal maps use the glTF/OpenGL convention.
The livery and labels are fictional. No third-party vehicle geometry or photos
were used. The route text, instruments and lamps are static authored materials;
the displayed speed is not connected to game telemetry.

## Validation performed

The serialized GLB passed these checks:

- Original names, transforms, parenting and source scene metadata preserved.
- Four exact wheel radii and widths within 1e-6 m floating-point tolerance.
- Buffer ranges, triangle indices and finite unit normals/tangents checked.
- All embedded PNGs decode successfully.
- Separate glass primitives use low-alpha, double-sided blend materials.
- Structural-shell ray spot-checks through all 11 side window centres and the
  front windscreen found no opaque shell geometry filling those openings.
- Independent Trimesh import succeeded and reproduced 329,836 triangles.

These checks are not a substitute for Unreal/game integration testing. A formal
Khronos glTF Validator run, Unreal material compilation, runtime binding test,
and full steering/suspension articulation clearance test have not been performed.
See `validation_report.json` for the exact checks and limits.

## Rebuilding / editing

The GLB can be edited as ordinary mesh data in a compatible DCC. There is no
Blender `.blend` source file; the included source is procedural Python.

To regenerate geometry and the GLB with the existing textures, run these from
an environment with the listed dependencies installed:

```sh
python -m pip install -r source/requirements.txt
python source/build_bus.py
python source/export_glb.py
python source/validate_asset.py
```

To regenerate review views:

```sh
python source/render_bus.py front final
python source/render_bus.py rear final
python source/render_bus.py interior final
python source/render_bus.py driver final
```

The review renderer uses VTK's off-screen EGL rendering; availability depends on
the local VTK/OpenGL installation. The original renders were made with VTK 9.6.2.
The optional `make_textures.py` and review annotation code use system DejaVu fonts
at their standard Linux paths. Change those font paths on Windows as needed.
Font files are not distributed. Existing delivered textures do not need rebuilding.

Geometry regeneration creates intermediate pickle files inside `source/`; only
use intermediate pickle files you generated yourself. The delivered archive
contains no pickle files, binaries, runtime executables or font files other than
the actual GLB model/reference and PNG textures/images.

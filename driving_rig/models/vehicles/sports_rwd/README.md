# VANTA V87 GT
## Sports RWD / finished-model review delivery / revision 1.0

A fictional late-1980s front-engined 2+2 fastback sports GT, authored independently from the original `sports_rwd_bind.glb`. No geometry or design surfaces from earlier passenger-car attempts were used.

**Open `VANTA_V87_GT_sports_rwd.glb` for the complete textured vehicle.** All textures are embedded; the GLB needs no external image files. `renders/20_GLB_front.png` through `26_GLB_wheel_detail.png` are renders of the exported GLB re-imported through an independent glTF reader. They are not generated concept images.

### Contents

- Complete GLB, with the original MotorRig transform hierarchy and added visual meshes.
- Seven final views, a review contact sheet, and primary-shell diagnostic views.
- Rig analysis, original rig JSON, asset manifest, and automated validation report.
- The original sports-car proxy GLB for recovery/comparison.
- Python authoring, export, validation, texture-extraction and review-render sources.

### Model specifications

| Item | Value |
|---|---:|
| Rendered triangles | 820,420 |
| Referenced visual vertices | 469,023 |
| Visual mesh nodes | 87 |
| Original MotorRig nodes retained | 25 |
| Materials used | 24 |
| Embedded PNG images | 12 |
| Wheelbase | 2,700 mm |
| Front / rear track | 1,620 / 1,600 mm |
| Tyre diameter / width | 680 / 280 mm |
| Body width, excluding mirrors | 1,986 mm |
| Overall width, including mirrors | 2,064 mm |
| Overall height above tyre contact plane | 1,282 mm |
| Body length / overall length including exhaust tips | 4,700 / 4,725 mm |

The body proxy remains **1,300 x 850 x 4,500 mm** in the unchanged original scene metadata. It is not used as the visible envelope. The visual body is wider so that the authoritative tyre positions are naturally enclosed by the fenders.

### Included design and detailing

Continuous primary forebody, hood/fenders, side surfaces and rear quarters; a swept greenhouse and actual window apertures; closed flush pop-up headlamp lids; a functional front intake opening; distinct rear lamp/numberplate architecture; inset trim, door divisions, handles and mirrors; geometric tyre grooves and tread blocks; five-spoke alloys, valve stems, lugs, discs and non-spinning calipers; a two-tone 2+2 interior, analogue cluster, manual gearbox controls and pedals; a restrained visible underbody and connected exhaust.

The six glazing meshes are separate transparent objects, with real surrounding pillars, header/sill geometry, seals and aperture returns. The interior is comparatively simpler than the exterior, as requested. Doors, wipers, headlamp lids and other fittings remain static.

### Rig integration

All original names, local transforms and original parent relationships are retained. Original proxy mesh attachments are removed from the visible scene; their original bounds and archive references are recorded on the retained carrier nodes. No original proxy mesh is accidentally rendered. Original scene extras, including `body_size`, wheel dimensions, ride height and static compression, are unchanged.

New static geometry is beneath `body_geo`; wheel geometry is beneath the corresponding original `wheel_*_geo`; calipers inherit `wheel_*_susp` rather than spin; the steering wheel retains the original steering-column rotation chain. The steering rim was moved **210 mm along the original column axis**, not sideways, so animation does not make it orbit a displaced pivot.

This is the same runtime-driven **rigid-node** contract as the source. No skeleton, skin weights, driving animation clips or vehicle Blueprint have been invented.

### Validation and remaining integration work

The 19 checks in `validation_report.json` pass. They cover original-node transforms/parents, metadata, absence of display proxies, geometry/index validity, unit normals, tangent frames, UVs, image decoding, separate glass, tyre dimensions, hardpoint positions, on-axis steering placement and independent trimesh import/bounds. The exported GLB was also re-imported and rendered with VTK's glTF importer.

Static primary-shell sampling gives approximately **41.6 mm minimum radial clearance** beyond the tyre radius. This is a sampled bind-pose check, **not** an exhaustive triangle-intersection analysis or a suspension/full-steering sweep guarantee.

**Not tested in an Unreal project.** Unreal material conversion, the user's MotorRig controller integration, collision setup, suspension travel and full steering sweeps still require in-engine testing. In particular, inspect clearcoat and translucent-glass materials after import. Preserve/reconstruct the hierarchy rather than combining the entire vehicle into one static mesh. No engine LODs, Nanite settings, lightmap UVs or Unreal collision assets are supplied.

### Texture organization

The body uses a 4K base microflake map with 2K packed occlusion/roughness/metallic and normal maps. Leather and rubber use 2K normals; smaller optical, carpet, branding and dashboard maps are 1K/2K as appropriate. These are material-space textures with explicit UVs, not a unique all-parts bake or baked lightmap set. Packed ORM channels are R=occlusion, G=roughness, B=metallic. Normals use glTF's tangent-space convention.

To extract the exact embedded images without any third-party Python modules:

```sh
python source/extract_textures.py
```

### Sources and rebuilding

See `documentation/design_and_references.md` for reference choices and the proportion study. The source code captures this particular authored design; it is not intended as a generic passenger-car template. Its principal surface stations should not be transplanted into the next vehicle.

To regenerate in a separate working copy (Python 3.13 was used here):

```sh
python -m pip install -r source/requirements.txt
python source/rebuild.py
python source/validate_vehicle.py
```

The rebuild overwrites the GLB and generated material maps in its package directory. Intermediate geometry caches are written to `source/`. Set `VANTA_OUTPUT_DIR` to change the model output directory. A locally installed TrueType font is required to regenerate gauges and fictional lettering; set `VANTA_FONT` when the automatic font search does not find one. Font files are not included. Cross-platform rendering/rebuild has not been tested; the delivered GLB itself does not depend on Python or VTK.

To recreate final views after a rebuild, first run `source/car_core.py` to generate the studio contact-shadow map, then run `source/render_exported.py`. The renderer uses PBR studio lighting, screen-space ambient occlusion and a soft contact-shadow approximation; the review images are not claimed to be path-traced reference renders.

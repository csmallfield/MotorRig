# Kestrel S6 - SUV review delivery

A complete exterior-and-interior review asset built fresh around the original **suv_awd_bind.glb** MotorRig. This delivery is the SUV, not the limousine mentioned in the conflicting final section of the brief.

## Contents

- `Kestrel_S6_MotorRig.glb`: self-contained visual vehicle with the original transform-node rig.
- `renders/`: eight 2400 x 1600 views rendered from an independent import of this GLB.
- `diagnostics/`: five undecorated primary-shell views and a primary-shell GLB; these are diagnostic material, not the final model.
- `reports/`: original rig measurements, hierarchy, design/reference notes and validation results.
- `original/suv_awd_bind.glb`: untouched SUV reference only. Do not load its proxy meshes alongside the replacement visuals.

The `source_project/` folder contains the editable surface definitions, detailed geometry builders, deterministic texture generation, GLB writer and independent validation/render scripts. It is Python source, not a native Blender or Maya scene.

## Measured dimensions

| Property | Value |
|---|---:|
| Wheelbase | 2.850 m |
| Front / rear track | 1.660 / 1.660 m |
| Tyre diameter / width | 0.760 / 0.260 m |
| Overall visual length | 4.888 m |
| Maximum body width excluding mirrors | 2.011 m |
| Complete width including mirrors | 2.252 m |
| Ground-to-highest visual point | 1.825 m |
| Front / rear visual overhang | 0.997 / 1.041 m |
| Original body proxy dimensions, retained as metadata | 1.450 x 1.250 x 4.800 m |

The visible body deliberately extends beyond the narrow proxy. Original wheel centres, original local transforms, original parent relationships and original scene extras are unchanged.

## Included modelling and materials

The exterior has integrated curved fenders, actual side and front/rear glazing openings, separate window seals and glass meshes, real door/hood/hatch divisions, grille and intake cavities, multi-part headlamps, tail lamps, mirrors, wipers, roof rails, restrained trim, and fictional Kestrel branding. No manufacturer artwork or purchased vehicle mesh is included.

The wheels include shaped tyres, geometric tread and grooves, sidewall textures, split spokes, rim barrels and lips, hub bolts, discs and calipers. Calipers are parented above wheel spin.

The five-seat cabin includes upholstered seats, headrests, belts, dashboard, driver display, centre navigation display, steering wheel and column, controls, centre console, cup wells, door cards, speakers, pedals, roof lining and rear cargo structures. It is intended for occasional interior cameras rather than full mechanical interaction. Doors and seats are static.

There are **9 separate glazing objects**, **34 materials** and **19 embedded PNG textures**. The paint uses 4K ORM/normal microfinish maps with a recolourable base-colour factor. Secondary textures are mainly 2K, with 1K smaller material/UI maps. RGB ORM convention is occlusion, roughness, metallic. Display aspect ratios are intentional, not all maps are square.

Glass uses alpha-blended materials, not opaque painted windows. Front glazing has alpha 0.18, rear glazing 0.30, and roof glazing 0.46. These are portable glTF transparency settings, not a physically refractive laminated-glass shader. Lamp covers are separate transparent meshes. Paint also uses `KHR_materials_clearcoat`.

## Rig contract

The first 25 nodes retain their original names, transforms, extras and parent relationships. New render nodes are appended below them. Original mesh assignments are removed so no crude proxy remains visible.

The vehicle is a **transform-node rig**, not a newly skinned skeletal mesh. The original contains no animation clips; no driving clips have been invented. Drive the existing chassis, wheel steer/suspension/spin nodes and steering-wheel hierarchy as before. Avoid destructive node merging or transform baking when using a loader that resolves the original node names.

Body and interior visuals follow `body_geo` below `chassis`. Wheel geometry follows each original `wheel_*_geo` below its spin node. Brake calipers follow the suspension nodes. Steering rim and spokes follow their original steering descendants. `nose_geo` and the original steering marker remain as empty contract nodes.

Collision **metadata** is preserved. This does not mean an engine collision shape has been authored or tested. The original reference GLB is included for any project code that builds collision from its proxy mesh instead of the scene extras.

## Density and file size

This is deliberately a dense review asset, with no LOD or aggressive optimization pass:

- 1,766,101 triangles in unique mesh data.
- 2,384,753 triangles when all vehicle instances are counted.
- 667 unique meshes, 847 renderable nodes, 872 total nodes.
- 141,016,260 bytes for the GLB (141.0 MB decimal).

Polygon count is recorded for integration planning, not asserted as a quality rating. Repeated wheel geometry shares mesh data.

## Verification and remaining integration tests

`reports/Validation.json` records **28 passing custom automated checks** and no failed checks. These cover original node/transform/parent retention, wheel centres and dimensions, wheelbase and tracks, buffer bounds, indices, finite attributes, normal/tangent consistency, non-degenerate exported triangles, embedded image decoding, separate transparent glazing, proxy removal and a static body-to-tyre vertex-envelope check.

The GLB also imports through **trimesh** and **VTK's independent glTF importer**. The final studio images use the latter. This is not a claim of Khronos validator certification.

**Not verified here:** Unreal Engine import/playback, your MotorRig runtime, full steering lock, full suspension travel, engine collision setup, transparent-material sorting in your renderer, or performance on your target PC. The static tyre test is not a complete triangle-triangle intersection or manufacturing check. There is no animation clip, physical vehicle setup, LOD chain or lightmap-UV pass in this delivery.

The model is supplied for art-direction review and project import testing. The other passenger-car assets have not been modified.

## Integrity

GLB SHA-256: `b5e2944e161a078b99e07c63676e37a0ea2e08d889ab7ef512775d794d0e3ccd`

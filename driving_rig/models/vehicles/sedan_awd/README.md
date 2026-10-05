# VAEL S26 AWD

## Sedan review build - 4 October 2026

This delivery is the sedan selected at the beginning of the request. Its sole source rig is `sedan_awd_bind.glb` from the supplied `MotorRig_bind_cars(2).zip`. The closing limousine instructions were treated as carried-over template text. No earlier passenger-car design or geometry was used.

The package contains a fully populated exterior and interior, embedded materials, an intact original transform hierarchy, review images, numerical validation reports, and reproducible modelling/export source. Design approval is still required; technical validation is not a certification of artistic quality or of the Unreal runtime.

## Open first

- `VAEL_S26_AWD.glb`: standalone asset; no external texture paths.
- `VAEL_S26_review.jpg`: front/rear three-quarter, exact side, and driver-view contact sheet.
- `renders/imported_*.png`: seven full-resolution views rendered after importing the GLB in a separate reader, rather than drawing the source geometry directly.
- `reports/validation.json`: binary, geometry, material, rig and measurement checks.
- `reports/vtk_import.json`: second independent import and render record.
- `RIG_CONTRACT.md` and `DESIGN_REVIEW.md`: measurements, hierarchy and design notes.

The studio floor, cyclorama, lights and contact-shadow backdrop are presentation elements, not vehicle geometry in the GLB. The views are actual 3D renders, not generated concept paintings or geometry-overpaint composites.

## Asset contents

The exterior includes a continuous designed side-body surface, integrated wheel openings and returns, bonnet, roof, rear quarters and boot, physical window openings and pillars, separate glazing, door/bonnet/boot divisions, grille cavities, projector lamps, tail-light optics, mirrors, wipers, handles and restrained fictional markings. The four wheels include tyre tread geometry, sidewall moulding, split-Y spokes, rims, hubs, bolts, brake discs and fixed calipers. Underfloor panels have wheelhouse recesses rather than continuing through the tyres.

The simpler interior includes two front seats, a three-position rear bench, headrests, stitching and inserts, dashboard, textured instruments and infotainment, console, gear selector, pedals, mats, door cards, speakers, belts, headliner, mirror and steering controls. The cabin is intentionally less detailed than the exterior; there are no working displays, door animations or interactive cockpit controls.

Paint uses embedded 4K base-color, packed material and normal maps. Secondary leather, tyre and brake maps use 2K images. Displays and the registration plate use 1K-wide images with appropriate rectangular aspect ratios. Twelve image resources are embedded in total. All maps are also included externally for material editing.

Glass is six separately named mesh objects with highly transparent, double-sided alpha-blended materials. The openings are actual holes in the surrounding structure. The GLB also uses clearcoat and index-of-refraction material extensions; it does not depend on a transmission extension. Engine-specific glass shading has not been calibrated in Unreal.

## Measured delivery

| Property | Value |
|---|---:|
| Wheelbase | 2.650 m |
| Front / rear track | 1.580 / 1.560 m |
| Tyre diameter / width | 0.680 / 0.240 m |
| Visible length | 4.578 m |
| Primary painted body width | 1.897 m |
| Visible width including mirrors | 2.210 m |
| Height from tyre contact | 1.435 m |
| Original collision body dimensions, unchanged (X/Y/Z) | 1.300 / 1.000 / 4.400 m |
| Visible triangles | 1,650,778 |
| Visible mesh objects | 755 |
| Original / total nodes | 25 / 780 |
| Embedded texture images | 12 |

This is an unoptimized delivery. No LODs, draw-call consolidation, material atlasing or engine-specific collision generation have been performed. The high count is disclosed as a delivery characteristic, not a quality metric. The six unused original reference meshes are excluded from the visible triangle count.

## Validation and remaining runtime work

The automated audit passes 42 named checks: GLB structure and buffer ranges, original names/order/transforms/parent links and world transforms, scene metadata, retained source binary, embedded image decoding, valid indices, finite attributes, unit normals, orthonormal tangent frames, no zero-area exported triangles, wheel centres and dimensions, wheel assembly envelopes, wheelbase/tracks, separate glazing, neutral-pose static vertex clearance, and independent trimesh import/bounds.

A second reader, `vtkGLTFImporter`, independently loads 755 active mesh objects and renders the final file. Its bounds agree with the audit. It does not display the retained original proxy meshes.

Important limits: the static clearance test samples vertices against the neutral tyre volumes. It is not an exhaustive triangle/solid intersection proof or a full suspension/steering sweep. The 57 mm nominal arch-radius margin is not a guarantee for every suspension pose. Unreal Editor, the project's MotorRig runtime, physics/collision behavior and engine material conversion have not been tested. The official Khronos validator executable was not used. Before approving deployment, check the original node bindings, vehicle scale/orientation, steering and suspension extremes, glass/material behavior and the intended camera distances in the actual project.

The original file contains no animation clips and no skeletal skins. This delivery therefore preserves the supplied transform-node animation contract; it does not invent a different skeletal rig or bake new animations.

## Source and rebuilding

`source/meshkit.py` contains the mesh utilities and GLB writer. `build_sedan.py` describes the dedicated primary body surfaces; `detail_sedan.py` adds the exterior finishing, wheels and cabin. `validate_asset.py` reads and audits the resulting binary independently. `render_sedan.py --reimport` renders the exported asset through VTK's glTF importer.

The scripts use Python with NumPy, SciPy, Shapely, Pillow and Matplotlib. Validation additionally uses trimesh; rendering uses VTK with a functioning off-screen OpenGL implementation. The validated environment used Shapely 2.1.2, trimesh 4.11.1 and VTK 9.6.2. The package is not a Blender scene or a Maya scene: the GLB contains explicit triangulated meshes; the editable surface definitions are in the supplied Python source.

Run from the extracted package directory:

```sh
python source/build_sedan.py --full
python source/validate_asset.py
python source/render_sedan.py --reimport front_3q rear_3q side front rear interior wheel_detail
```

Keep `textures/materials.json` and the included texture images. They are the authoritative delivery material set and are reused by a normal rebuild. The texture-creation helper is an earlier seed generator, not an instruction to discard the delivered display artwork. A source-geometry `scene.pkl` is generated locally by the build; it is not needed for GLB import or for `--reimport` rendering and is intentionally not distributed. Do not run the build without `--full` when regenerating the detailed delivery.

No font files are included. Letter geometry and raster labels are already present in the asset and textures. Matplotlib's installed font resources are used if those elements are regenerated.

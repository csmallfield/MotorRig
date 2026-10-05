# VELA 1600 S - hatchback delivery

Fictional late-1980s three-door FWD hatchback, authored fresh against `hatch_fwd_bind.glb` from the supplied MotorRig archive. The hatchback is the subject of this delivery; the limousine paragraph in the pasted brief was treated as a carry-over.

## Start here

**`hatch_fwd_hero.glb` is the self-contained model.** All 17 texture images are embedded. The separate `textures/` folder is provided for material editing, not required to resolve the GLB. `review/` contains eight finished-detail views and five primary-shell clay diagnostics. These are renders of the actual model geometry, not generative concept images.

The package also contains `RIG_AND_DESIGN.md`, machine-readable validation/clearance reports and rebuildable Python source. The source folder includes the untouched original bind GLB. It does not contain a Blender or Maya scene.

## Design and contents

Petrol-teal metallic paint, a low crowned bonnet, long front doors, generous greenhouse, substantial rear pillars and a sloping hatch establish the primary form. Rectangular recessed lamps, slim grille, charcoal bumpers and restrained side strips provide a deliberately period identity. No geometry from a previous passenger-car design was reused.

The detail pass includes framed geometric window apertures with six separate transparent panes; modeled lamp reflectors/lenses and grille internals; mirrors, wipers, defroster lines, handles and shut lines; eight-slot wheels, tire grooves/lettering, front disc/caliper and rear drum hardware; and a modest underbody, exhaust and suspension representation.

The cabin includes checked-cloth seats and headrests, rear bench, floor and wheelhouses, door cards, dashboard, textured gauges/radio, heater controls, manual shifter, handbrake, pedals, steering wheel, column/stalks, visors and mirror. Doors and fittings are static.

## Asset statistics

| Item | Delivered value |
|---|---:|
| Triangles | 1,051,578 |
| Vertices, summed over mesh primitives | 608,737 |
| Meshes / total nodes | 608 / 633 |
| Original rig nodes retained | 25 |
| Materials | 20 |
| Embedded texture images | 17 |
| GLB size | 97,953,192 bytes (93.42 MiB) |
| Overall length | 4.196 m |
| Painted body width | 1.802 m |
| Width including mirrors | 2.184 m |
| Ground-to-roof height | 1.443 m |

Primary paint base color and packed roughness/metalness maps are 4K; paint normal and most secondary surfaces are 2K. The instrument map is 2048 x 768; plate/radio maps are 1024 x 256. The asset is deliberately unoptimized: no LODs, material batching or engine draw-call reduction has been applied.

## Validation completed

All original node names, local transforms and parent relationships match. Wheel centers, wheelbase, tracks, tyre radius and width match the source. Original scene/collision metadata is retained; original proxy rendering meshes are removed. All binary accessors, index ranges and embedded images pass the supplied checks, with no detected zero-area triangles or face/vertex-normal winding disagreement.

The GLB was loaded independently through both `trimesh` and `vtkGLTFImporter`; each returned all 608 meshes/actors and matching bounds. A separate portable source rebuild produced a byte-identical GLB. VTK driver-view and exact-side import renders are also included. Steering samples at -30, 0 and +30 degrees found no sampled body/tyre penetration; minimum sampled vertical tyre-to-arch-return clearance is about 32.4 mm. This is finite sampling, not exhaustive collision certification. Calipers do not inherit wheel spin. The steering-wheel visual center remains on the original column axis.

## Target-project checks still required

**This file has not been imported or tested in your Unreal project.** The supplied MotorRig is a named transform hierarchy, not a skinned armature; the source contained no animation clips and none have been invented. Verify your importer preserves and uses that hierarchy rather than flattening it. No Unreal Physics Asset or new gameplay collision mesh is supplied. The original collision dimensions remain metadata, and the untouched bind source is included for your existing collision workflow.

Check transparent material sorting, clearcoat, normal-map convention, scale and animation binding in the actual project. Glass uses an alpha-blend fallback rather than a volume/refraction shader. Packed ORM channels in this asset are R=AO, G=roughness and B=metalness; normal maps were authored in +Y/OpenGL convention. Suspension compression/rebound limits were not supplied, so full travel and gameplay collision have not been certified.

Review images are studio visual checks, not Unreal performance or shading benchmarks. Read `source/README.md` before rebuilding; rebuilding writes a new GLB and reports alongside this file.

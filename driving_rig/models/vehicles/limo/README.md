# AUREL / REGENT 600
## Limousine - complete modelling and materials review build

Build date: 2026-10-04. Source vehicle: **only `source/limo_bind.glb`** from the supplied MotorRig archive.

The deliverable is `delivery/limo_aurel_regent600.glb`. It is a self-contained GLB with geometry, materials and all 23 texture images embedded. No external texture files are needed to open it. The separate PNGs are included for material editing.

This is a complete review asset, not a primary-shell-only blockout. It is **not yet production-approved in Unreal**. The scene has been imported independently by two implementations, but Unreal Editor, the user's MotorRig runtime and packaged gameplay have not been run here. The original nodes are preserved; the relocated visual steering wheel requires the explicit binding described below.

## Design

Regent 600 is a formal, fictional coachbuilt stretch limousine, with a gently crowned long hood, upright front, continuous shoulder, four side glazing sections per side, a long formal roof, and a distinct rear deck. The architecture was authored around the original 6 m wheelbase, rather than stretched from an earlier passenger-car mesh. Main surfaces are individually authored longitudinal and cross-section curves with integrated wheel-arch shaping; trim and fittings were added afterward. The front and rear cap-to-side transitions were revised to match both position and tangent planes, and curved trim surfaces use derivative-evaluated normals rather than shading driven by their triangulation.

The visual body is allowed to exceed the crude original box. The model has not been constrained into an implausibly low roof or a cabin dictated by the legacy steering location. The working brand and model names are fictional design labels, not a claim of trademark clearance.

Reference roles were kept separate: Mercedes-Maybach Pullman for formal limousine cabin organization; Rolls-Royce Phantom Extended for a long hood and formal shoulder/deck relationship; and Cabot/Royale stretch vehicles for extended passenger compartment layouts. This model is not a dimensionally accurate replica of any of them.

## Measurements

All values below are measured in the exported asset or the original rig, not inferred from a photograph.

| Measurement | Original / required | Delivered |
| --- | ---: | ---: |
| Wheelbase | 6,000 mm | 6,000 mm |
| Front track, wheel-centre to wheel-centre | 1,650 mm | 1,650 mm |
| Rear track, wheel-centre to wheel-centre | 1,650 mm | 1,650 mm |
| Tyre radius | 370 mm | 370 mm, within float32 tolerance |
| Tyre width | 250 mm | 250 mm |
| Body proxy dimensions, width / height / length | 2,000 / 1,450 / 8,500 mm | Metadata unchanged |
| Visual overall length | Not authoritative | 8,590 mm |
| Visual overall width including mirrors | Not authoritative | 2,358 mm |
| Visual height from ground | Not authoritative | 1,661 mm |

Native GLB axes are **X right, Y up, -Z forward**, in metres. The Python authoring space is X right, Z up, +Y forward. The exporter performs the coordinate conversion; do not reinterpret the source GLB as Z-up.

Original wheel centres in native GLB coordinates:

| Wheel | X | Y (height) | Z |
| --- | ---: | ---: | ---: |
| FL | -0.825 | 0.369984382041736 | -3.000 |
| FR | 0.825 | 0.369984382041736 | -3.000 |
| RL | -0.825 | 0.370015617958264 | 3.000 |
| RR | 0.825 | 0.370015617958264 | 3.000 |

The tiny front/rear height difference is retained. The front tyres consequently reach approximately 0.016 mm below nominal Y=0, exactly as implied by the original hard points; this was not silently corrected.

## Model contents

The exterior contains the main shell, shaped hood and deck, real cut window apertures and returns, separate clear glass, pillar trim and seals, door and panel divisions, handles, mirrors, wipers, wheel-arch hems and liners. Front and rear have different structures: a recessed formal grille with separate vanes and projector lamps at the front, and separate red lamp assemblies, numberplate recess and reflectors at the rear.

Each wheel includes a shaped tyre with geometric tread, rim and paired spokes, hub and fixings, brake disc and caliper. The calipers and non-spinning suspension components are attached below the suspension nodes, not the wheel-spin nodes. Underbody pieces are present where visible; this is not an engineering-accurate mechanical model.

The cabin contains two front seats, two rear-facing guest seats and two forward-facing rear executive seats, dashboard, instrument and navigation graphics, steering wheel and controls, centre consoles and cupholders, pedals, interior door structures, headliner, lighting and a transparent division. Doors, seats and fittings are static as requested.

## Textures and shading

There are 23 embedded PNGs: three 4K paint maps; 2K leather, walnut, rubber, wool and brushed-alloy maps; a 2K instrument graphic; and 1K-class navigation, passenger display, clock, climate, steering-control and plate graphics. All dimensions are powers of two.

The principal surface maps are **tileable, physically scaled material textures**, not a unique 4K vehicle atlas or a baked photographic body texture. UI surfaces have dedicated UVs. ORM channels are R=occlusion, G=roughness, B=metallic. Normal maps use the glTF/OpenGL positive-green convention. Base colour and emissive maps are colour textures; normal and ORM maps are data textures.

Paint carries `KHR_materials_clearcoat`; some lamp/display materials use `KHR_materials_emissive_strength`. Transparent cabin glass uses alpha-blend PBR as the portable baseline, with separate mesh objects and a base alpha of 0.12. It does not require a transmission/refraction extension. Suggested glass IOR/transmission values are included as metadata, not an assertion that every receiving renderer will implement them.

## Rig preservation and the steering exception

All **25 original nodes** remain at their original indices with their original names, local TRS fields and original parent relationships. Existing parent nodes gain new children for visual geometry. The original file contains a transform hierarchy but **no skin and no animation clips**; this build does not invent a skeletal rig or pre-authored driving animation.

Original proxy mesh payloads are retained byte-for-byte but are no longer referenced by visible nodes. The former mesh index is recorded in each relevant original node's `extras.motorRigSourceProxyMesh`. Original scene metadata, including `body_size`, remains unchanged. There was no Unreal-specific physics asset in the source to preserve or synthesize.

The original steering-column position is physically unsuitable for the designed cabin. Moving that legacy node would break the transform contract; placing a wheel off-centre under the original spin pivot would make the wheel orbit when steered. Instead the model retains the legacy nodes and adds:

```
chassis
  steering_column                  [unchanged legacy branch]
    steering_wheel                 [unchanged input rotation]
      steering_rim_geo             [original proxy no longer visible]
      steering_spoke_geo
      steering_marker_geo
  steering_visual_column           [logical cabin position]
    steering_visual_pivot          [new visible wheel assembly]
```

**Required runtime binding: copy the LOCAL rotation of `steering_wheel` to `steering_visual_pivot` after MotorRig updates it. Do not copy its translation or complete transform.** Both spin nodes have identity bind rotations, and both column parents have the same orientation. The logical wheel centre is native GLB `(-0.430, 1.005, -1.716)` metres. Detailed integration notes are in `UNREAL_INTEGRATION.md`.

## Validation and review

`reports/validation.json` records all performed checks. They pass for the delivered SHA-256 hash. Checks include exact preservation of the original graph/transforms/world matrices, original metadata and proxy bytes; wheel measurements and full spinning-assembly envelopes; a mathematical steering-binding rotation test; finite vertex attributes; valid indices; unit normals and orthogonal tangents; no triangles collapsing in float32; no visible proxy references; and successful decoding of all embedded PNG images.

Independent import was performed with trimesh 4.11.1 for geometry and hierarchy (materials deliberately skipped there), and VTK 9.6.2 `vtkGLTFImporter` for the material-bearing GLB. VTK loaded all 713 renderable objects, including 266 with texture assignments. `renders/imported_glb_front34.png` was rendered from that independently imported GLB, rather than reconstructed from the authoring scene.

The eight `renders/review_*.png` views are actual mesh renders at 2200 pixels wide: front three-quarter, rear three-quarter, exact side, front, rear, driver, passenger cabin and a front/wheel detail. The `primary_v2_*.png` files are the earlier undecorated shell diagnostics. Review lighting uses VTK PBR, an analytic studio environment and screen-space ambient occlusion; these are not path-traced Unreal renders or generated concept images.

**Not certified here:** Unreal import/material conversion; live MotorRig behaviour; a full steering/suspension collision sweep; the official Khronos validator; engineering watertightness or Class-A continuity; or final artistic approval. Static wheel fit was visually reviewed and rim/body hard points checked, but the nominal 47 mm radial arch clearance is not a guarantee of clearance at arbitrary suspension travel or steering angles.

## Build statistics

The final exported scene has 1,542,411 triangles, 851,365 exported vertices and 713 renderable mesh objects. It is an intentionally unoptimized, separated-detail review build, not a draw-call-optimized game package. These counts are disclosure, not a quality claim. There are 42 material entries including preserved source entries. File size is 104,836,296 bytes.

SHA-256: `9f3e1194c2c51ccfba1ada03fe2cbbcaadbde09b83b874f0dcc41a191030a1c6`

## Source and rebuild

The authored surface definitions, detailing, texture generation, export and validation scripts are included. This is a Python-authored mesh asset; no native Blender or Maya scene, NURBS history, subdivision cage or hand-retopologized editable master is implied. The GLB can be the interchange input for subsequent DCC work.

Install `requirements.txt` in a Python 3.11+ environment and run from the package root:

```
python scripts/rebuild.py
```

This regenerates geometry, texture PNGs, the GLB and structural validation. It never accesses other passenger-car files. To also render:

```
python scripts/rebuild.py --render --size 2200
```

On a Linux machine without an active display, run the rendering command under an appropriate offscreen/Xvfb environment. Windows and macOS still require working VTK/OpenGL support. Those operating-system rebuilds have not been tested here. Rendering and 4K texture generation are memory-intensive.

No font files are distributed. Texture generation uses installed fonts, optionally set with `AUREL_FONT_REGULAR` and `AUREL_FONT_BOLD`; a different installed font may change the regenerated UI typography. Intermediate `.scene` files generated by the scripts are Python pickles for local authoring only. Do not load untrusted pickle files.

## Reference sources

Production reference, not a donor-mesh source:

- Mercedes-Benz, new Mercedes-Maybach Pullman: length 6,499 mm, wheelbase 4,418 mm, height 1,598 mm. https://media.mercedes-benz.pl/nowy-mercedes-maybach-pullman---nawyzszej-klasy-limuzyna-z-elitarnym-rodowodem/
- Rolls-Royce, Phantom Extended, official model imagery and architectural reference. https://www.rolls-roycemotorcars.com/en_GB/showroom/phantom-extended.html
- Cabot Coach / Royale, 120-inch MKT stretch and related coachbuilt layouts. https://www.cabotcoach.com/vehicles/120-inch-MKT.aspx

No later passenger-car model, geometry or texture from the earlier session was used. Only the limousine is included; the other vehicles remain untouched.

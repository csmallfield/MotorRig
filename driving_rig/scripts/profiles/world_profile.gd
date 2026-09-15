@tool
class_name WorldProfile
extends Resource
## The world: terrain (procedural or an imported set) plus world physics. Edit in the
## Inspector. Profiles live in res://profiles/worlds or user://profiles/worlds.
##
## Surface grip and air density are *physics*, not geometry: a wet world with the same
## terrain shares its collision source (and so its scene export) with the dry one.

enum Source { PROCEDURAL, SCENE, CITY }

## The profile the running scene was built with (set by Terrain). Read by the car.
static var active: WorldProfile

@export_group("Identity")
@export var display_name: String = "Default Hills"
@export_multiline var description: String = ""

@export_group("Physics")
@export var gravity: float = 9.81
## Physics ticks per second. Car tuning is rate-dependent: keep this at the car profiles'
## tuned_at_hz unless you retune. 240 divides evenly into 24/30/48/60/120.
@export_range(60, 480) var tick_hz: int = 240
## Multiplies every tyre's grip: 1.0 dry tarmac, ~0.7 wet, ~0.5 gravel, ~0.15 snow.
@export_range(0.05, 2.0) var surface_grip: float = 1.0
## Multiplies aerodynamic drag (1.0 = sea level).
@export_range(0.0, 3.0) var air_density_scale: float = 1.0

@export_group("Terrain")
@export var source: Source = Source.PROCEDURAL
@export var imported_scene: PackedScene       ## SCENE: every mesh gets a trimesh collider
@export var seed_value: int = 1234
@export var size: float = 800.0
@export var cell: float = 2.0
@export var flat_radius: float = 150.0
@export var blend_distance: float = 120.0
@export var amplitude: float = 14.0
@export var frequency: float = 0.006
@export_range(1, 6) var octaves: int = 3
@export var build_test_props: bool = true   ## PROCEDURAL: bumps/ramp/mark. CITY: hydrants and poles.

@export_group("City")
## Blocks east-west (between avenues) and north-south (between streets).
@export_range(1, 8) var city_blocks_x: int = 2
@export_range(1, 12) var city_blocks_z: int = 5
## Manhattan at real size: blocks 900 x 264 ft, avenues 100 ft, streets 60 ft, sidewalks 15 ft,
## curbs 6 in. block_size_x runs east-west (the long way, avenue to avenue).
@export var block_size_x: float = 274.3
@export var block_size_z: float = 80.5
@export var avenue_width: float = 30.5
@export var street_width: float = 18.3
@export var sidewalk_width: float = 4.6
@export var curb_height: float = 0.15
@export var building_depth: float = 24.0
@export var lot_width_min: float = 11.0
@export var lot_width_max: float = 26.0
@export var building_height_min: float = 14.0
@export var building_height_max: float = 58.0
@export var city_road_markings: bool = true


func to_dict() -> Dictionary:
	var d := {}
	for p in get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var v: Variant = get(p["name"])
		if v is float or v is int or v is bool or v is String:
			d[p["name"]] = v
	if imported_scene:
		d["imported_scene"] = imported_scene.resource_path
	return d


func summary() -> String:
	var terrain := ""
	match source:
		Source.SCENE:
			terrain = "scene: %s" % (imported_scene.resource_path.get_file() if imported_scene else "(none set)")
		Source.CITY:
			terrain = "city %dx%d blocks (%.0f x %.0f m)%s" % [city_blocks_x, city_blocks_z,
				city_blocks_x * block_size_x + (city_blocks_x + 1) * avenue_width,
				city_blocks_z * block_size_z + (city_blocks_z + 1) * street_width,
				", hydrants + poles" if build_test_props else ""]
		_:
			terrain = "seed %d, %d m, hills %.1f m%s" % [seed_value, int(size), amplitude,
				", props" if build_test_props else ""]
	return "%s  |  g %.2f  |  %d Hz  |  grip %.2f%s" % [terrain, gravity, tick_hz, surface_grip,
			("  |  air x%.2f" % air_density_scale) if not is_equal_approx(air_density_scale, 1.0) else ""]

class_name TakeIndex
extends RefCounted
## Per-take user metadata that must not live inside the take file: display label,
## favourite, and a cached copy of the header (gzipped takes can't be read one line at a
## time, so listing them would otherwise mean decompressing every file). File names stay stable (`take_0007.json`) so anything downstream that points
## at a take — a Maya scene, a shot sheet — never breaks when someone renames it.

const SETTINGS: String = "_settings"

var _cfg := ConfigFile.new()
var _path: String


func _init(takes_dir: String) -> void:
	_path = takes_dir.path_join("index.cfg")
	_cfg.load(_path)   # missing file is fine


func get_label(file: String) -> String:
	return _cfg.get_value(file, "label", "")


func set_label(file: String, label: String) -> void:
	_cfg.set_value(file, "label", label.strip_edges())
	_cfg.save(_path)


func is_favourite(file: String) -> bool:
	return _cfg.get_value(file, "favourite", false)


func set_favourite(file: String, fav: bool) -> void:
	_cfg.set_value(file, "favourite", fav)
	_cfg.save(_path)


func get_header(file: String) -> Dictionary:
	return _cfg.get_value(file, "header", {})


func set_header(file: String, header: Dictionary) -> void:
	_cfg.set_value(file, "header", header)
	_cfg.save(_path)


func forget(file: String) -> void:
	if _cfg.has_section(file):
		_cfg.erase_section(file)
		_cfg.save(_path)


func get_setting(key: String, default: Variant) -> Variant:
	return _cfg.get_value(SETTINGS, key, default)


func set_setting(key: String, value: Variant) -> void:
	_cfg.set_value(SETTINGS, key, value)
	_cfg.save(_path)

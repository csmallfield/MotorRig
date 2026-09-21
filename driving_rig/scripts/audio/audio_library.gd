class_name AudioLibrary
extends RefCounted
## Finds sound files on disk so you can drop them in without touching any code.
##
## Looked for in this order, first hit wins:
##     res://audio/<car profile file name>/     e.g. res://audio/city_bus/
##     res://audio/default/
##     user://audio/<car profile file name>/    (AppData - works in an exported build too)
##     user://audio/default/
##
## Names (.ogg preferred, .wav also works):
##     engine_<rpm>.ogg   one or more steady loops, named for the rpm they were recorded at:
##                        engine_0800.ogg, engine_2500.ogg, engine_5200.ogg. The rig crossfades
##                        between the two nearest and pitches each to the exact rpm, so two or
##                        three layers already sound convincing. A single file works too.
##     tyre_roll.ogg      rolling road noise, loops; gain and pitch follow road speed
##     skid.ogg           tyre scrub/squeal, loops; gain follows how hard the tyres are sliding
##     wind.ogg           loops; gain follows speed
##     scrape.ogg         body dragging along something, loops
##     impact_01.ogg ...  one-shot hits, any number; one is picked at random with a little
##                        pitch variance each time
##     bump_01.ogg ...    suspension thumps on landings and kerbs, same random treatment
##
## Anything missing is simply silent - the rig never errors over a sound it can't find.

const EXTS: PackedStringArray = ["ogg", "wav"]
const ROOT_RES: String = "res://audio"
const ROOT_USER: String = "user://audio"

var _sets: PackedStringArray = PackedStringArray()   # search order, most specific first
var missing: PackedStringArray = PackedStringArray() # what wasn't found, for the report


func _init(vehicle_set: String = "") -> void:
	for root in [ROOT_RES, ROOT_USER]:
		if vehicle_set != "":
			_sets.append(root.path_join(vehicle_set))
		_sets.append(root.path_join("default"))


## One stream by base name ("skid"), or null.
func one(base: String) -> AudioStream:
	for dir in _sets:
		for ext in EXTS:
			var s := _load(dir.path_join("%s.%s" % [base, ext]))
			if s:
				return s
	missing.append(base)
	return null


## Every numbered variant of a base name ("impact" -> impact_01, impact_02, ...), from the
## first set that has any.
func variants(base: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for dir in _sets:
		for f in _files_in(dir):
			var stem := f.get_basename()
			if stem.begins_with(base + "_") and stem.trim_prefix(base + "_").is_valid_int():
				var s := _load(dir.path_join(f))
				if s:
					out.append(s)
		if not out.is_empty():
			return out
	missing.append(base + "_NN")
	return out


## Engine layers as [{rpm: float, stream: AudioStream}], sorted by rpm. Reads the rpm out of
## the file name: engine_2500.ogg was recorded at 2500 rpm.
func engine_layers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dir in _sets:
		for f in _files_in(dir):
			var stem := f.get_basename()
			if not stem.begins_with("engine_"):
				continue
			var tail := stem.trim_prefix("engine_")
			var rpm := 0.0
			if tail.is_valid_int():
				rpm = float(tail.to_int())
			elif tail == "idle":
				rpm = 800.0
			else:
				continue
			var s := _load(dir.path_join(f))
			if s:
				out.append({"rpm": rpm, "stream": s})
		if not out.is_empty():
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["rpm"] < b["rpm"])
			return out
	missing.append("engine_<rpm>")
	return out


## What was found, for the HUD / a one-line report.
func describe() -> String:
	var found := PackedStringArray()
	for dir in _sets:
		var n := _files_in(dir).size()
		if n > 0:
			found.append("%s (%d)" % [dir, n])
	return "audio: " + (", ".join(found) if not found.is_empty() else "no files found - silent")


func _files_in(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		var name := f.trim_suffix(".remap")     # exported builds list imported files this way
		if name.get_extension().to_lower() in EXTS:
			out.append(name)
	return out


func _load(path: String) -> AudioStream:
	if path.begins_with("res://"):
		return ResourceLoader.load(path, "AudioStream") as AudioStream if ResourceLoader.exists(path) else null
	# user:// is outside the import pipeline: read it off disk at run time
	if not FileAccess.file_exists(path):
		return null
	if path.get_extension().to_lower() == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	var bytes := FileAccess.get_file_as_bytes(path)
	return AudioStreamWAV.load_from_buffer(bytes) if bytes.size() > 44 else null


## Loops are what a continuous sound needs; set it whatever the import settings say.
static func set_looping(stream: AudioStream, on: bool = true) -> AudioStream:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = on
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED
		if on and (stream as AudioStreamWAV).loop_end <= 0:
			(stream as AudioStreamWAV).loop_end = (stream as AudioStreamWAV).data.size()
	return stream

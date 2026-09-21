class_name TakeAudioCapture
extends RefCounted
## Records what you actually heard while the take was running, straight off the master bus,
## and writes it next to the take as a .wav.
##
## It is a real-time capture, so it only works when the game is running normally - a headless
## or fast-forwarded run has no audio clock to capture and this quietly does nothing. The
## recording starts on the take's first sample (handles included), which is what the Maya
## importer lines the sound up to.

const EFFECT_NAME: String = "drv_take_record"

var recording: bool = false
var last_error: String = ""

var _effect: AudioEffectRecord
var _bus: int = 0


## Start capturing the master bus. Returns false (with last_error set) if audio isn't running.
func start() -> bool:
	last_error = ""
	if recording:
		stop_and_discard()
	if AudioServer.get_bus_count() == 0:
		last_error = "no audio bus"
		return false
	_bus = 0                                     # master: everything the player heard
	_effect = AudioEffectRecord.new()
	_effect.resource_name = EFFECT_NAME
	AudioServer.add_bus_effect(_bus, _effect)
	_effect.set_recording_active(true)
	recording = true
	return true


## Stop and write `path` (a .wav). Returns "" on success, or why it didn't happen.
func stop_and_save(path: String) -> String:
	if not recording:
		return "not recording"
	var stream := _finish()
	if stream == null or stream.data.size() == 0:
		return "nothing was captured (no audio device?)"
	var err := stream.save_to_wav(path)
	return "" if err == OK else "save failed: %s" % error_string(err)


func stop_and_discard() -> void:
	if recording:
		_finish()


func _finish() -> AudioStreamWAV:
	recording = false
	var stream: AudioStreamWAV = null
	if _effect:
		_effect.set_recording_active(false)
		if _effect.is_recording_active() == false:
			stream = _effect.get_recording()
		for i in range(AudioServer.get_bus_effect_count(_bus) - 1, -1, -1):
			if AudioServer.get_bus_effect(_bus, i) == _effect:
				AudioServer.remove_bus_effect(_bus, i)
		_effect = null
	return stream


## Path a take's audio lives at: the take file with its extensions swapped for .wav.
static func wav_path_for(take_path: String) -> String:
	var base := take_path.trim_suffix(".gz")
	return base.get_basename() + ".wav"

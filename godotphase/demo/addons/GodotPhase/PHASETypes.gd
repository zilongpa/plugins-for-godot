# Copyright © 2026 Apple Inc.

extends RefCounted

## Static utility types and methods for PHASE framework
## Used by editor tools without requiring runtime PHASE engine

enum GodotPHASEReverbPreset {
	REVERB_PRESET_NONE = 0,
	REVERB_PRESET_SMALL_ROOM = 1,
	REVERB_PRESET_MEDIUM_ROOM = 2,
	REVERB_PRESET_LARGE_ROOM = 3,
	REVERB_PRESET_LARGE_ROOM_2 = 4,
	REVERB_PRESET_MEDIUM_CHAMBER = 5,
	REVERB_PRESET_LARGE_CHAMBER = 6,
	REVERB_PRESET_MEDIUM_HALL = 7,
	REVERB_PRESET_MEDIUM_HALL_2 = 8,
	REVERB_PRESET_MEDIUM_HALL_3 = 9,
	REVERB_PRESET_LARGE_HALL = 10,
	REVERB_PRESET_CATHEDRAL = 11
}

enum PHASEMixerType {
	SPATIAL = 0,
	CHANNEL = 1,
	AMBIENT = 2
}

static func mixer_type_to_string(mixer_type: PHASEMixerType) -> String:
	match mixer_type:
		PHASEMixerType.AMBIENT:
			return "Ambient"
		PHASEMixerType.CHANNEL:
			return "Channel"
		PHASEMixerType.SPATIAL:
			return "Spatial"
		_:
			return "Unknown"

static func mixer_type_from_string(type_str: String) -> PHASEMixerType:
	match type_str.to_lower():
		"ambient":
			return PHASEMixerType.AMBIENT
		"channel":
			return PHASEMixerType.CHANNEL
		"spatial":
			return PHASEMixerType.SPATIAL
		_:
			return PHASEMixerType.SPATIAL

# Copyright © 2026 Apple Inc.

extends Node

const PHASETypes = preload("res://addons/GodotPhase/PHASETypes.gd")

var phase_manager: PHASEManager

func _ready():
	phase_manager = PHASEManager.new()
	add_child(phase_manager)

func _exit_tree():
	if phase_manager:
		phase_manager.queue_free()

func initialize_engine() -> bool:
	if phase_manager:
		return phase_manager.initialize_engine()
	return false

func shutdown_engine():
	if phase_manager:
		phase_manager.shutdown_engine()

func is_engine_initialized() -> bool:
	if phase_manager:
		return phase_manager.is_engine_initialized()
	return false

func set_scene_reverb_preset(preset):
	if phase_manager:
		phase_manager.set_scene_reverb_preset(preset)

func get_scene_reverb_preset():
	if phase_manager:
		return phase_manager.get_scene_reverb_preset()
	return PHASETypes.GodotPHASEReverbPreset.REVERB_PRESET_SMALL_ROOM

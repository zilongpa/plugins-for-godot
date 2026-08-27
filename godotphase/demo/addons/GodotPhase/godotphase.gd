# Copyright © 2026 Apple Inc.

@tool
extends EditorPlugin

const PHASEExportPlugin = preload("res://addons/GodotPhase/phase_export_plugin.gd")

var export_plugin

func _enter_tree() -> void:
	export_plugin = PHASEExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	if export_plugin:
		remove_export_plugin(export_plugin)
		export_plugin = null

func _enable_plugin() -> void:
	add_autoload_singleton("PhaseManagerSingleton", "res://addons/GodotPhase/PhaseManagerSingleton.gd")

func _disable_plugin() -> void:
	remove_autoload_singleton("PhaseManagerSingleton")

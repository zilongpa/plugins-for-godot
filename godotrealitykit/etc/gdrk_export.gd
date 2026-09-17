#===----------------------------------------------------------------------===#
# Copyright © 2026 Apple Inc.
#
# Licensed under the MIT license (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# LICENSE
#
#===----------------------------------------------------------------------===#

@tool
class_name GDRKEditorExportPlugin
extends EditorExportPlugin

var _pending_visionos_path: String = ""

func _get_name() -> String:
	return "Godot-RealityKit Export Plugin"

func _supports_platform(platform) -> bool:
	var os_name: String = platform.get_os_name()
	if os_name == "visionOS":
		return true
	if os_name == "macOS":
		return ProjectSettings.get_setting("reality_kit/debug_rendering_on_macos", false)
	return false

func _get_features(platform, debug) -> PackedStringArray:
	return PackedStringArray(["gdrk"])

func _get_export_options_overrides(platform: EditorExportPlatform) -> Dictionary:
	if platform is not EditorExportPlatformVisionOS:
		return {}
	else:
		return {
			"custom_template/debug": "./addons/GodotRealityKit/visionos.template_debug/godot_visionos.zip",
			"custom_template/release": "./addons/GodotRealityKit/visionos.template_release/godot_visionos.zip"
		}

func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	_pending_visionos_path = path if features.has("visionos") else ""

func _export_end() -> void:
	if _pending_visionos_path.is_empty():
		return
	var path := _pending_visionos_path
	_pending_visionos_path = ""
	_enable_simulator_launch(path)
	var plist_path := _resolve_visionos_info_plist(path)
	if plist_path.is_empty():
		return
	var f := FileAccess.open(plist_path, FileAccess.READ)
	if f == null:
		push_warning("GDRK export: cannot read %s (err %d)" % [plist_path, FileAccess.get_open_error()])
		return
	var contents := f.get_as_text()
	f.close()

	var false_marker := "<key>UIApplicationSupportsMultipleScenes</key><false/>"
	if contents.contains(false_marker):
		contents = contents.replace(false_marker, "<key>UIApplicationSupportsMultipleScenes</key><true/>")
		print("GDRK export: set UIApplicationSupportsMultipleScenes=true in %s" % plist_path)
	elif not contents.contains("UIApplicationSupportsMultipleScenes"):
		push_warning("GDRK export: UIApplicationSupportsMultipleScenes not found in %s" % plist_path)

	var closing_marker := "</dict>\n</plist>"

	# Every GodotRealityKit view (volumetric window, portal, or immersive space) installs a
	# SpatialEventGesture on scene entities, which makes RealityKit implicitly start an
	# ARKitSession and request world-sensing authorization. This is unconditional: it happens
	# regardless of presentation style or project settings.
	if not contents.contains("NSWorldSensingUsageDescription"):
		contents = _add_usage_description(
			contents, plist_path, closing_marker,
			"NSWorldSensingUsageDescription",
			"Used to detect and understand the surrounding space for content placement."
		)

	var hand_tracking_enabled: bool = ProjectSettings.get_setting("xr/visionos/enable_hand_tracking", false)
	if hand_tracking_enabled and not contents.contains("NSHandsTrackingUsageDescription"):
		contents = _add_usage_description(
			contents, plist_path, closing_marker,
			"NSHandsTrackingUsageDescription",
			"Used to track hand position and gestures for interacting with content."
		)

	var controller_tracking_enabled: bool = ProjectSettings.get_setting("xr/visionos/enable_controller_tracking", false)
	if controller_tracking_enabled and not contents.contains("NSAccessoryTrackingUsageDescription"):
		contents = _add_usage_description(
			contents, plist_path, closing_marker,
			"NSAccessoryTrackingUsageDescription",
			"Used to track spatial controllers for interacting with content."
		)

	var w := FileAccess.open(plist_path, FileAccess.WRITE)
	if w == null:
		push_warning("GDRK export: cannot write %s (err %d)" % [plist_path, FileAccess.get_open_error()])
		return
	w.store_string(contents)
	w.close()

func _add_usage_description(contents: String, plist_path: String, closing_marker: String, key: String, value: String) -> String:
	if not contents.contains(closing_marker):
		push_warning("GDRK export: could not find closing </dict></plist> in %s" % plist_path)
		return contents
	var addition := "\t<key>%s</key>\n\t<string>%s</string>\n" % [key, value]
	print("GDRK export: added %s to %s" % [key, plist_path])
	return contents.replace(closing_marker, addition + closing_marker)

func _resolve_visionos_info_plist(export_path: String) -> String:
	var project_dir := export_path.get_base_dir()
	var binary_name := export_path.get_file().get_basename()
	var candidate := "%s/%s/%s-Info.plist" % [project_dir, binary_name, binary_name]
	if FileAccess.file_exists(candidate):
		return candidate
	push_warning("GDRK export: Info.plist not found at %s" % candidate)
	return ""

# The engine reads this flag only when compiled for the visionOS Simulator.
func _enable_simulator_launch(export_path: String) -> void:
	var binary_name := export_path.get_file().get_basename()
	var scheme_path := "%s/%s.xcodeproj/xcshareddata/xcschemes/%s.xcscheme" % [export_path.get_base_dir(), binary_name, binary_name]
	var file := FileAccess.open(scheme_path, FileAccess.READ)
	if file == null:
		push_warning("GDRK export: cannot read scheme %s" % scheme_path)
		return
	var contents := file.get_as_text()
	file.close()
	var launch_pattern := RegEx.new()
	launch_pattern.compile("(?s)<LaunchAction\\b.*?</LaunchAction>")
	var launch := launch_pattern.search(contents)
	if launch == null:
		push_warning("GDRK export: LaunchAction missing in %s" % scheme_path)
		return
	var section := launch.get_string()
	var flag_pattern := RegEx.new()
	flag_pattern.compile('(?s)<EnvironmentVariable\\s+[^>]*\\bkey\\s*=\\s*"GDRK_SIMULATOR_SKIP_GPU_CHECK"[^>]*/>')
	section = flag_pattern.sub(section, "", true)
	var entry := '<EnvironmentVariable key="GDRK_SIMULATOR_SKIP_GPU_CHECK" value="1" isEnabled="YES"/>'
	if section.contains("</EnvironmentVariables>"):
		section = section.replace("</EnvironmentVariables>", entry + "\n      </EnvironmentVariables>")
	else:
		var empty_variables := RegEx.new()
		empty_variables.compile("<EnvironmentVariables\\s*/>")
		section = empty_variables.sub(section, "", true)
		section = section.replace("</LaunchAction>", "<EnvironmentVariables>\n         " + entry + "\n      </EnvironmentVariables>\n   </LaunchAction>")
	contents = contents.substr(0, launch.get_start()) + section + contents.substr(launch.get_end())
	file = FileAccess.open(scheme_path, FileAccess.WRITE)
	if file == null:
		push_warning("GDRK export: cannot write scheme %s" % scheme_path)
		return
	file.store_string(contents)
	file.close()
	print("GDRK export: enabled simulator GPU override in %s" % scheme_path)

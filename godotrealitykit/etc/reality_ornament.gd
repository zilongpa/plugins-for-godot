@tool
class_name RealityOrnament
extends Window
## Hosts ordinary Godot Controls in a native visionOS volume ornament.
## On other platforms the same content opens in a regular window.

## RealitySceneTree volume ID, not a DisplayServer window ID. Main volume is 0.
@export var volume_id: int = 0
## Reuses the GodotVisionOS addon's VisionOSHoverRoot2D for native gaze highlights.
@export var hover_enabled := true:
	set(value):
		hover_enabled = value
		_sync_hover_root()
## Native layout size in points. Godot receives the corresponding pixel size.
@export var panel_size := Vector2i(480, 260):
	set(value):
		panel_size = value.max(Vector2i.ONE)
		if is_inside_tree() and not Engine.is_editor_hint():
			_apply_size()
@export var show_on_ready := true
var _hover_root: Node


func _init() -> void:
	visible = false
	force_native = true
	transient = false
	exclusive = false
	transparent = true
	transparent_bg = true
	wrap_controls = false
	# Popup menus remain in this panel instead of becoming independent scenes.
	gui_embed_subwindows = true


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_sync_hover_root()
	close_requested.connect(hide)
	if get_tree().has_signal("volume_window_destroyed"):
		get_tree().connect("volume_window_destroyed", _on_volume_destroyed)
	if show_on_ready:
		# Complete the scene-tree setup before creating a native view.
		attach_to_volume.call_deferred(volume_id)


## Call after open_volume_window returns the target ID. Hiding preserves child UI state.
## Reattaching a visible panel recreates only its native view, not its Controls.
func attach_to_volume(target_volume: int = 0) -> Error:
	if not is_inside_tree() or Engine.is_editor_hint():
		return ERR_UNCONFIGURED
	if target_volume < 0:
		return ERR_INVALID_PARAMETER
	if OS.has_feature("visionos"):
		if not get_tree().has_method("has_volume_window"):
			return ERR_UNAVAILABLE
		if not get_tree().call("has_volume_window", target_volume):
			return ERR_DOES_NOT_EXIST
	# Window must be hidden before changing its hosting metadata.
	hide()
	volume_id = target_volume
	set_meta("gdrk_ornament_volume_id", volume_id)
	_apply_size()
	show()
	return OK


func is_native_visible() -> bool:
	return visible and (not OS.has_feature("visionos") or bool(get_meta("gdrk_native_open", false)))


func _apply_size() -> void:
	var native_scale := DisplayServer.screen_get_scale() if OS.has_feature("visionos") else 1.0
	size = Vector2i(Vector2(panel_size) * maxf(native_scale, 1.0))
	content_scale_size = panel_size
	content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


func _sync_hover_root() -> void:
	if not is_inside_tree() or Engine.is_editor_hint():
		return
	if is_instance_valid(_hover_root):
		_hover_root.set("enabled", hover_enabled)
		return
	if not hover_enabled: return
	if not ClassDB.class_exists("VisionOSHoverRoot2D"):
		if OS.has_feature("visionos"):
			push_warning("RealityOrnament hover requires addons/GodotVisionOS. The panel remains usable without hover.")
		return
	_hover_root = ClassDB.instantiate("VisionOSHoverRoot2D")
	_hover_root.name = "NativeHover"
	add_child(_hover_root)


func get_native_hover_target_count() -> int:
	return int(_hover_root.call("get_active_target_count")) if is_instance_valid(_hover_root) else 0


func _on_volume_destroyed(destroyed_id: int) -> void:
	if destroyed_id == volume_id:
		hide()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if volume_id < 0:
		warnings.append("Volume ID must be nonnegative. Use attach_to_volume(id) for a dynamically created volume.")
	return warnings

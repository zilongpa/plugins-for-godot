extends Control

const Ornament = preload("res://addons/GodotRealityKit/reality_ornament.gd")
const PlaybackState = preload("res://ui/playback_state.gd")
const DEFAULT_PANEL_SIZE := Vector2i(520, 220)
var panel: Window
var transport: Control
var state = PlaybackState.new()
var volume_id := -1
var status: Label
var failures := 0
var checks: Array[Dictionary] = []
var running_checks := false


func _ready() -> void:
	var column := VBoxContainer.new()
	column.position = Vector2(32, 32)
	column.size = Vector2(570, 330)
	add_child(column)
	status = Label.new()
	status.text = "Godot Controls in a volume ornament"
	column.add_child(status)
	for pair in [["Hide panel", _hide_panel], ["Show panel", _show_panel],
		["Close volume", _close_volume], ["Reopen volume", _reopen_volume],
		["Resize panel", _resize_panel], ["Run lifecycle checks", _run_checks]]:
		var button := Button.new()
		button.text = pair[0]
		button.pressed.connect(pair[1])
		column.add_child(button)
	_create.call_deferred()


func _create() -> void:
	var options = ClassDB.instantiate("RealityVolumeWindowOptions")
	options.initial_size = Vector3(0.6, 0.6, 0.6)
	volume_id = int(get_tree().call("open_volume_window", "res://model.tscn", "Ornament model", options))
	panel = Ornament.new()
	panel.show_on_ready = false
	panel.panel_size = DEFAULT_PANEL_SIZE
	panel.title = "Playback panel"
	add_child(panel)
	var margin := MarginContainer.new()
	panel.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text = "Magnetic field — playback"
	column.add_child(title)
	transport = preload("res://ui/playback_bar.tscn").instantiate()
	column.add_child(transport)
	transport.set_compact_layout()
	# Reuse the existing viewer's actual Controls and signals in a compact arrangement.
	var row: HBoxContainer = transport.get_node("Padding/Row")
	var stack := VBoxContainer.new()
	stack.name = "PlaybackRows"
	transport.get_node("Padding").add_child(stack)
	row.reparent(stack)
	for key in ["FrameLabel", "Speed", "Smooth"]:
		row.get_node(key).reparent(stack)
	row.get_node("Position").custom_minimum_size.x = 260
	transport.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	transport.play_requested.connect(func():
		state.playing = not state.playing
		print("ORNAMENT_ACTION playback playing=", state.playing)
		_sync())
	transport.position_requested.connect(func(value): state.position = value; _sync())
	transport.speed_requested.connect(func(value): state.speed = value; _sync())
	state.available = true
	state.maximum = 100
	state.can_smooth = false
	_sync()
	var result := int(panel.attach_to_volume(volume_id))
	print("ORNAMENT_LAB attach=", result, " volume=", volume_id)
	if OS.get_cmdline_user_args().has("--automated"):
		await get_tree().create_timer(5).timeout
		_run_checks()


func _process(delta: float) -> void:
	if not is_instance_valid(transport): return
	if state.playing:
		state.position = fmod(state.position + delta * 10.0 * state.speed, 101.0)
		_sync()
	if volume_id >= 0:
		var root = get_tree().call("get_volume_window_root", volume_id)
		if is_instance_valid(root): root.get_node("Torus").rotation.y = state.position / 100.0 * TAU


func _sync() -> void:
	state.label = "Frame %d / 100" % int(state.position)
	transport.set_state(state)
	status.text = state.label + (" · Playing" if state.playing else " · Paused")


func _hide_panel() -> void: panel.hide()
func _show_panel() -> void: panel.attach_to_volume(volume_id)
func _close_volume() -> void: get_tree().call("close_volume_window", volume_id)
func _reopen_volume() -> void: get_tree().call("reopen_volume_window", volume_id)
func _resize_panel() -> void: panel.panel_size = Vector2i(600, 260) if panel.panel_size == DEFAULT_PANEL_SIZE else DEFAULT_PANEL_SIZE


func _check(condition: bool, message: String) -> void:
	print("ORNAMENT_CHECK ", "PASS " if condition else "FAIL ", message)
	if not condition: failures += 1
	checks.append({"passed": condition, "scenario": message})
	var file := FileAccess.open("user://ornament-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "checks": checks}, "\t"))


func _run_checks() -> void:
	if running_checks: return
	running_checks = true
	failures = 0
	checks.clear()
	_check(panel.is_native_visible(), "panel presented")
	_check(panel.attach_to_volume(-1) == ERR_INVALID_PARAMETER and panel.is_native_visible(), "invalid volume ID preserves the visible panel")
	_check(panel.attach_to_volume(9223372036854775807) == ERR_DOES_NOT_EXIST and panel.is_native_visible(), "missing volume preserves the visible panel")
	await get_tree().create_timer(0.3).timeout
	_check(panel.get_native_hover_target_count() == 3, "GodotVisionOS hover targets registered for button, slider and speed control")
	panel.hover_enabled = false
	await get_tree().create_timer(0.3).timeout
	_check(panel.get_native_hover_target_count() == 0, "native hover can be disabled")
	panel.hover_enabled = true
	var root = get_tree().call("get_volume_window_root", volume_id)
	var root_id: int = root.get_instance_id()
	var initial_size: Vector3 = get_tree().call("get_volume_window_size", volume_id)
	var initial_panel_size: Vector2i = panel.panel_size
	var initial_pixel_size: Vector2i = panel.size
	# UIKit sends pixel-space screen-touch events. Use Input and DisplayServer routing,
	# including Godot's touch-to-mouse emulation needed by Slider.
	var transform := panel.get_final_transform()
	var button: Button = transport.get_node("Padding/PlaybackRows/Row/Play")
	for pressed in [true, false]:
		var click := InputEventScreenTouch.new()
		click.window_id = panel.get_window_id()
		click.position = transform * button.get_global_rect().get_center()
		click.pressed = pressed
		Input.parse_input_event(click)
		Input.flush_buffered_events()
	_check(state.playing, "existing playback button receives routed touch input")
	state.playing = false
	var slider: HSlider = transport.get_node("Padding/PlaybackRows/Row/Position")
	var slider_rect := slider.get_global_rect()
	var start := transform * (slider_rect.position + slider_rect.size * Vector2(0.25, 0.5))
	var finish := transform * (slider_rect.position + slider_rect.size * Vector2(0.75, 0.5))
	var touch := InputEventScreenTouch.new()
	touch.window_id = panel.get_window_id()
	touch.position = start
	touch.pressed = true
	Input.parse_input_event(touch)
	Input.flush_buffered_events()
	var before_drag: float = state.position
	var drag := InputEventScreenDrag.new()
	drag.window_id = panel.get_window_id()
	drag.position = finish
	drag.relative = finish - start
	Input.parse_input_event(drag)
	Input.flush_buffered_events()
	var release := InputEventScreenTouch.new()
	release.window_id = panel.get_window_id()
	release.position = finish
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	_check(state.position > before_drag + 20, "existing slider receives routed touch drag")
	state.position = 37
	_sync()
	_resize_panel()
	await get_tree().create_timer(2).timeout
	var volume_size: Vector3 = get_tree().call("get_volume_window_size", volume_id)
	_check(initial_size.is_equal_approx(volume_size), "panel resize leaves volume size unchanged")
	_check(get_tree().call("get_volume_window_title", volume_id) == "Ornament model", "panel title leaves volume title unchanged")
	# Do not leave the visual comparison at the temporary test size.
	panel.panel_size = initial_panel_size
	await get_tree().create_timer(1).timeout
	_check(panel.content_scale_size == initial_panel_size and panel.size == initial_pixel_size, "resize check restores requested and rendered panel size")
	_hide_panel()
	await get_tree().create_timer(1).timeout
	_check(int(get_tree().call("get_volume_window_state", volume_id)) == 2, "hiding panel leaves volume open")
	_show_panel()
	await get_tree().create_timer(2).timeout
	_check(panel.is_native_visible() and state.position == 37, "reshow preserves UI state")
	_close_volume()
	await get_tree().create_timer(2).timeout
	_check(not panel.is_native_visible(), "closing volume removes native panel")
	_reopen_volume()
	await get_tree().create_timer(3).timeout
	_check(panel.is_native_visible() and state.position == 37, "volume reopen restores panel and state")
	_check(panel.size == initial_pixel_size, "volume reopen preserves panel size")
	_check(panel.get_native_hover_target_count() == 3, "GodotVisionOS hover targets restored after native host recreation")
	_check(get_tree().call("get_volume_window_root", volume_id).get_instance_id() == root_id, "same Godot model after reopen")
	var duplicate := Ornament.new()
	duplicate.show_on_ready = false
	add_child(duplicate)
	duplicate.attach_to_volume(volume_id)
	await get_tree().create_timer(1).timeout
	_check(not duplicate.visible and panel.is_native_visible(), "duplicate panel rejected without disturbing original")
	duplicate.queue_free()
	var other_id: int = get_tree().call("open_volume_window", "res://model.tscn", "Second model")
	var other := Ornament.new()
	other.show_on_ready = false
	add_child(other)
	var label := Label.new()
	label.text = "Independent second-volume panel"
	other.add_child(label)
	other.attach_to_volume(other_id)
	await get_tree().create_timer(4).timeout
	_check(other.is_native_visible() and panel.is_native_visible(), "two volumes own independent panels")
	get_tree().call("destroy_volume_window", other_id)
	await get_tree().create_timer(3).timeout
	_check(not other.visible and not get_tree().call("has_volume_window", other_id), "destroying volume hides its panel")
	_check(panel.is_native_visible() and state.position == 37, "destroying another volume preserves original panel")
	other.queue_free()
	print("ORNAMENT_RESULT failures=", failures)
	status.text = "Lifecycle checks: %d failures" % failures
	running_checks = false

extends PanelContainer
## Playback controls emit intent; the caller owns and advances playback.

const PlaybackState := preload("res://ui/playback_state.gd")
const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]

signal play_requested
signal position_requested(value: float)
signal speed_requested(multiplier: float)
signal smooth_requested(enabled: bool)

@onready var _play: Button = %Play
@onready var _slider: HSlider = %Position
@onready var _label: Label = %FrameLabel
@onready var _smooth: CheckButton = %Smooth
@onready var _speed: OptionButton = %Speed
var _compact_labels := false


func _ready() -> void:
	_play.pressed.connect(func() -> void: play_requested.emit())
	_slider.value_changed.connect(func(value: float) -> void: position_requested.emit(value))
	_smooth.toggled.connect(func(enabled: bool) -> void: smooth_requested.emit(enabled))
	_speed.item_selected.connect(func(index: int) -> void: speed_requested.emit(SPEEDS[index]))


func set_compact_layout() -> void:
	_compact_labels = true
	_slider.custom_minimum_size.x = 100
	_label.custom_minimum_size.x = 160


func set_state(state: PlaybackState) -> void:
	visible = state.available
	# Changing limits or step can clamp the current value and emit value_changed.
	_slider.set_block_signals(true)
	_slider.min_value = 0.0
	_slider.max_value = state.maximum
	_slider.step = state.step
	_slider.value = state.position
	_slider.set_block_signals(false)
	_label.text = state.label
	if _compact_labels:
		_play.text = "Pause (X)" if state.playing else "Play (X)"
	else:
		_play.text = "Pause  (Space)" if state.playing else "Play  (Space)"
	_smooth.visible = state.can_smooth
	_smooth.set_pressed_no_signal(state.smooth)
	_speed.select(SPEEDS.find(state.speed))

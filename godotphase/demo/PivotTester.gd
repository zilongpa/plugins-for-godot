# Copyright © 2026 Apple Inc.

extends Node3D
class_name PivotTester

@export_group("Pivot Controls")
@export var enable_pivot: bool = false : set = set_enable_pivot
@export var pivot_speed: float = 1.0 : set = set_pivot_speed
@export var pivot_radius: float = 3.0 : set = set_pivot_radius

@export_group("Rotation Controls")
@export var enable_rotation: bool = false : set = set_enable_rotation
@export var rotation_speed: Vector3 = Vector3(0, 1, 0) : set = set_rotation_speed

@export_group("Animation Controls")
@export var use_smooth_motion: bool = true
@export var smooth_factor: float = 2.0

var _target_position: Vector3
var _target_rotation: Vector3
var _pivot_time: float = 0.0
var _initial_position: Vector3

func _ready():
	_initial_position = global_transform.origin
	_target_position = _initial_position

func _process(delta: float):
	if enable_pivot:
		_pivot_time += delta * pivot_speed
		var new_pos = Vector3(
			cos(_pivot_time) * pivot_radius,
			_initial_position.y,
			sin(_pivot_time) * pivot_radius
		)
		_target_position = new_pos
	else:
		_target_position = _initial_position

	if enable_rotation:
		_target_rotation += rotation_speed * delta
	else:
		_target_rotation = Vector3.ZERO

	if use_smooth_motion:
		global_transform.origin = global_transform.origin.lerp(_target_position, smooth_factor * delta)
		var target_basis = Basis.from_euler(_target_rotation)
		transform.basis = transform.basis.slerp(target_basis, smooth_factor * delta).orthonormalized()
	else:
		global_transform.origin = _target_position
		transform.basis = Basis.from_euler(_target_rotation)

func set_enable_pivot(value: bool):
	enable_pivot = value

func set_pivot_speed(value: float):
	pivot_speed = max(0.0, value)

func set_pivot_radius(value: float):
	pivot_radius = max(0.1, value)

func set_enable_rotation(value: bool):
	enable_rotation = value

func set_rotation_speed(value: Vector3):
	rotation_speed = value

func reset_to_origin():
	_pivot_time = 0.0
	_target_position = _initial_position
	_target_rotation = Vector3.ZERO
	global_transform.origin = _initial_position
	transform.basis = Basis.IDENTITY

func toggle_pivot():
	enable_pivot = not enable_pivot

func toggle_rotation():
	enable_rotation = not enable_rotation

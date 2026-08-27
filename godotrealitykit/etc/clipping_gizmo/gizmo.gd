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
extends EditorNode3DGizmoPlugin

const HANDLE_SIZE_X = 0
const HANDLE_SIZE_Y = 1
const HANDLE_SIZE_Z = 2

func _get_gizmo_name() -> String:
	return "RealityClipping3D"

func _has_gizmo(for_node_3d: Node3D) -> bool:
	return for_node_3d is RealityClipping3D

func _init():
	create_material("lines", Color(0.23, 0.692, 1.0, 1.0))
	create_material("feather_lines", Color(1.0, 0.6, 0.2, 1.0))
	create_handle_material("handles")

func _get_handle_count(gizmo: EditorNode3DGizmo) -> int:
	return 3

func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	return ["Size X", "Size Y", "Size Z"][handle_id]

func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	var node := gizmo.get_node_3d() as RealityClipping3D
	return node.size

func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d() as RealityClipping3D
	var gt := node.global_transform
	var ray_o := camera.project_ray_origin(screen_pos)
	var ray_d := camera.project_ray_normal(screen_pos)

	var axis: Vector3
	match handle_id:
		HANDLE_SIZE_X:
			axis = gt.basis.x.normalized()
		HANDLE_SIZE_Y:
			axis = gt.basis.y.normalized()
		HANDLE_SIZE_Z:
			axis = gt.basis.z.normalized()

	var d := _project_ray_onto_axis(gt.origin, axis, ray_o, ray_d)
	var size := node.size
	size[handle_id] = max(0.001, abs(d) * 2.0)
	node.size = size

func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool,
		restore: Variant, cancel: bool) -> void:
	var node := gizmo.get_node_3d() as RealityClipping3D
	if cancel:
		node.size = restore
		return
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Set Clipping Size")
	undo.add_do_property(node, "size", node.size)
	undo.add_undo_property(node, "size", restore)
	undo.commit_action()

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d() as RealityClipping3D

	var half_size := node.size * 0.5
	gizmo.add_lines(_box_wireframe(half_size), get_material("lines", gizmo), false)

	if node.feather_enabled:
		var feather_half_size := (half_size - node.feather_inset).max(Vector3.ZERO)
		gizmo.add_lines(_box_wireframe(feather_half_size), get_material("feather_lines", gizmo), false)

	if EditorInterface.get_selection().get_selected_nodes().has(node):
		gizmo.add_handles(
			PackedVector3Array([
				Vector3(half_size.x, 0, 0),
				Vector3(0, half_size.y, 0),
				Vector3(0, 0, half_size.z),
			]),
			get_material("handles", gizmo), []
		)

func _box_wireframe(half_size: Vector3) -> PackedVector3Array:
	var lines := PackedVector3Array()

	# in X
	lines.push_back(Vector3(-1, +1, -1) * half_size)
	lines.push_back(Vector3(+1, +1, -1) * half_size)
	lines.push_back(Vector3(-1, +1, +1) * half_size)
	lines.push_back(Vector3(+1, +1, +1) * half_size)
	lines.push_back(Vector3(-1, -1, -1) * half_size)
	lines.push_back(Vector3(+1, -1, -1) * half_size)
	lines.push_back(Vector3(-1, -1, +1) * half_size)
	lines.push_back(Vector3(+1, -1, +1) * half_size)

	# in Y
	lines.push_back(Vector3(+1, -1, -1) * half_size)
	lines.push_back(Vector3(+1, +1, -1) * half_size)
	lines.push_back(Vector3(-1, -1, -1) * half_size)
	lines.push_back(Vector3(-1, +1, -1) * half_size)
	lines.push_back(Vector3(+1, -1, +1) * half_size)
	lines.push_back(Vector3(+1, +1, +1) * half_size)
	lines.push_back(Vector3(-1, -1, +1) * half_size)
	lines.push_back(Vector3(-1, +1, +1) * half_size)

	# in Z
	lines.push_back(Vector3(+1, -1, -1) * half_size)
	lines.push_back(Vector3(+1, -1, +1) * half_size)
	lines.push_back(Vector3(+1, +1, -1) * half_size)
	lines.push_back(Vector3(+1, +1, +1) * half_size)
	lines.push_back(Vector3(-1, -1, -1) * half_size)
	lines.push_back(Vector3(-1, -1, +1) * half_size)
	lines.push_back(Vector3(-1, +1, -1) * half_size)
	lines.push_back(Vector3(-1, +1, +1) * half_size)

	return lines

# Returns the signed distance t such that (origin + t*axis) is the closest
# point on the axis line to the ray (ray_o + u*ray_d).
func _project_ray_onto_axis(origin: Vector3, axis: Vector3,
		ray_o: Vector3, ray_d: Vector3) -> float:
	var ray_to_axis_origin := origin - ray_o
	var axis_ray_cos    := axis.dot(ray_d)
	var ray_dir_sq_len  := ray_d.dot(ray_d)
	var axis_proj       := axis.dot(ray_to_axis_origin)
	var ray_proj        := ray_d.dot(ray_to_axis_origin)
	var parallelism_det := 1.0 - axis_ray_cos * axis_ray_cos / ray_dir_sq_len
	if abs(parallelism_det) < 1e-6:
		return 0.0
	return (axis_ray_cos * ray_proj / ray_dir_sq_len - axis_proj) / parallelism_det

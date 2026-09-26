//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc.
//
// Licensed under the MIT license (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// LICENSE
//
//===----------------------------------------------------------------------===//

#import "volume_camera_3d.h"
#import "node_loaders.h"
#import "scene_tree.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/viewport.hpp>

namespace gdrk {

void RealityVolumeCamera3D::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("get_size"), &RealityVolumeCamera3D::get_size);
	godot::ClassDB::bind_method(godot::D_METHOD("set_size", "size"), &RealityVolumeCamera3D::set_size);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::FLOAT, "size"), "set_size", "get_size");

	godot::ClassDB::bind_method(godot::D_METHOD("get_keep_aspect"), &RealityVolumeCamera3D::get_keep_aspect);
	godot::ClassDB::bind_method(godot::D_METHOD("set_keep_aspect", "keep_aspect"), &RealityVolumeCamera3D::set_keep_aspect);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::INT, "keep_aspect", godot::PROPERTY_HINT_ENUM, "Keep Width,Keep Height,Keep Depth"), "set_keep_aspect", "get_keep_aspect");

	godot::ClassDB::bind_method(godot::D_METHOD("get_preview_camera_enabled"), &RealityVolumeCamera3D::get_preview_camera_enabled);
	godot::ClassDB::bind_method(godot::D_METHOD("set_preview_camera_enabled"), &RealityVolumeCamera3D::set_preview_camera_enabled);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::BOOL, "preview_camera_enabled"),
			"set_preview_camera_enabled", "get_preview_camera_enabled");

	godot::ClassDB::bind_method(godot::D_METHOD("get_camera_projection"), &RealityVolumeCamera3D::get_camera_projection);
	godot::ClassDB::bind_method(godot::D_METHOD("get_camera_transform"), &RealityVolumeCamera3D::get_camera_transform);

	godot::ClassDB::bind_method(godot::D_METHOD("get_frustum"), &RealityVolumeCamera3D::get_frustum);

	godot::ClassDB::bind_method(godot::D_METHOD("is_position_behind", "world_point"), &RealityVolumeCamera3D::is_position_behind);
	godot::ClassDB::bind_method(godot::D_METHOD("is_position_in_frustum", "world_point"),
			&RealityVolumeCamera3D::is_position_in_frustum);
	godot::ClassDB::bind_method(godot::D_METHOD("make_current"), &RealityVolumeCamera3D::make_current);
	godot::ClassDB::bind_method(godot::D_METHOD("project_local_ray_normal", "screen_point"),
			&RealityVolumeCamera3D::project_local_ray_normal);
	godot::ClassDB::bind_method(godot::D_METHOD("project_position", "screen_point", "z_depth"),
			&RealityVolumeCamera3D::project_position);
	godot::ClassDB::bind_method(godot::D_METHOD("project_ray_normal", "screen_point"), &RealityVolumeCamera3D::project_ray_normal);
	godot::ClassDB::bind_method(godot::D_METHOD("project_ray_origin", "screen_point"), &RealityVolumeCamera3D::project_ray_origin);
	godot::ClassDB::bind_method(godot::D_METHOD("unproject_position", "world_point"), &RealityVolumeCamera3D::unproject_position);

	BIND_ENUM_CONSTANT(KEEP_WIDTH);
	BIND_ENUM_CONSTANT(KEEP_HEIGHT);
	BIND_ENUM_CONSTANT(KEEP_DEPTH);
}

void RealityVolumeCamera3D::set_preview_camera_enabled(bool p_preview_camera_enabled) {
	preview_camera_enabled = p_preview_camera_enabled;
#if TARGET_OS_OSX
	if (!generated_camera) {
		return;
	}

	if (preview_camera_enabled) {
		add_child(generated_camera);

		godot::Engine *engine = godot::Engine::get_singleton();
		if (engine->is_editor_hint()) {
			generated_camera->set_owner(get_tree()->get_edited_scene_root());
		}

		godot::Transform3D preview_camera_xform = godot::Transform3D();
		preview_camera_xform = preview_camera_xform.translated(
				godot::Vector3(0.0, 0.5 * size, size));
		preview_camera_xform = preview_camera_xform.looking_at(godot::Vector3());

		generated_camera->set_transform(preview_camera_xform);
		generated_camera->set_perspective(75.0, 0.05, 4000.0);
	} else {
		generated_camera->set_owner(nullptr);

		// Removing and re-adding the child triggers a scene outliner update.
		remove_child(generated_camera);
	}
#endif // TARGET_OS_OSX
}

godot::Transform3D RealityVolumeCamera3D::get_local_camera_transform() const {
	const godot::Vector3 physical_size = get_physical_size();
	const godot::Basis local_basis =
			godot::Basis(godot::Vector3(1.0, 0.0, 0.0),
					godot::Vector3(0.0, 1.0, 0.0),
					godot::Vector3(0.0, 0.0, 1.0));
	const godot::Vector3 local_origin = godot::Vector3(0.0, 0.0, 0.7 * physical_size.z);
	return godot::Transform3D(local_basis, local_origin);
}

godot::Transform3D RealityVolumeCamera3D::get_camera_transform() const {
	return get_global_transform() * get_local_camera_transform();
}

godot::Vector3 RealityVolumeCamera3D::get_physical_size() const {
	const godot::Vector3 viewport_size = _get_viewport_size();
	switch (keep_aspect) {
		case KEEP_WIDTH: {
			const float xy_aspect = viewport_size.y / viewport_size.x;
			const float xz_aspect = viewport_size.z / viewport_size.x;
			return godot::Vector3(size, size * xy_aspect, size * xz_aspect);
		}
		case KEEP_HEIGHT: {
			const float yz_aspect = viewport_size.z / viewport_size.y;
			const float yx_aspect = viewport_size.x / viewport_size.y;
			return godot::Vector3(size * yx_aspect, size, size * yz_aspect);
		}
		case KEEP_DEPTH: {
			const float zx_aspect = viewport_size.x / viewport_size.z;
			const float zy_aspect = viewport_size.y / viewport_size.z;
			return godot::Vector3(size * zx_aspect, size * zy_aspect, size);
		}
	}

	return godot::Vector3();
}

godot::TypedArray<godot::Plane> RealityVolumeCamera3D::get_frustum() const {
	const godot::Transform3D camera_transform = get_camera_transform();
	const godot::Vector3 physical_size = get_physical_size();

	godot::TypedArray<godot::Plane> res;
	res.push_back(camera_transform.xform(godot::Plane(godot::Vector3(0.0, 0.0, -1.0), 0.0))); // near
	res.push_back(camera_transform.xform(godot::Plane(godot::Vector3(0.0, 0.0, 1.0), physical_size.z))); // far
	res.push_back(camera_transform.xform(godot::Plane(godot::Vector3(1.0, 0.0, 0.0), -0.5 * physical_size.x))); // left
	res.push_back(camera_transform.xform(godot::Plane(godot::Vector3(0.0, -1.0, 0.0), 0.5 * physical_size.y))); // top
	res.push_back(camera_transform.xform(godot::Plane(godot::Vector3(-1.0, 0.0, 0.0), 0.5 * physical_size.x))); // right
	res.push_back(camera_transform.xform(godot::Plane(godot::Vector3(0.0, 1.0, 0.0), -0.5 * physical_size.y))); // bottom
	return res;
}

bool RealityVolumeCamera3D::is_position_behind(const godot::Vector3 &p_world_point) const {
	const godot::Transform3D camera_transform = get_camera_transform();
	const godot::Vector3 eyedir = -camera_transform.basis.get_column(2).normalized();
	return eyedir.dot(p_world_point - camera_transform.origin) < 0.0;
}

bool RealityVolumeCamera3D::is_position_in_frustum(const godot::Vector3 &p_world_point) const {
	for (const godot::Variant &plane_v : get_frustum()) {
		godot::Plane plane = plane_v;
		if (plane.is_point_over(p_world_point)) {
			return false;
		}
	}
	return true;
}

void RealityVolumeCamera3D::make_current() {
	if (generated_camera) {
		generated_camera->make_current();
	}
}

godot::Vector3 RealityVolumeCamera3D::project_position(const godot::Vector2 &p_screen_point, float p_z_depth) const {
	return project_ray_origin(p_screen_point) + project_ray_normal(p_screen_point) * p_z_depth;
}

godot::Vector3 RealityVolumeCamera3D::project_ray_normal(const godot::Vector2 &p_screen_point) const {
	const godot::Transform3D camera_transform = get_camera_transform();
	const godot::Vector3 res = camera_transform.basis.xform(project_local_ray_normal(p_screen_point));
	return res.normalized();
}

godot::Vector3 RealityVolumeCamera3D::project_ray_origin(const godot::Vector2 &p_screen_point) const {
	const godot::Vector3 physical_size = get_physical_size();
	const godot::Vector3 viewport_size = _get_viewport_size();
	const godot::Vector2 ndc_pos =
			godot::Vector2(2.0 * (p_screen_point.x / viewport_size.x) - 1.0,
					1.0 - 2.0 * (p_screen_point.y / viewport_size.y));

	const godot::Transform3D camera_transform = get_camera_transform();
	const godot::Vector3 local_origin =
			godot::Vector3(0.5 * ndc_pos.x * physical_size.x,
					0.5 * ndc_pos.y * physical_size.y,
					0.0);
	return camera_transform.xform(local_origin);
}

godot::Vector2 RealityVolumeCamera3D::unproject_position(const godot::Vector3 &p_world_point) const {
	const godot::Vector3 physical_size = get_physical_size();
	const godot::Vector3 viewport_size = _get_viewport_size();
	const godot::Vector2 viewport_size_2d = godot::Vector2(viewport_size.x, viewport_size.y);
	const godot::Vector3 camera_point = get_camera_transform().xform_inv(p_world_point);
	const godot::Vector3 ndc_pos = 2.0 * camera_point / physical_size;
	return godot::Vector2((ndc_pos.x * 0.5 + 0.5) * viewport_size_2d.x,
			(0.5 - ndc_pos.y * 0.5) * viewport_size_2d.y);
}

void RealityVolumeCamera3D::_ready() {
	generated_camera = godot::Object::cast_to<godot::Camera3D>(find_child("PreviewCamera"));
	if (!generated_camera) {
		generated_camera = memnew(godot::Camera3D);
		generated_camera->set_name("PreviewCamera");
		add_child(generated_camera);

		set_preview_camera_enabled(preview_camera_enabled);
	}

#if TARGET_OS_XR
	generated_camera->make_current();
#endif // TARGET_OS_XR
}

void RealityVolumeCamera3D::update_generated_camera_pose() {
#if TARGET_OS_XR
	const godot::Vector3 physical_size = get_physical_size();
	const float y = 1.0 * physical_size.y;
	const float z = -1.5 * physical_size.z;
	generated_camera->set_transform(
			godot::Transform3D().translated(godot::Vector3(0, y, z)));
#endif // TARGET_OS_XR
}

void RealityVolumeCamera3D::_process(double p_delta) {
	update_generated_camera_pose();
}

godot::Vector3 RealityVolumeCamera3D::_get_viewport_size() const {
	godot::Engine *engine = godot::Engine::get_singleton();
	godot::MainLoop *main_loop = engine->get_main_loop();
	RealitySceneTree *scene_tree = godot::Object::cast_to<RealitySceneTree>(main_loop);
	if (scene_tree && scene_tree->get_loader()) {
		if (auto *loader = scene_tree->get_loader_for_node(const_cast<RealityVolumeCamera3D *>(this))) {
			return loader->get_viewport_size();
		}
	}
	{
		const godot::Vector2 viewport_size = get_viewport()->get_visible_rect().size;
		return godot::Vector3(viewport_size.x, viewport_size.y, std::min(viewport_size.x, viewport_size.y));
	}
}

} // namespace gdrk

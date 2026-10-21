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

#ifndef VOLUME_CAMERA_H
#define VOLUME_CAMERA_H

#include <godot_cpp/classes/camera3d.hpp>

namespace gdrk {

// TODO: need icons for this
class RealityVolumeCamera3D : public godot::Node3D {
	GDCLASS(RealityVolumeCamera3D, Node3D);

protected:
	static void _bind_methods();

public:
	float get_size() const { return size; }
	void set_size(const float p_size) {
		size = p_size;
		update_gizmos();
	}

	enum KeepAspect {
		KEEP_WIDTH = godot::Camera3D::KEEP_WIDTH,
		KEEP_HEIGHT = godot::Camera3D::KEEP_HEIGHT,
		KEEP_DEPTH,
	};

	KeepAspect get_keep_aspect() const { return keep_aspect; }
	void set_keep_aspect(KeepAspect p_keep_aspect) { keep_aspect = p_keep_aspect; }

	// The physical size of the volume, in meters, when its Window opens as a
	// volume. Zero components of the minimum and maximum leave them unbounded.
	godot::Vector3 get_window_size() const { return window_size; }
	void set_window_size(const godot::Vector3 &p_size) { window_size = p_size; }
	godot::Vector3 get_window_min_size() const { return window_min_size; }
	void set_window_min_size(const godot::Vector3 &p_size) { window_min_size = p_size; }
	godot::Vector3 get_window_max_size() const { return window_max_size; }
	void set_window_max_size(const godot::Vector3 &p_size) { window_max_size = p_size; }

	// The size the volume has in the person's space, in meters, while open.
	godot::Vector3 get_window_measured_size() const { return window_measured_size; }
	void set_window_measured_size(const godot::Vector3 &p_size);

	bool get_preview_camera_enabled() const { return preview_camera_enabled; }
	void set_preview_camera_enabled(bool p_preview_camera_enabled);

	godot::Camera3D::ProjectionType get_camera_projection() const {
		return godot::Camera3D::PROJECTION_ORTHOGONAL;
	}

	godot::Transform3D get_local_camera_transform() const;
	godot::Transform3D get_camera_transform() const;
	godot::Vector3 get_physical_size() const;

	godot::TypedArray<godot::Plane> get_frustum() const;
	bool is_position_behind(const godot::Vector3 &p_world_point) const;
	bool is_position_in_frustum(const godot::Vector3 &p_world_point) const;

	void make_current();

	godot::Vector3 project_local_ray_normal(const godot::Vector2 &p_screen_point) const {
		return godot::Vector3(0, 0, -1.0);
	}

	godot::Vector3 project_position(const godot::Vector2 &p_screen_point, float p_z_depth) const;
	godot::Vector3 project_ray_normal(const godot::Vector2 &p_screen_point) const;
	godot::Vector3 project_ray_origin(const godot::Vector2 &p_screen_point) const;
	godot::Vector2 unproject_position(const godot::Vector3 &p_world_point) const;

	void _ready() override;
	void _process(double p_delta) override;

private:
	godot::Vector3 _get_viewport_size() const;
	void update_generated_camera_pose();
	void reset_preview_camera();

	float size = 5.0;
	KeepAspect keep_aspect = KEEP_DEPTH;
	godot::Vector3 window_size = godot::Vector3(1.0, 1.0, 1.0);
	godot::Vector3 window_min_size;
	godot::Vector3 window_max_size;
	godot::Vector3 window_measured_size;
	godot::Camera3D *generated_camera = nullptr;
	bool preview_camera_enabled = true;
};

} // namespace gdrk

VARIANT_ENUM_CAST(gdrk::RealityVolumeCamera3D::KeepAspect)

#endif // VOLUME_CAMERA_H

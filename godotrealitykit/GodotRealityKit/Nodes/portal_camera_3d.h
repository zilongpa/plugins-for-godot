//===----------------------------------------------------------------------===//
// Copyright © 2026 GodotRealityKit contributors.
//
// Licensed under the MIT license (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// LICENSE
//
//===----------------------------------------------------------------------===//

#ifndef PORTAL_CAMERA_3D_H
#define PORTAL_CAMERA_3D_H

#include <godot_cpp/classes/camera3d.hpp>

namespace gdrk {

// The camera of a Window that opens as a RealityKit portal window in the
// 2D Window presentation style. The portal looks into the Window's 3D world
// from this camera, as the Portal Window style does with the current camera.
class RealityPortalCamera3D : public godot::Camera3D {
	GDCLASS(RealityPortalCamera3D, Camera3D);

protected:
	static void _bind_methods();

public:
	// Meters of the portal per world unit; 0 shows an interactive slider.
	float get_world_scale() const { return world_scale; }
	void set_world_scale(float p_world_scale) { world_scale = p_world_scale; }

	// Planes in the portal window's space, as RealityPortalMeshInstance3D's:
	// meters from the window's center, with +Z toward the person.
	bool is_clipping_plane_enabled() const { return clipping_plane_enabled; }
	void set_clipping_plane_enabled(bool p_enabled) { clipping_plane_enabled = p_enabled; }
	godot::Vector3 get_clipping_plane_position() const { return clipping_plane_position; }
	void set_clipping_plane_position(const godot::Vector3 &p_position) { clipping_plane_position = p_position; }
	godot::Vector3 get_clipping_plane_normal() const { return clipping_plane_normal; }
	void set_clipping_plane_normal(const godot::Vector3 &p_normal) { clipping_plane_normal = p_normal; }

	bool is_crossing_plane_enabled() const { return crossing_plane_enabled; }
	void set_crossing_plane_enabled(bool p_enabled) { crossing_plane_enabled = p_enabled; }
	godot::Vector3 get_crossing_plane_position() const { return crossing_plane_position; }
	void set_crossing_plane_position(const godot::Vector3 &p_position) { crossing_plane_position = p_position; }
	godot::Vector3 get_crossing_plane_normal() const { return crossing_plane_normal; }
	void set_crossing_plane_normal(const godot::Vector3 &p_normal) { crossing_plane_normal = p_normal; }

private:
	float world_scale = 0.0;
	bool clipping_plane_enabled = false;
	godot::Vector3 clipping_plane_position;
	godot::Vector3 clipping_plane_normal = godot::Vector3(0.0, 0.0, 1.0);
	bool crossing_plane_enabled = false;
	godot::Vector3 crossing_plane_position;
	godot::Vector3 crossing_plane_normal = godot::Vector3(0.0, 0.0, 1.0);
};

} // namespace gdrk

#endif // PORTAL_CAMERA_3D_H

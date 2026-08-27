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

//  directional_light_shadow_3d.h
//  GodotRealityKit
#pragma once

#include <godot_cpp/classes/directional_light3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

namespace gdrk {

// Place this node as a child of a DirectionalLight3D to opt in to RealityKit's
// fixed orthographic shadow projection. When absent, the parent light uses
// automatic shadow projection (shadow map fit to the camera frustum).
class RealityKitDirectionalLightShadow3D : public godot::Node3D {
	GDCLASS(RealityKitDirectionalLightShadow3D, Node3D);

protected:
	static void _bind_methods();
	void _notification(int p_what);

private:
	void _apply_transform_to_parent();

public:
	godot::PackedStringArray _get_configuration_warnings() const override;

	float get_z_near() const { return z_near; }
	void set_z_near(float p_z_near) {
		z_near = p_z_near;
		update_gizmos();
	}

	float get_z_far() const { return z_far; }
	void set_z_far(float p_z_far) {
		z_far = p_z_far;
		update_gizmos();
	}

	float get_orthographic_scale() const { return orthographic_scale; }
	void set_orthographic_scale(float p_scale) {
		orthographic_scale = p_scale;
		update_gizmos();
	}

	float get_depth_bias() const { return depth_bias; }
	void set_depth_bias(float p_depth_bias) { depth_bias = p_depth_bias; }

private:
	float z_near = 0.001f;
	float z_far = 100.0f;
	float orthographic_scale = 10.0f;
	float depth_bias = 1.0f; // matches DirectionalLightComponent.Shadow default
};

} // namespace gdrk

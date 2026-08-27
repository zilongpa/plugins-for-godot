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

#pragma once

#include "../Util/culling.h"
#include "../resource_loaders.h"
#include "camera_loader.h"
#include "node_loader.h"

#include <godot_cpp/classes/spot_light3d.hpp>

namespace gdrk {

class SpotLightLoader : public NodeLoader<SpotLightLoader, godot::SpotLight3D> {
	NODE_LOADER(SpotLightLoader, NodeLoader, godot::SpotLight3D);

public:
	static constexpr bool manages_visibility_state = true;
	static constexpr bool manages_entity_registrations = true;

	void initialize(const CameraLoader *p_camera_loader) { camera_loader = p_camera_loader; }

	void update(const ResourceLoaderSet &p_resource_loaders);
	void update_visibility_state(const MeshLoader *p_meshes);
	void on_transform_changed(uint32_t p_idx, const godot::Transform3D &transform);

	void _reserve(uint32_t p_capacity) {
		Base::_reserve(p_capacity);
		dep_states.resize(p_capacity);
		culling_states.resize(p_capacity);
	}

	uint32_t add(godot::SpotLight3D *p_node) {
		const uint32_t idx = Base::add(p_node);
		dep_states[idx] = DependencyState();
		culling_states[idx] = CullingState();
		culling_states[idx].contributing = !is_non_contributing(p_node);
		if (culling_states[idx].contributing) {
			culling_system.register_entry(idx, 0);
		}
		return idx;
	}

	uint32_t remove(godot::SpotLight3D *p_node) {
		const uint32_t idx = Base::remove(p_node);
		if (culling_states[idx].contributing) {
			culling_system.unregister_entry(idx, 0);
		}
		return idx;
	}

	void set_world_scale(float value) { world_scale = value; }

private:
	struct DependencyState {
		uint32_t light_hash = 0;
		bool shadow_enabled = false;
	};

	struct CullingState {
		bool transform_updated = false;
		bool contributing = true;
		float range = 0.0f;
		float spot_angle = 0.0f;
	};

	bool is_non_contributing(godot::SpotLight3D *p_node) const;

	float world_scale = 1.0;
	const CameraLoader *camera_loader = nullptr;
	godot::LocalVector<DependencyState> dep_states;
	godot::LocalVector<CullingState> culling_states;
	CullingSystem culling_system;
};

} //namespace gdrk

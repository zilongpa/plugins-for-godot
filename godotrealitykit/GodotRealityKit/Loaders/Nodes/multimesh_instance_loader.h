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

#include "../resource_loaders.h"
#include "mesh_common.h"
#include "node_loader.h"

#include <godot_cpp/classes/multi_mesh_instance3d.hpp>

namespace gdrk {

class MultiMeshInstanceLoader : public NodeLoader<MultiMeshInstanceLoader, godot::MultiMeshInstance3D> {
	NODE_LOADER(MultiMeshInstanceLoader, NodeLoader, godot::MultiMeshInstance3D)
public:
	static constexpr bool manages_visibility_state = true;
	static constexpr bool manages_entity_registrations = true;

	void _reserve(uint32_t p_capacity) {
		Base::_reserve(p_capacity);
		dep_states.resize(p_capacity);
	}

	uint32_t add(godot::MultiMeshInstance3D *p_node) {
		const uint32_t idx = Base::add(p_node);
		dep_states[idx] = MultiMeshDependencyState();
		return idx;
	}

	void update_deps(ResourceLoaderSet &p_resource_loaders);

	void update_dirty_flags(const ResourceLoaderSet &p_resource_loaders);
	void update_deps_usage(ResourceLoaderSet &p_resource_loaders) const;
	void update_visibility_state(const MeshLoader *p_mesh);
	void update(const ResourceLoaderSet &p_resource_loaders);
	void _on_visibility_changed(uint32_t p_idx);

private:
	DependencyList mesh_deps;
	DependencyList multimesh_deps;
	DependencyList material_deps;

	godot::LocalVector<MultiMeshDependencyState> dep_states;
};

} //namespace gdrk

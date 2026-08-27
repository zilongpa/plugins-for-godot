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
#include "node_loader.h"

#include <godot_cpp/classes/grid_map.hpp>

namespace gdrk {

class MaterialLoader;

// TODO: add gridmap colliions?
class GridMapLoader : public NodeLoader<GridMapLoader, godot::GridMap> {
	NODE_LOADER(GridMapLoader, NodeLoader, godot::GridMap)
public:
	void _reserve(uint32_t p_capacity) {
		Base::_reserve(p_capacity);
		dep_states.resize(p_capacity);
	}

	uint32_t add(godot::GridMap *p_node) {
		const uint32_t idx = Base::add(p_node);
		dep_states[idx] = DependencyState();
		return idx;
	}

	void update_deps(ResourceLoaderSet &p_resource_loaders);

	void update_dirty_flags(const ResourceLoaderSet &p_resource_loaders);
	void update_deps_usage(ResourceLoaderSet &p_resource_loaders) const;

	void update(const ResourceLoaderSet &p_resource_loaders);

private:
	struct alignas(8) DependencyState {
		uint32_t mesh_hash = 0;
		uint32_t material_hash = 0;
	};

	DependencyList mesh_deps;
	DependencyList material_deps;

	godot::LocalVector<DependencyState> dep_states;
};

} //namespace gdrk

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

#include <godot_cpp/classes/world_environment.hpp>

namespace gdrk {

class WorldEnvironmentLoader : public NodeLoaderBase<WorldEnvironmentLoader, godot::WorldEnvironment> {
	NODE_LOADER(WorldEnvironmentLoader, NodeLoaderBase, godot::WorldEnvironment)

public:
	void _reserve(uint32_t p_capacity) {
		Base::_reserve(p_capacity);
		dep_states.resize(p_capacity);
	}

	uint32_t add(godot::WorldEnvironment *p_node) {
		const uint32_t idx = Base::add(p_node);
		dep_states[idx] = DependencyState();
		return idx;
	}

	uint32_t remove(godot::WorldEnvironment *p_node) {
		const uint32_t idx = Base::remove(p_node);
		entity.removeFromParent();
		return idx;
	}

	void update_deps(ResourceLoaderSet &p_resource_loaders);

	void update_dirty_flags(const ResourceLoaderSet &p_resource_loaders);
	void update_deps_usage(ResourceLoaderSet &p_resource_loaders) const;

	void update(const ResourceLoaderSet &p_resource_loaders);

private:
	struct DependencyState {
		uint32_t env_hash = 0;
	};

	DependencyList env_deps;
	DependencyList skybox_deps;
	GodotRealityKit::Entity entity = GodotRealityKit::Entity::initAndMaterialize(); // contains the IBL and the skybox
	godot::LocalVector<DependencyState> dep_states;
};

} //namespace gdrk

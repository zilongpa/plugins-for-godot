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

#import "image_based_light_3d.h"

namespace gdrk {

class ImageBasedLightLoader : public NodeLoader<ImageBasedLightLoader, RealityImageBasedLight3D> {
	NODE_LOADER(ImageBasedLightLoader, NodeLoader, RealityImageBasedLight3D)
public:
	void _reserve(uint32_t p_capacity) {
		Base::_reserve(p_capacity);
		states.resize(p_capacity);
	}

	uint32_t add(RealityImageBasedLight3D *p_node);
	uint32_t remove(RealityImageBasedLight3D *p_node);

	void update_deps(ResourceLoaderSet &p_resource_loaders);

	void update_dirty_flags(const ResourceLoaderSet &p_resource_loaders);
	void update_deps_usage(ResourceLoaderSet &p_resource_loaders) const;

	void update(const ResourceLoaderSet &p_resource_loaders);

private:
	struct IBLState {
		// the parent godot::Node is the root of the IBL
		uint64_t parent_node_id;
		uint32_t env_hash = 0;
	};

	DependencyList env_deps;
	godot::LocalVector<IBLState> states;
};

} //namespace gdrk

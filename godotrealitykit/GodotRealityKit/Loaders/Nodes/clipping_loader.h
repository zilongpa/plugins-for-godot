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

#ifndef CLIPPING_LOADER_H
#define CLIPPING_LOADER_H

#include "clipping_3d.h"
#include "node_loader.h"

namespace gdrk {

// RealityClipping3D is a marker node with no entity of its own (like RealityHoverEffectLoader),
// so it uses NodeLoaderBase, which gives no transform/parent tracking. Unlike
// RealityHoverEffectLoader, this loader must track both itself: a clip node can move without any
// property changing, and reparenting must free the effect against the *old* parent.
class RealityClippingLoader : public NodeLoaderBase<RealityClippingLoader, RealityClipping3D> {
	NODE_LOADER(RealityClippingLoader, NodeLoaderBase, RealityClipping3D)
public:
	void _reserve(uint32_t p_capacity) {
		Base::_reserve(p_capacity);
		node_state.resize(p_capacity);
	}

	uint32_t add(RealityClipping3D *p_node);
	uint32_t remove(RealityClipping3D *p_node);

	void update(const ResourceLoaderSet &p_resource_loaders);

private:
	struct State {
		uint32_t props_hash = 0;
		godot::Transform3D last_global_xform;
		uint64_t last_parent_id = 0;
	};

	godot::LocalVector<State> node_state;
};

} // namespace gdrk

#endif // CLIPPING_LOADER_H

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

#include "resource_loader.h"

namespace gdrk {

class ShapeLoader : public ResourceLoader<ShapeLoader> {
	GDCLASS(ShapeLoader, Object);

protected:
	static void _bind_methods() {}

public:
	void _reserve(uint32_t p_capacity) {
		ResourceLoader<ShapeLoader>::_reserve(p_capacity);
		shapes.resize(p_capacity);
	}

	// Note that unlike other resoure loaders, this one requires the resource object to be specified
	uint32_t find_or_add(godot::RID p_shape_rid, godot::Ref<godot::Shape3D> p_shape);

	void remove(uint32_t p_idx) {
		shape_rid_to_idx.remove(shapes[p_idx].shape_rid);
		godot::Shape3D *shape = shapes[p_idx].shape.ptr();
		if (shape) {
			disconnect_changed(shape, p_idx);
		}

		shapes[p_idx] = Shape();

		free_idx(p_idx);
	}

	bool update();

	GodotRealityKit::ShapeResource find_resource(godot::RID p_shape_rid) const {
		if (!p_shape_rid.is_valid()) {
			return GodotRealityKit::ShapeResource::init();
		}

		ERR_FAIL_COND_V(!shape_rid_to_idx.has(p_shape_rid), GodotRealityKit::ShapeResource::init());
		const uint32_t idx = shape_rid_to_idx.get(p_shape_rid);
		return shapes[idx].resource;
	}

private:
	struct Shape {
		godot::RID shape_rid;
		godot::Ref<godot::Shape3D> shape;
		GodotRealityKit::ShapeResource resource = GodotRealityKit::ShapeResource::init();
	};

	RID_Associated<uint32_t> shape_rid_to_idx;
	godot::LocalVector<Shape> shapes;
};

} //namespace gdrk

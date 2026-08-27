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

#include "clipping_loader.h"

#include "node_loaders.h"
#include "types.h"
#include "utility.h"

using namespace gdrk;

namespace {

auto get_clipping_3d_prop_hasher() {
	return make_object_property_hasher(
			make_object_property(&RealityClipping3D::get_size),
			make_object_property(&RealityClipping3D::get_feather_enabled),
			make_object_property(&RealityClipping3D::get_feather_inset),
			make_object_property(&RealityClipping3D::get_feather_falloff));
}

auto clipping_prop_hasher = get_clipping_3d_prop_hasher();

NodeLoaders::ClippingParams build_clipping_params(const RealityClipping3D *p_node) {
	const godot::Transform3D global_xform = p_node->get_global_transform();
	const godot::Quaternion rotation = global_xform.basis.get_rotation_quaternion();
	const godot::Vector3 translation = global_xform.origin;
	const godot::Vector3 scale = global_xform.basis.get_scale(); // signed, per-axis

	const godot::Transform3D rigid(godot::Basis(rotation), translation);
	const godot::Transform3D rigid_inv = rigid.affine_inverse();

	const godot::Vector3 half_size = p_node->get_size() * 0.5f;
	const godot::Vector3 corner0 = -half_size * scale;
	const godot::Vector3 corner1 = half_size * scale;
	const godot::Vector3 feather_inset = p_node->get_feather_inset() * scale.abs();

	NodeLoaders::ClippingParams params;
	params.clipper.rotation = to_vector4(rotation);
	params.clipper.translation = to_vector3(translation);
	params.anchor.rotation = to_vector4(rigid_inv.basis.get_rotation_quaternion());
	params.anchor.translation = to_vector3(rigid_inv.origin);
	params.bounds_min = to_vector3(corner0.min(corner1));
	params.bounds_max = to_vector3(corner0.max(corner1));
	params.feather_enabled = p_node->get_feather_enabled();
	params.feather_inset = to_vector3(feather_inset);
	params.falloff = (uint32_t)p_node->get_feather_falloff();
	return params;
}

} // namespace

namespace gdrk {

uint32_t RealityClippingLoader::add(RealityClipping3D *p_node) {
	const uint32_t idx = Base::add(p_node);

	godot::Node *parent = p_node->get_parent();
	const uint64_t parent_id = parent ? parent->get_instance_id() : 0;
	node_state[idx] = State{
		.props_hash = clipping_prop_hasher.hash(p_node),
		.last_global_xform = p_node->get_global_transform(),
		.last_parent_id = parent_id,
	};

	if (parent_id) {
		owner->clipping_create(parent_id, build_clipping_params(p_node));
	}

	return idx;
}

uint32_t RealityClippingLoader::remove(RealityClipping3D *p_node) {
	const uint32_t idx = Base::remove(p_node);

	if (node_state[idx].last_parent_id) {
		owner->clipping_free(node_state[idx].last_parent_id);
	}

	return idx;
}

void RealityClippingLoader::update(const ResourceLoaderSet &p_resource_loaders) {
	Base::update(p_resource_loaders);

	for_each_valid([&](uint32_t p_idx) {
		RealityClipping3D *node = nodes[p_idx];
		State &state = node_state[p_idx];

		godot::Node *parent = node->get_parent();
		const uint64_t parent_id = parent ? parent->get_instance_id() : 0;

		if (parent_id != state.last_parent_id) {
			// Reparented: move the effect from the old parent to the new one.
			if (state.last_parent_id) {
				owner->clipping_free(state.last_parent_id);
			}
			if (parent_id) {
				owner->clipping_create(parent_id, build_clipping_params(node));
			}
			state.last_parent_id = parent_id;
			state.props_hash = clipping_prop_hasher.hash(node);
			state.last_global_xform = node->get_global_transform();
			return;
		}

		const uint32_t props_hash = clipping_prop_hasher.hash(node);
		const godot::Transform3D global_xform = node->get_global_transform();
		if (parent_id && (props_hash != state.props_hash || global_xform != state.last_global_xform)) {
			owner->clipping_update(parent_id, build_clipping_params(node));
			state.props_hash = props_hash;
			state.last_global_xform = global_xform;
		}
	});
}

} // namespace gdrk

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

#define ENABLE_CULLING_DEBUG_VISUALIZATION 0

#include "spot_light_loader.h"
#include "bridge.h"
#include "light_tunning.h"
#include "node_loaders.h"
#include "signposts.h"
using namespace gdrk;

bool SpotLightLoader::is_non_contributing(godot::SpotLight3D *p_node) const {
	return p_node->is_negative() || LightTunning::get_light_intensity(*p_node) == 0.0f;
}

void SpotLightLoader::update_visibility_state(const MeshLoader *) {
	PROFILE_FUNC_SCOPE;

	// Reconcile contributing status. A light becomes non-contributing when it is
	// negative or has zero intensity; such lights are kept out of the culling
	// system entirely and never registered as entities until they contribute again.
	for_each_valid([&](uint32_t idx) {
		CullingState &state = culling_states[idx];
		const bool contributing = !is_non_contributing(nodes[idx]);
		if (contributing == state.contributing) {
			return;
		}

		if (contributing) {
			culling_system.register_entry(idx, 0);
			state.contributing = true;
			state.transform_updated = true;
		} else {
			if (is_visible(idx)) {
				unregister_entity(idx, nodes[idx]);
				mark_invisible(idx);
				mark_clean(idx);
			}
			culling_system.unregister_entry(idx, 0);
			state.contributing = false;
		}
	});

	std::optional<CullingSystem::Collector> collector = camera_loader->get_octree_collector();

	if (collector == std::nullopt) {
		for_each_valid([&](uint32_t idx) {
			if (!culling_states[idx].contributing || is_visible(idx)) {
				return;
			}
			register_entity(idx);
			mark_visible(idx);

			// Mark active right away so a later switch to a valid Collector lets the
			// next tick() properly signal entities that activated / deactivated.
			culling_system.mark_active(idx, 0);
		});

		return;
	}

	for_each_valid([&](uint32_t idx) {
		CullingState &state = culling_states[idx];
		if (!state.contributing) {
			return;
		}

		const float range = nodes[idx]->get_param(godot::Light3D::Param::PARAM_RANGE);
		const float spot_angle = nodes[idx]->get_param(godot::Light3D::Param::PARAM_SPOT_ANGLE);
		if (state.transform_updated || range != state.range || spot_angle != state.spot_angle) {
			state.range = range;
			state.spot_angle = spot_angle;
			state.transform_updated = false;

			const godot::AABB world_aabb = node_transform_states[idx].xform(nodes[idx]->get_aabb());
			culling_system.update_entry(idx, 0, world_aabb);
		}
	});

	culling_system.tick(collector.value(), [&](uint32_t idx, uint32_t) {
		mark_visible(idx);
		register_entity(idx);
		// Reset the dependency state so update() re-applies the light parameters
		// (and thus re-attaches the SpotLightComponent) to the freshly registered entity.
		dep_states[idx] = DependencyState();
		mark_dirty(idx); }, [&](uint32_t idx, uint32_t) {
		mark_invisible(idx);
#if ENABLE_CULLING_DEBUG_VISUALIZATION
		node_entities[idx].entity.clearDebugVisualizations();
#endif
		unregister_entity(idx, nodes[idx]);
		mark_clean(idx); });

#if ENABLE_CULLING_DEBUG_VISUALIZATION
	for_each_valid([&](uint32_t idx) {
		if (!is_visible(idx)) {
			return;
		}
		std::optional<godot::AABB> aabb_opt = culling_system.get_entry_aabb(idx, 0);
		if (!aabb_opt) {
			return;
		}
		const godot::AABB &aabb = *aabb_opt;
		node_entities[idx].entity.setDebugBoundingBox(owner->get_root_entity(),
				to_vector3(aabb.position), to_vector3(aabb.position + aabb.size), 0.6);
	});
#endif
}

void SpotLightLoader::on_transform_changed(uint32_t p_idx, const godot::Transform3D &transform) {
	culling_states[p_idx].transform_updated = true;
	if (is_visible(p_idx)) {
		Base::on_transform_changed(p_idx, transform);
	}
}

void SpotLightLoader::update(const ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	Base::update(p_resource_loaders);

	for_each_valid([&](uint32_t idx) {
		if (!is_visible(idx)) {
			return;
		}

		godot::SpotLight3D *node = nodes[idx];
		DependencyState &state = dep_states[idx];
		ERR_FAIL_NULL(node);

		if (node->has_shadow() != state.shadow_enabled) {
			state.shadow_enabled = node->has_shadow();
			node_entities[idx].entity.setSpotLightShadow(state.shadow_enabled);
		}

		float intensity = LightTunning::get_light_intensity(*node) * world_scale;
		float outerAngle = node->get_param(godot::Light3D::Param::PARAM_SPOT_ANGLE);
		float spot_attenuation = node->get_param(godot::Light3D::Param::PARAM_SPOT_ATTENUATION);
		float innerAngle = outerAngle - spot_attenuation;
		float attenuationRadius = node->get_param(godot::Light3D::Param::PARAM_RANGE) * world_scale;
		float attenuationFalloffExponent = node->get_param(godot::Light3D::Param::PARAM_ATTENUATION);
		godot::Color color = node->get_color();

		uint32_t hash = godot::hash_murmur3_one_float(intensity);
		hash = godot::hash_murmur3_one_float(innerAngle, hash);
		hash = godot::hash_murmur3_one_float(outerAngle, hash);
		hash = godot::hash_murmur3_one_float(attenuationRadius, hash);
		hash = godot::hash_murmur3_one_float(attenuationFalloffExponent, hash);
		hash = godot::hash_murmur3_one_32(color.to_rgba32(), hash);

		if (state.light_hash != hash) {
			node_entities[idx].entity.setSpotLight(gdrk::to_gdrk_color(color), intensity, 2 * innerAngle, 2 * outerAngle, attenuationRadius, attenuationFalloffExponent);
			state.light_hash = hash;
		}
	});
}

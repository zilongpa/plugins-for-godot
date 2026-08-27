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

#include "image_based_light_loader.h"

#import "constants.h"
#include "node_loaders.h"

using namespace gdrk;

uint32_t ImageBasedLightLoader::add(RealityImageBasedLight3D *p_node) {
	const uint32_t idx = Base::add(p_node);
	states[idx] = IBLState();

	if (godot::Node *parent = p_node->get_parent()) {
		const uint64_t parent_id = parent->get_instance_id();
		owner->ibl_create(parent_id, node_entities[idx].entity);
	}

	return idx;
}

uint32_t ImageBasedLightLoader::remove(RealityImageBasedLight3D *p_node) {
	const uint32_t idx = Base::remove(p_node);

	if (godot::Node *parent = p_node->get_parent()) {
		const uint64_t parent_id = parent->get_instance_id();
		owner->ibl_free(parent_id);
	}

	return idx;
}

void ImageBasedLightLoader::update_deps(
		ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	EnvironmentLoader *environments = std::get<EnvironmentLoader *>(p_resource_loaders);

	Base::update_deps(p_resource_loaders);

	ChangedDependencyListSet changed_env_deps = ChangedDependencyListSet(get_capacity());
	for_each_removed([&](uint32_t p_idx) {
		changed_env_deps.mark_changed(p_idx);
	});
	for_each_valid([&](uint32_t p_idx) {
		RealityImageBasedLight3D *node = nodes[p_idx];

		uint32_t env_hash_state = HASH_MURMUR3_SEED;
		if (godot::Environment *env = *node->get_environment()) {
			env_hash_state = godot::hash_murmur3_one_64(env->get_rid().get_id(), env_hash_state);
		}

		const uint32_t env_hash = godot::hash_fmix32(env_hash_state);
		if (states[p_idx].env_hash != env_hash) {
			changed_env_deps.mark_changed(p_idx);

			if (godot::Environment *env = *node->get_environment()) {
				const uint32_t env_idx = environments->find_or_add(env->get_rid(), env);
				changed_env_deps.add_changed_dep(env_idx, p_idx);
			}

			states[p_idx].env_hash = env_hash;
		}
	});

	env_deps.replace_changed(changed_env_deps, environments);
}

void ImageBasedLightLoader::update_dirty_flags(const ResourceLoaderSet &p_resource_loaders) {
	const EnvironmentLoader *environments = std::get<EnvironmentLoader *>(p_resource_loaders);

	dirty_idxs.merge(env_deps.changed());
	if (environments->has_dirty()) {
		for (Dependency env_dep : env_deps.get()) {
			if (environments->is_dirty(env_dep.src)) {
				dirty_idxs.insert(env_dep.dst);
			}
		}
	}
}

void ImageBasedLightLoader::update_deps_usage(ResourceLoaderSet &p_resource_loaders) const {
	EnvironmentLoader *environments = std::get<EnvironmentLoader *>(p_resource_loaders);

	for (Dependency dep : env_deps.get()) {
		if (is_valid(dep.dst)) {
			environments->mark_used_in_frame(dep.src);
		}
	}
}

void ImageBasedLightLoader::update(const ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	EnvironmentLoader *environments = std::get<EnvironmentLoader *>(p_resource_loaders);

	Base::update(p_resource_loaders);

	for_each_dirty([&](uint32_t idx) {
		RealityImageBasedLight3D *node = nodes[idx];
		ERR_FAIL_NULL(node);

		if (godot::Environment *env = *node->get_environment()) {
			float exponent = EnvironmentLoader::get_energy_exponent(env);
			GodotRealityKit::EnvironmentResource rkenv = environments->find_resource(env->get_rid());
			node_entities[idx].entity.setImageBasedLight(rkenv, constants::ibl_intensity_exponent + exponent);
		}

		// TODO: fix issue where transform update will break this
		godot::Quaternion rotation = godot::Basis(godot::Vector3(0, 1, 0), M_PI).get_quaternion();
		node_entities[idx].entity.setRotation(GodotRealityKit::Vector4::init(rotation.x, rotation.y, rotation.z, rotation.w));
	});
}

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

#include "world_environment_loader.h"
#include "constants.h"
#include "node_loaders.h"
#include "scene_tree.h"

#include <dispatch/dispatch.h>
#include <godot_cpp/classes/environment.hpp>
#include <godot_cpp/classes/panorama_sky_material.hpp>
#include <godot_cpp/classes/sky.hpp>

using namespace gdrk;

void WorldEnvironmentLoader::update_deps(
		ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	EnvironmentLoader *environments = std::get<EnvironmentLoader *>(p_resource_loaders);
	SkyboxLoader *skyboxes = std::get<SkyboxLoader *>(p_resource_loaders);

	Base::update_deps(p_resource_loaders);

	if (!get_scene_tree()->get_extension_settings().should_convert_world_environment()) {
		return;
	}

	ChangedDependencyListSet changed_env_deps = ChangedDependencyListSet(get_capacity());
	ChangedDependencyListSet changed_skybox_deps = ChangedDependencyListSet(get_capacity());
	for_each_removed([&](uint32_t idx) {
		changed_env_deps.mark_changed(idx);
		changed_skybox_deps.mark_changed(idx);
	});
	for_each_valid([&](uint32_t idx) {
		godot::WorldEnvironment *node = nodes[idx];

		uint32_t env_hash_state = HASH_MURMUR3_SEED;
		if (godot::Environment *env = *node->get_environment()) {
			env_hash_state = godot::hash_murmur3_one_64(env->get_rid().get_id(), env_hash_state);
		}

		uint32_t env_hash = godot::hash_fmix32(env_hash_state);
		if (dep_states[idx].env_hash != env_hash) {
			changed_env_deps.mark_changed(idx);
			changed_skybox_deps.mark_changed(idx);

			if (godot::Environment *env = *node->get_environment()) {
				const uint32_t env_idx = environments->find_or_add(env->get_rid(), env);
				changed_env_deps.add_changed_dep(env_idx, idx);
				const uint32_t skybox_idx = skyboxes->find_or_add(env->get_rid(), env);
				changed_skybox_deps.add_changed_dep(skybox_idx, idx);
			}

			dep_states[idx].env_hash = env_hash;
			dirty_idxs.insert(idx);
		}
	});

	env_deps.replace_changed(changed_env_deps, environments);
	skybox_deps.replace_changed(changed_skybox_deps, skyboxes);
}

void WorldEnvironmentLoader::update_dirty_flags(const ResourceLoaderSet &p_resource_loaders) {
	if (!get_scene_tree()->get_extension_settings().should_convert_world_environment()) {
		return;
	}

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

void WorldEnvironmentLoader::update_deps_usage(ResourceLoaderSet &p_resource_loaders) const {
	if (!get_scene_tree()->get_extension_settings().should_convert_world_environment()) {
		return;
	}

	EnvironmentLoader *environments = std::get<EnvironmentLoader *>(p_resource_loaders);
	SkyboxLoader *skyboxes = std::get<SkyboxLoader *>(p_resource_loaders);

	for (Dependency dep : env_deps.get()) {
		if (is_valid(dep.dst)) {
			environments->mark_used_in_frame(dep.src);
		}
	}
	for (Dependency dep : skybox_deps.get()) {
		if (is_valid(dep.dst)) {
			skyboxes->mark_used_in_frame(dep.src);
		}
	}
}

void WorldEnvironmentLoader::update(const ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	EnvironmentLoader *environments = std::get<EnvironmentLoader *>(p_resource_loaders);
	SkyboxLoader *skyboxes = std::get<SkyboxLoader *>(p_resource_loaders);

	Base::update(p_resource_loaders);

	if (!get_scene_tree()->get_extension_settings().should_convert_world_environment()) {
		return;
	}

	for_each_removed([&](uint32_t idx) {
		GodotRealityKit::Entity root = owner->get_root_entity();
		root.setImageBasedLightReceiver(swift::Optional<GodotRealityKit::Entity>::none());
		entity.setSkybox(GodotRealityKit::Skybox::init());
		entity.removeFromParent();
	});

	for_each_dirty([&](uint32_t idx) {
		godot::WorldEnvironment *node = nodes[idx];
		ERR_FAIL_NULL(node);

		// The root has the ImageBasedLightReceiver
		GodotRealityKit::Entity root = owner->get_root_entity();
		// The loader's Entity has the ImageBasedLightReceiver
		entity.setName("WorldEnvironment");

		if (godot::Environment *env = *node->get_environment()) {
			GodotRealityKit::EnvironmentResource rkenv = environments->find_resource(env->get_rid());
			float exponent = EnvironmentLoader::get_energy_exponent(env);
			entity.setImageBasedLight(rkenv, constants::ibl_intensity_exponent + exponent);
			entity.setSkybox(skyboxes->find_resource(env->get_rid()));
			entity.setParent(swift::Optional<GodotRealityKit::Entity>::some(root));
			root.setImageBasedLightReceiver(swift::Optional<GodotRealityKit::Entity>::some(entity));
		} else {
			entity.setImageBasedLight(GodotRealityKit::EnvironmentResource::init(), constants::ibl_intensity_exponent);
			entity.removeFromParent();
			entity.setSkybox(GodotRealityKit::Skybox::init());
			root.setImageBasedLightReceiver(swift::Optional<GodotRealityKit::Entity>::none());
		}
	});
}

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

#include "grid_map_loader.h"
#include "mesh_common.h"
#include "signposts.h"

#include "../resource_loaders.h"

using namespace gdrk;

void GridMapLoader::update_deps(
		ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	Base::update_deps(p_resource_loaders);

	ChangedDependencyListSet changed_mesh_deps = ChangedDependencyListSet(get_capacity());
	ChangedDependencyListSet changed_material_deps = ChangedDependencyListSet(get_capacity());
	for_each_removed([&](uint32_t idx) {
		changed_mesh_deps.mark_changed(idx);
		changed_material_deps.mark_changed(idx);
	});
	for_each_valid([&](uint32_t idx) {
		godot::GridMap *node = nodes[idx];
		godot::Array bake_meshes = node->get_bake_meshes();
		const uint32_t bake_mesh_count = static_cast<uint32_t>(bake_meshes.size() / 2);

		godot::TightLocalVector<godot::RID> instance_rids;
		instance_rids.reserve(bake_mesh_count);
		godot::TightLocalVector<godot::RID> mesh_rids;
		mesh_rids.reserve(bake_mesh_count);
		godot::TightLocalVector<godot::Mesh *> mesh_ptrs;
		mesh_ptrs.reserve(bake_mesh_count);
		for (uint32_t bake_mesh_idx = 0; bake_mesh_idx < bake_mesh_count; bake_mesh_idx++) {
			godot::Ref<godot::Mesh> mesh = bake_meshes[bake_mesh_idx * 2];
			instance_rids.push_back(node->get_bake_mesh_instance(bake_mesh_idx));
			mesh_rids.push_back(mesh->get_rid());
			mesh_ptrs.push_back(mesh.ptr());
		}

		uint32_t mesh_hash_state = HASH_MURMUR3_SEED;
		uint32_t material_hash_state = HASH_MURMUR3_SEED;
		for (godot::RID mesh_rid : mesh_rids) {
			accum_mesh_hash(mesh_rid, 0, mesh_hash_state, material_hash_state);
		}

		const uint32_t mesh_hash = godot::hash_fmix32(mesh_hash_state);
		const uint32_t material_hash = godot::hash_fmix32(material_hash_state);
		if (mesh_hash != dep_states[idx].mesh_hash) {
			for (uint32_t bake_mesh_idx = 0; bake_mesh_idx < bake_mesh_count; bake_mesh_idx++) {
				godot::Ref<godot::Mesh> mesh = bake_meshes[bake_mesh_idx * 2];
				add_mesh_deps(changed_mesh_deps, meshes, idx, mesh->get_rid(), 0, mesh.ptr());
			}

			dep_states[idx].mesh_hash = mesh_hash;
		}

		if (material_hash != dep_states[idx].material_hash) {
			for (uint32_t bake_mesh_idx = 0; bake_mesh_idx < bake_mesh_count; bake_mesh_idx++) {
				godot::Ref<godot::Mesh> mesh = bake_meshes[bake_mesh_idx * 2];
				add_material_deps(changed_material_deps, materials, idx, mesh->get_rid(), mesh.ptr());
			}

			dep_states[idx].material_hash = material_hash;
		}
	});

	mesh_deps.replace_changed(changed_mesh_deps, meshes);
	material_deps.replace_changed(changed_material_deps, materials);
}

void GridMapLoader::update_dirty_flags(const ResourceLoaderSet &p_resource_loaders) {
	const MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	const MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	dirty_idxs.merge(mesh_deps.changed());
	if (meshes->has_dirty()) {
		for (Dependency dep : mesh_deps.get()) {
			if (meshes->is_dirty(dep.src)) {
				dirty_idxs.insert(dep.dst);
			}
		}
	}

	dirty_idxs.merge(material_deps.changed());
	if (materials->has_dirty()) {
		for (Dependency dep : material_deps.get()) {
			if (materials->is_dirty(dep.src)) {
				dirty_idxs.insert(dep.dst);
			}
		}
	}
}

void GridMapLoader::update_deps_usage(ResourceLoaderSet &p_resource_loaders) const {
	MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	for (Dependency dep : mesh_deps.get()) {
		if (is_valid(dep.dst)) {
			meshes->mark_used_in_frame(dep.src);
		}
	}
	for (Dependency dep : material_deps.get()) {
		if (is_valid(dep.dst)) {
			materials->mark_used_in_frame(dep.src);
		}
	}
}

void GridMapLoader::update(const ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	Base::update(p_resource_loaders);

	for_each_dirty([&](uint32_t idx) {
		godot::GridMap *node = nodes[idx];
		ERR_FAIL_NULL(node);

		node_entities[idx].entity.clearChildren();
		godot::Array bake_meshes = node->get_bake_meshes();
		const uint32_t bake_mesh_count = static_cast<uint32_t>(bake_meshes.size() / 2);
		for (uint32_t bake_mesh_idx = 0; bake_mesh_idx < bake_mesh_count; bake_mesh_idx++) {
			godot::Ref<godot::Mesh> mesh = bake_meshes[bake_mesh_idx * 2];
			for (GodotRealityKit::Entity child : node_to_entities(mesh->get_rid(), meshes, materials)) {
				node_entities[idx].entity.addChild(child);
			}
		}
	});
}

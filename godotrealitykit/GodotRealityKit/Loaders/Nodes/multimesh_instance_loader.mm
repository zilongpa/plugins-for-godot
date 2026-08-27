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

#include "multimesh_instance_loader.h"
#include "../resource_loaders.h"
#include "signposts.h"

using namespace gdrk;

void MultiMeshInstanceLoader::update_deps(
		ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	MultiMeshLoader *multimeshes = std::get<MultiMeshLoader *>(p_resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	Base::update_deps(p_resource_loaders);

	ChangedDependencyListSet changed_mesh_deps = ChangedDependencyListSet(get_capacity());
	ChangedDependencyListSet changed_multimesh_deps = ChangedDependencyListSet(get_capacity());
	ChangedDependencyListSet changed_material_deps = ChangedDependencyListSet(get_capacity());

	for_each_removed([&](uint32_t idx) {
		changed_mesh_deps.mark_changed(idx);
		changed_multimesh_deps.mark_changed(idx);
		changed_material_deps.mark_changed(idx);
	});

	for_each_valid([&](uint32_t idx) {
		godot::MultiMeshInstance3D *node = nodes[idx];
		godot::Ref<godot::MultiMesh> multimesh = node->get_multimesh();
		if (!multimesh.is_valid()) {
			return;
		}
		godot::Ref<godot::Mesh> mesh = multimesh->get_mesh();

		add_dirty_multimesh_deps(changed_mesh_deps,
				changed_multimesh_deps,
				changed_material_deps,
				dep_states,
				meshes,
				multimeshes,
				materials,
				node,
				mesh.ptr(),
				idx);
	});

	mesh_deps.replace_changed(changed_mesh_deps, meshes);
	multimesh_deps.replace_changed(changed_multimesh_deps, multimeshes);
	material_deps.replace_changed(changed_material_deps, materials);
}

void MultiMeshInstanceLoader::update_visibility_state(const MeshLoader *p_meshes) {
	for_each_valid([&](uint32_t idx) {
		if (!is_enabled(idx)) {
			return;
		}
		godot::MultiMeshInstance3D *node = nodes[idx];
		godot::Ref<godot::MultiMesh> multimesh = node->get_multimesh();
		if (!multimesh.is_valid()) {
			return;
		}

		if (multimesh->get_visible_instance_count() == 0) {
			unregister_entity(idx, node);
			mark_invisible(idx);
		} else {
			if (!node_entities[idx].registered) {
				mark_dirty(idx);
				register_entity(idx);
				mark_visible(idx);
			}
		}
	});
}

void MultiMeshInstanceLoader::update_dirty_flags(const ResourceLoaderSet &p_resource_loaders) {
	const MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	const MultiMeshLoader *multimeshes = std::get<MultiMeshLoader *>(p_resource_loaders);
	const MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	dirty_idxs.merge(mesh_deps.changed());
	if (meshes->has_dirty()) {
		for (Dependency dep : mesh_deps.get()) {
			if (meshes->is_dirty(dep.src)) {
				dirty_idxs.insert(dep.dst);
			}
		}
	}

	dirty_idxs.merge(multimesh_deps.changed());
	if (multimeshes->has_dirty()) {
		for (Dependency dep : multimesh_deps.get()) {
			if (multimeshes->is_dirty(dep.src)) {
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

void MultiMeshInstanceLoader::update_deps_usage(ResourceLoaderSet &p_resource_loaders) const {
	MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	MultiMeshLoader *multimeshes = std::get<MultiMeshLoader *>(p_resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	for (Dependency dep : mesh_deps.get()) {
		if (is_valid(dep.dst)) {
			meshes->mark_used_in_frame(dep.src);
		}
	}
	for (Dependency dep : multimesh_deps.get()) {
		if (is_valid(dep.dst)) {
			multimeshes->mark_used_in_frame(dep.src);
		}
	}
	for (Dependency dep : material_deps.get()) {
		if (is_valid(dep.dst)) {
			materials->mark_used_in_frame(dep.src);
		}
	}
}

void MultiMeshInstanceLoader::_on_visibility_changed(uint32_t p_idx) {
	Base::_on_visibility_changed(p_idx);
	const bool now_enabled = node_entities[p_idx].enabled;

	if (now_enabled) {
		mark_dirty(p_idx);
	} else {
		if (is_registered(p_idx)) {
			node_entities[p_idx].entity.clearChildren();
		}
	}
}

void MultiMeshInstanceLoader::update(const ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	MultiMeshLoader *multimeshes = std::get<MultiMeshLoader *>(p_resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	Base::update(p_resource_loaders);

	for_each_dirty([&](uint32_t idx) {
		if (!is_registered(idx)) {
			return;
		}
		godot::MultiMeshInstance3D *node = nodes[idx];
		ERR_FAIL_NULL(node);

		godot::Ref<godot::MultiMesh> multimesh = node->get_multimesh();
		godot::Ref<godot::Mesh> mesh = multimesh->get_mesh();

		node_entities[idx].entity.clearChildren();
		for (GodotRealityKit::Entity child : node_to_entities(node, meshes, materials, multimeshes)) {
			node_entities[idx].entity.addChild(child);
		}
	});
}

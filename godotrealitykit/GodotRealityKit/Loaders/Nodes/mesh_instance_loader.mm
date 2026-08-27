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

#include "mesh_instance_loader.h"
#include "camera_loader.h"
#include "mesh_common.h"
#include "node_loaders.h"
#include "signposts.h"

#include "../resource_loaders.h"

#include <godot_cpp/classes/skin.hpp>

using namespace gdrk;

namespace {

auto get_portal_mesh_instance_3d_prop_hasher() {
	return make_object_property_hasher(
			make_object_property(&RealityPortalMeshInstance3D::get_flag,
					RealityPortalMeshInstance3D::FLAG_CLIPPING_PLANE_ENABLED),
			make_object_property(&RealityPortalMeshInstance3D::get_clipping_plane_position),
			make_object_property(&RealityPortalMeshInstance3D::get_clipping_plane_normal),
			make_object_property(&RealityPortalMeshInstance3D::get_flag,
					RealityPortalMeshInstance3D::FLAG_CROSSING_PLANE_ENABLED),
			make_object_property(&RealityPortalMeshInstance3D::get_crossing_plane_position),
			make_object_property(&RealityPortalMeshInstance3D::get_crossing_plane_normal));
}

} //namespace

#pragma mark - MeshInstanceLoaderBase

template <typename Derived, std::derived_from<godot::MeshInstance3D> MeshInstance>
void MeshInstanceLoaderBase<Derived, MeshInstance>::update_deps(
		ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	Base::update_deps(p_resource_loaders);

	ChangedDependencyListSet changed_mesh_deps = ChangedDependencyListSet(Self::get_capacity());
	ChangedDependencyListSet changed_material_deps = ChangedDependencyListSet(Self::get_capacity());

	Self::for_each_removed([&](uint32_t idx) {
		changed_mesh_deps.mark_changed(idx);
		changed_material_deps.mark_changed(idx);
	});

	Self::for_each_valid([&](uint32_t idx) {
		MeshInstance *node = Self::nodes[idx];

		uint32_t mesh_hash_state = HASH_MURMUR3_SEED;
		uint32_t material_hash_state = HASH_MURMUR3_SEED;
		if (Self::node_parent_skeleton_idxs.has(idx)) {
			accum_mesh_hash<true>(node, mesh_hash_state, material_hash_state);
		} else {
			accum_mesh_hash<false>(node, mesh_hash_state, material_hash_state);
		}

		const uint32_t mesh_hash = godot::hash_fmix32(mesh_hash_state);
		if (mesh_hash != dep_states[idx].mesh_hash) {
			const SmallLocalVector<uint32_t, 8> mesh_indices = add_mesh_deps(changed_mesh_deps, meshes, idx, node);
			if (mesh_indices.size()) {
				dep_states[idx].mesh_index = mesh_indices[0];
			}
			dep_states[idx].mesh_hash = mesh_hash;
		}

		const uint32_t material_hash = godot::hash_fmix32(material_hash_state);
		if (material_hash != dep_states[idx].material_hash) {
			add_material_deps(changed_material_deps, materials, idx, node);
			dep_states[idx].material_hash = material_hash;
		}

		const uint32_t blend_shape_count = node->get_blend_shape_count();
		const bool has_skeleton = Base::node_parent_skeleton_idxs.has(idx);
		godot::Ref<godot::SkinReference> skin_ref = has_skeleton ? node->get_skin_reference() : nullptr;
		const godot::RID mesh_rid = node->get_base();
		const uint64_t instance_id = (has_skeleton || blend_shape_count > 0) ? node->get_instance_id() : 0;

		// Skinned mesh: push the Skin so MeshLoader can resolve bind→bone mapping
		// and inverse bind poses when computing the per-bind transform matrices.
		if (skin_ref.is_valid()) {
			const uint32_t mesh_idx = meshes->find_or_add(mesh_rid, instance_id);
			meshes->set_skin(mesh_idx, node->get_skin().is_valid() ? node->get_skin() : skin_ref->get_skin());
		}

		if (blend_shape_count > 0) {
			SmallLocalVector<float, 8> weights;
			weights.resize(blend_shape_count);
			uint32_t blend_shape_hash_state = HASH_MURMUR3_SEED;
			for (uint32_t blend_shape_idx = 0; blend_shape_idx < blend_shape_count; blend_shape_idx++) {
				const float blend_shape_value = node->get_blend_shape_value(blend_shape_idx);
				weights[blend_shape_idx] = blend_shape_value;
				blend_shape_hash_state = godot::hash_murmur3_one_float(blend_shape_value, blend_shape_hash_state);
			}

			const uint32_t blend_shape_hash = godot::hash_fmix32(blend_shape_hash_state);
			if (dep_states[idx].blend_shape_hash != blend_shape_hash) {
				const uint32_t mesh_idx = meshes->find_or_add(mesh_rid, instance_id);
				meshes->set_blend_shape_weights(mesh_idx, VECTOR_SPAN(weights));
				dep_states[idx].blend_shape_hash = blend_shape_hash;
			}
		}
	});

	mesh_deps.replace_changed(changed_mesh_deps, meshes);
	material_deps.replace_changed(changed_material_deps, materials);
}

template <typename Derived, std::derived_from<godot::MeshInstance3D> MeshInstance>
void MeshInstanceLoaderBase<Derived, MeshInstance>::update_dirty_flags(const ResourceLoaderSet &p_resource_loaders) {
	const MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	const MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	Base::dirty_idxs.merge(mesh_deps.changed());
	if (meshes->has_dirty()) {
		for (Dependency dep : mesh_deps.get()) {
			if (meshes->is_dirty(dep.src)) {
				Self::dirty_idxs.insert(dep.dst);
			}
		}
	}

	Base::dirty_idxs.merge(material_deps.changed());
	if (materials->has_dirty()) {
		for (Dependency dep : material_deps.get()) {
			if (materials->is_dirty(dep.src)) {
				Self::dirty_idxs.insert(dep.dst);
			}
		}
	}
}

template <typename Derived, std::derived_from<godot::MeshInstance3D> MeshInstance>
void MeshInstanceLoaderBase<Derived, MeshInstance>::update_deps_usage(ResourceLoaderSet &p_resource_loaders) const {
	MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	for (Dependency dep : mesh_deps.get()) {
		if (this->is_valid(dep.dst)) {
			if constexpr (Derived::manages_visibility_state) {
				if (!static_cast<const Derived *>(this)->is_visible(dep.dst)) {
					continue;
				}
				if (!static_cast<const Derived *>(this)->is_enabled(dep.dst)) {
					continue;
				}
			}
			meshes->mark_used_in_frame(dep.src);
		}
	}
	for (Dependency dep : material_deps.get()) {
		if (this->is_valid(dep.dst)) {
			if constexpr (Derived::manages_visibility_state) {
				if (!static_cast<const Derived *>(this)->is_visible(dep.dst)) {
					continue;
				}
				if (!static_cast<const Derived *>(this)->is_enabled(dep.dst)) {
					continue;
				}
			}
			materials->mark_used_in_frame(dep.src);
		}
	}
}

template <typename Derived, std::derived_from<godot::MeshInstance3D> MeshInstance>
void MeshInstanceLoaderBase<Derived, MeshInstance>::update(const ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	MultiMeshLoader *multimeshes = std::get<MultiMeshLoader *>(p_resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	Base::update(p_resource_loaders);

	Self::for_each_dirty_and_visible([&](uint32_t idx) {
		if (!Base::is_enabled(idx)) {
			return;
		}
		MeshInstance *node = Self::nodes[idx];
		ERR_FAIL_NULL(node);

		Self::node_entities[idx].entity.clearChildren();
		for (GodotRealityKit::Entity child : node_to_entities(node, meshes, materials, multimeshes)) {
			Self::node_entities[idx].entity.addChild(child);
		}
	});
}

#pragma mark - MeshInstanceLoader

void MeshInstanceLoader::update_visibility_state(const MeshLoader *p_meshes) {
	PROFILE_FUNC_SCOPE;
#if ENABLE_CULLING_FRAME_STATS
	culling_system.reset_frame_stats();
#endif

	const CameraLoader::CullingInfo &culling_info = camera_loader->get_culling_info();
	std::optional<CullingSystem::Collector> collector = camera_loader->get_octree_collector();

	if (collector == std::nullopt) {
		for_each_valid([&](uint32_t idx) {
			if (!is_visible(idx)) {
				register_entity(idx);
				mark_visible(idx);

				// We mark them as active right away in the culling system to support the
				// camera changes. Once the we switch to a Collector that's valid, the next
				// culling_system.tick() call should properly signal entities that activated / deactivated
				culling_system.mark_active(idx, 0);
			}
		});

		return;
	}

	for_each_valid([&](uint32_t index) {
		CullingState &culling_state = culling_states[index];

		const bool recompute_aabb = is_dirty(index) || p_meshes->did_change_in_frame(dep_states[index].mesh_index);
		if (recompute_aabb) {
			godot::MeshInstance3D *node = nodes[index];
			const godot::RID mesh_rid = node->get_base();
			if (rendering_server()->mesh_get_surface_count(mesh_rid) == 0) {
				return;
			}

			const bool has_skeleton = Base::node_parent_skeleton_idxs.has(index);
			const bool has_blend_shapes = node->get_blend_shape_count() > 0;
			const uint64_t instance_id = (has_skeleton || has_blend_shapes) ? node->get_instance_id() : 0;

			const godot::AABB new_aabb = p_meshes->get_aabb(mesh_rid, instance_id);
			if (new_aabb != culling_state.local_aabb) {
				culling_state.local_aabb = new_aabb;
				culling_state.transform_updated = true;
			}
		}

		// Portal world content (descendants of a portal's target node) is rendered
		// through the portal mesh, not at the content's world position. Culling it
		// against its world AABB hides it whenever the user looks through the portal
		// but not at the content's actual world location — which is the common case
		// for small content like a sphere centered at the portal target. Substitute
		// an unbounded AABB so the culling check always passes for portal content,
		// and re-issue update_entry on transitions so we recover correct bounds when
		// a node leaves a portal world.
		const bool in_portal_world = node_effect_rids_set.get<PortalEffect>()[index].is_valid();
		if (in_portal_world != culling_state.was_in_portal_world) {
			culling_state.was_in_portal_world = in_portal_world;
			culling_state.transform_updated = true;
		}

		if (culling_state.transform_updated) {
			constexpr float k = 1e9f;
			static godot::AABB invalid_aabb = godot::AABB(godot::Vector3(-k, -k, -k), godot::Vector3(2 * k, 2 * k, 2 * k));
			godot::AABB world_aabb = invalid_aabb;
			if (!in_portal_world) {
				godot::Transform3D &transform = node_transform_states[index];
				if (transform.get_basis().get_scale().length() == 0) {
					world_aabb = invalid_aabb;
				} else {
					world_aabb = transform.xform(culling_state.local_aabb);
				}
			}
			culling_state.transform_updated = false;
			culling_system.update_entry(index, 0, world_aabb);
		}
	});

#if ENABLE_CULLING_DEBUG_VISUALIZATION
	camera_loader->get_current_entity().setDebugCullingSphere(owner->get_root_entity(), to_vector3(culling_info.position), culling_info.radius, 0.3);
#endif

	culling_system.tick(collector.value(), [&](uint32_t idx, uint32_t) {
		mark_visible(idx);
		register_entity(idx);
		mark_dirty(idx); }, [&](uint32_t idx, uint32_t) {
		mark_invisible(idx);
#if ENABLE_CULLING_DEBUG_VISUALIZATION
		node_entities[idx].entity.clearDebugVisualizations();
#endif
		unregister_entity(idx, nodes[idx]);

		// The entity has become invisible, keeping its state dirty will only allow
		// further updates that don't need to happen anymore.
		mark_clean(idx); });

#if ENABLE_CULLING_DEBUG_VISUALIZATION
	for_each_valid([&](uint32_t index) {
		if (!is_visible(index)) {
			return;
		}
		CullingState &culling_state = culling_states[index];
		godot::Transform3D &transform = node_transform_states[index];
		godot::AABB world_aabb = transform.xform(culling_state.local_aabb);
		node_entities[index].entity.setDebugBoundingBox(owner->get_root_entity(),
				to_vector3(world_aabb.position), to_vector3(world_aabb.position + world_aabb.size), 0.6);
	});
#endif

#if ENABLE_CULLING_FRAME_STATS
	std::cout << to_std_string(culling_system.get_frame_stats().to_string()) << std::endl;
	//std::cout << to_std_string(culling_system.entries_to_string()) << std::endl;
#endif
}

void MeshInstanceLoader::on_transform_changed(uint32_t p_idx, const godot::Transform3D &transform) {
	culling_states[p_idx].transform_updated = true;
	Base::on_transform_changed(p_idx, transform);
}

void MeshInstanceLoader::_on_visibility_changed(uint32_t p_idx) {
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

#pragma mark - RealityPortalMeshInstanceLoader

uint32_t RealityPortalMeshInstanceLoader::add(RealityPortalMeshInstance3D *p_node) {
	const uint32_t idx = Base::add(p_node);
	godot::Node *target_node = p_node->get_node_or_null(p_node->get_target_node());
	if (target_node) {
		const uint64_t target_id = target_node->get_instance_id();
		const godot::RID portal_rid = owner->portal_create(target_id);
		if (portal_rid.is_valid()) {
			node_portal_states[idx] = PortalState{
				.target_node_id = target_id,
				.properties_hash = 0
			};
			node_portal_rids[idx] = portal_rid;
		} else {
			node_portal_states[idx] = PortalState();
			node_portal_rids[idx] = godot::RID();
		}
	} else {
		node_portal_states[idx] = PortalState();
		node_portal_rids[idx] = godot::RID();
	}

	return idx;
}

uint32_t RealityPortalMeshInstanceLoader::remove(RealityPortalMeshInstance3D *p_node) {
	const uint32_t idx = Base::remove(p_node);
	if (const uint64_t target_id = node_portal_states[idx].target_node_id) {
		owner->portal_free(target_id);
	}
	return idx;
}

void RealityPortalMeshInstanceLoader::update(const ResourceLoaderSet &p_resource_loaders) {
	Base::update(p_resource_loaders);

	static auto prop_hasher = get_portal_mesh_instance_3d_prop_hasher();

	for_each_valid([&](uint32_t p_idx) {
		const RealityPortalMeshInstance3D *node = nodes[p_idx];
		godot::Node *target_node = node->get_node_or_null(node->get_target_node());
		const uint64_t target_node_id = target_node ? target_node->get_instance_id() : 0;
		bool target_changed = false;
		if (node_portal_states[p_idx].target_node_id != target_node_id) {
			const uint64_t prev_target_node_id = node_portal_states[p_idx].target_node_id;
			if (prev_target_node_id) {
				owner->portal_free(prev_target_node_id);
			}

			if (target_node_id) {
				node_portal_rids[p_idx] = owner->portal_create(target_node_id);
			} else {
				node_portal_rids[p_idx] = godot::RID();
			}

			node_portal_states[p_idx].target_node_id = target_node_id;
			target_changed = true;
		}

		const uint32_t properties_hash = prop_hasher.hash(node);
		if (target_changed || node_portal_states[p_idx].properties_hash != properties_hash) {
			const godot::RID portal_rid = node_portal_rids[p_idx];
			swift::Optional<GodotRealityKit::Entity> portal_world_opt =
					swift::Optional<GodotRealityKit::Entity>::none();
			if (portal_rid.is_valid()) {
				emplace_replace(&portal_world_opt,
						swift::Optional<GodotRealityKit::Entity>::some(owner->get_portal_world_entity(portal_rid)));
			}

			swift::Optional<GodotRealityKit::Vector4> clipping_plane_opt =
					swift::Optional<GodotRealityKit::Vector4>::none();
			if (node->get_flag(RealityPortalMeshInstance3D::FLAG_CLIPPING_PLANE_ENABLED)) {
				const godot::Vector3 clipping_plane_normal = node->get_clipping_plane_normal();
				const float clipping_plane_w = clipping_plane_normal.dot(node->get_clipping_plane_position());
				const GodotRealityKit::Vector4 clipping_plane = GodotRealityKit::Vector4::init(
						clipping_plane_normal.x, clipping_plane_normal.y, clipping_plane_normal.z, clipping_plane_w);
				emplace_replace(&clipping_plane_opt,
						swift::Optional<GodotRealityKit::Vector4>::some(clipping_plane));
			}

			swift::Optional<GodotRealityKit::Vector4> crossing_plane_opt =
					swift::Optional<GodotRealityKit::Vector4>::none();
			if (node->get_flag(RealityPortalMeshInstance3D::FLAG_CROSSING_PLANE_ENABLED)) {
				const godot::Vector3 crossing_plane_normal = node->get_crossing_plane_normal();
				const float crossing_plane_w = crossing_plane_normal.dot(node->get_crossing_plane_position());
				const GodotRealityKit::Vector4 crossing_plane = GodotRealityKit::Vector4::init(
						crossing_plane_normal.x, crossing_plane_normal.y, crossing_plane_normal.z, crossing_plane_w);
				emplace_replace(&crossing_plane_opt,
						swift::Optional<GodotRealityKit::Vector4>::some(crossing_plane));
			}

			node_entities[p_idx].entity.setPortal(
					portal_world_opt, clipping_plane_opt, crossing_plane_opt);

			node_portal_states[p_idx].properties_hash = properties_hash;
		}
	});
}

#pragma mark - RealityPortalCrossingLoader

uint32_t RealityPortalCrossingLoader::add(RealityPortalCrossing3D *p_node) {
	const uint32_t idx = Base::add(p_node);
	if (godot::Node *parent = p_node->get_parent()) {
		const uint64_t parent_id = parent->get_instance_id();
		owner->portal_crossing_create(parent_id);
	}
	return idx;
}

uint32_t RealityPortalCrossingLoader::remove(RealityPortalCrossing3D *p_node) {
	const uint32_t idx = Base::remove(p_node);

	if (godot::Node *parent = p_node->get_parent()) {
		const uint64_t parent_id = parent->get_instance_id();
		owner->portal_crossing_free(parent_id);
	}

	return idx;
}

template class gdrk::MeshInstanceLoaderBase<MeshInstanceLoader, godot::MeshInstance3D>;
template class gdrk::MeshInstanceLoaderBase<RealityPortalMeshInstanceLoader, RealityPortalMeshInstance3D>;

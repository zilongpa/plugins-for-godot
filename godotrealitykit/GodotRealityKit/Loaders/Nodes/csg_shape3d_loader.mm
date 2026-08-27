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

#include "csg_shape3d_loader.h"
#include "mesh_common.h"
#include "signposts.h"

#include "../resource_loaders.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/csg_box3d.hpp>
#include <godot_cpp/classes/csg_combiner3d.hpp>
#include <godot_cpp/classes/csg_cylinder3d.hpp>
#include <godot_cpp/classes/csg_mesh3d.hpp>
#include <godot_cpp/classes/csg_polygon3d.hpp>
#include <godot_cpp/classes/csg_sphere3d.hpp>
#include <godot_cpp/classes/csg_torus3d.hpp>
#include <godot_cpp/classes/mesh.hpp>

using namespace gdrk;

// Hashing all the subclasses:
// https://docs.godotengine.org/en/4.4/classes/class_csgprimitive3d.html#class-csgprimitive3d
auto get_csgbox3d_mesh_prop_hasher() {
	return make_object_property_hasher(make_object_property(&godot::CSGBox3D::get_size));
}

auto get_csgcylinder3d_mesh_prop_hasher() {
	return make_object_property_hasher(make_object_property(&godot::CSGCylinder3D::is_cone),
			make_object_property(&godot::CSGCylinder3D::get_height),
			make_object_property(&godot::CSGCylinder3D::get_radius),
			make_object_property(&godot::CSGCylinder3D::get_sides),
			make_object_property(&godot::CSGCylinder3D::get_smooth_faces));
}

auto get_csgmesh3d_mesh_prop_hasher() {
	return make_object_property_hasher(make_object_property(&godot::CSGMesh3D::get_mesh));
}

// TODO: implement the rest of this
auto get_csgpolygon3d_mesh_prop_hasher() {
	return make_object_property_hasher(make_object_property(&godot::CSGPolygon3D::get_polygon));
}

auto get_csgsphere3d_mesh_prop_hasher() {
	return make_object_property_hasher(make_object_property(&godot::CSGSphere3D::get_radial_segments),
			make_object_property(&godot::CSGSphere3D::get_radius),
			make_object_property(&godot::CSGSphere3D::get_rings),
			make_object_property(&godot::CSGSphere3D::get_smooth_faces));
}

auto get_csgtorus3d_mesh_prop_hasher() {
	return make_object_property_hasher(make_object_property(&godot::CSGTorus3D::get_inner_radius),
			make_object_property(&godot::CSGTorus3D::get_outer_radius),
			make_object_property(&godot::CSGTorus3D::get_ring_sides),
			make_object_property(&godot::CSGTorus3D::get_sides),
			make_object_property(&godot::CSGTorus3D::get_smooth_faces));
}

void CSGShape3DLoader::update_deps(
		ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);

	Base::update_deps(p_resource_loaders);

	static auto csgbox3d_prop_hasher = get_csgbox3d_mesh_prop_hasher();
	static auto csgcylinder3d_prop_hasher = get_csgcylinder3d_mesh_prop_hasher();
	static auto csgmesh3d_prop_hasher = get_csgmesh3d_mesh_prop_hasher();
	static auto csgpolygon3d_prop_hasher = get_csgpolygon3d_mesh_prop_hasher();
	static auto csgsphere3d_prop_hasher = get_csgsphere3d_mesh_prop_hasher();
	static auto csgtorus3d_prop_hasher = get_csgtorus3d_mesh_prop_hasher();

	ChangedDependencyListSet changed_mesh_deps = ChangedDependencyListSet(get_capacity());
	ChangedDependencyListSet changed_material_deps = ChangedDependencyListSet(get_capacity());
	for_each_removed([&](uint32_t idx) {
		changed_mesh_deps.mark_changed(idx);
	});
	for_each_valid([&](uint32_t idx) {
		godot::CSGShape3D *node = nodes[idx];
		godot::Mesh *mesh = node->bake_static_mesh().ptr();

		// This can be null when the Node is not a CSG root node
		if (!mesh) {
			changed_mesh_deps.mark_changed(idx);
			return;
		}

		uint32_t mesh_hash_state = HASH_MURMUR3_SEED;
		uint32_t material_hash_state = HASH_MURMUR3_SEED;
		if (godot::CSGBox3D *box = godot::Object::cast_to<godot::CSGBox3D>(node)) {
			mesh_hash_state = csgbox3d_prop_hasher.hash(box);
		} else if (godot::CSGCylinder3D *cylinder = godot::Object::cast_to<godot::CSGCylinder3D>(node)) {
			mesh_hash_state = csgcylinder3d_prop_hasher.hash(cylinder);
		} else if (godot::CSGMesh3D *mesh = godot::Object::cast_to<godot::CSGMesh3D>(node)) {
			mesh_hash_state = csgmesh3d_prop_hasher.hash(mesh);
		} else if (godot::CSGPolygon3D *polygon = godot::Object::cast_to<godot::CSGPolygon3D>(node)) {
			mesh_hash_state = csgpolygon3d_prop_hasher.hash(polygon);
		} else if (godot::CSGSphere3D *sphere = godot::Object::cast_to<godot::CSGSphere3D>(node)) {
			mesh_hash_state = csgsphere3d_prop_hasher.hash(sphere);
		} else if (godot::CSGTorus3D *torus = godot::Object::cast_to<godot::CSGTorus3D>(node)) {
			mesh_hash_state = csgtorus3d_prop_hasher.hash(torus);
		}

		accum_mesh_hash(node, mesh_hash_state, material_hash_state);

		const uint32_t mesh_hash = godot::hash_fmix32(mesh_hash_state);
		if (dep_states[idx].mesh_hash != mesh_hash) {
			for (uint32_t mesh_idx : add_mesh_deps(changed_mesh_deps, meshes, idx, node)) {
				meshes->mark_dirty(mesh_idx);
			}

			dep_states[idx].mesh_hash = mesh_hash;
		}

		const uint32_t material_hash = godot::hash_fmix32(material_hash_state);
		if (dep_states[idx].material_hash != material_hash) {
			add_material_deps(changed_material_deps, materials, idx, node);
			dep_states[idx].material_hash = material_hash;
		}
	});

	mesh_deps.replace_changed(changed_mesh_deps, meshes);
	material_deps.replace_changed(changed_material_deps, materials);
}

void CSGShape3DLoader::update_dirty_flags(const ResourceLoaderSet &p_resource_loaders) {
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

void CSGShape3DLoader::update_deps_usage(ResourceLoaderSet &p_resource_loaders) const {
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

void CSGShape3DLoader::update(const ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	MeshLoader *meshes = std::get<MeshLoader *>(p_resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(p_resource_loaders);
	MultiMeshLoader *multimeshes = std::get<MultiMeshLoader *>(p_resource_loaders);

	Base::update(p_resource_loaders);

	for_each_dirty([&](uint32_t idx) {
		godot::CSGShape3D *node = nodes[idx];
		ERR_FAIL_NULL(node);

		node_entities[idx].entity.clearChildren();
		for (GodotRealityKit::Entity child : node_to_entities(node, meshes, materials, multimeshes)) {
			node_entities[idx].entity.addChild(child);
		}
	});
}

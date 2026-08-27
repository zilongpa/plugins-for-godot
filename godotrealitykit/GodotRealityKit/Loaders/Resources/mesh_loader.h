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

#pragma once

#import <Metal/Metal.h>

#include "mesh_types.h"
#include "resource_loader.h"
#include "signposts.h"

#include <godot_cpp/classes/skin.hpp>

namespace gdrk {

class SkeletonLoader;

// Manages mesh surface resources and drives MeshEncoder each frame.
class MeshLoader : public ResourceLoader<MeshLoader> {
	GDCLASS(MeshLoader, Object);

protected:
	static void _bind_methods() {}

public:
	void initialize(SkeletonLoader *p_skeletons);

	void _reserve(uint32_t p_capacity) {
		ResourceLoader<MeshLoader>::_reserve(p_capacity);
		meshes.resize(p_capacity);
		mesh_rid_idxs.resize(p_capacity);
		mesh_needs_reencoding.resize(p_capacity);
		no_compact_idxs.resize(p_capacity);
		mesh_needs_bounds_update.resize(p_capacity);
		surface_info_dirty_idxs.resize(p_capacity);
	}

	uint32_t find_or_add(godot::RID p_mesh_rid,
			uint64_t p_instance_id,
			godot::Mesh *p_mesh = nullptr,
			godot::Skeleton3D *p_skeleton = nullptr);

	void remove(uint32_t p_idx);

	void set_blend_shape_weights(uint32_t p_idx, Span<const float> p_weights);
	void set_skin(uint32_t p_idx, const godot::Ref<godot::Skin> &p_skin);

	bool update(id<MTLCommandBuffer> p_command_buffer);

	void prepare_frame_changes();
	godot::AABB get_aabb(godot::RID p_mesh_rid, uint64_t p_instance_id) const;

	GodotRealityKit::MeshResource find_resource(godot::RID p_mesh_rid, uint64_t p_instance_id, uint32_t p_surface_idx) const;
	GodotRealityKit::MeshResource find_compacted_resource(godot::RID p_mesh_rid, uint64_t p_instance_id) const;

	bool is_compacted(godot::RID p_mesh_rid, uint64_t p_instance_id) const {
		const Mesh *mesh = find_mesh(p_mesh_rid, p_instance_id);
		return mesh && mesh->compacted_resource.isSome();
	}

	void set_no_compact(uint32_t p_idx) {
		no_compact_idxs.insert(p_idx);
	}

	void force_update(uint32_t p_idx) {
		mesh_needs_reencoding.insert(p_idx);
	}

	void reset_dirty() {
		ResourceLoader<MeshLoader>::reset_dirty();
	}

private:
	void mesh_changed(uint32_t p_mesh_rid_idx) {
		dirty_mesh_rid_idxs.insert(p_mesh_rid_idx);
	}

	uint32_t get_mesh_index(godot::RID p_mesh_rid,
			uint64_t p_instance_id) const;

	inline const Mesh *find_mesh(godot::RID p_mesh_rid,
			uint64_t p_instance_id) const {
		if (!p_mesh_rid.is_valid()) {
			return nullptr;
		}

		uint32_t idx = get_mesh_index(p_mesh_rid, p_instance_id);
		ERR_FAIL_COND_V(idx == UINT32_MAX, nullptr);
		return &meshes[idx];
	}

	Mesh::SurfaceInfo get_surface_info(const godot::Dictionary &p_surface, godot::RID p_mesh_rid) const;
	godot::AABB compute_local_aabb(Span<const Mesh::SurfaceInfo> p_surface_infos) const;
	bool surface_needs_new_resource(const Mesh::SurfaceInfo &p_cur, const Mesh::SurfaceInfo &p_new) const;
	bool bounds_changed(const godot::AABB &p_cur, const godot::AABB &p_new, float p_percent) const;

	struct alignas(16) MeshKey {
		godot::RID mesh_rid;
		uint64_t instance_id = 0;

		friend bool operator==(MeshKey, MeshKey) = default;
	};

	struct Hasher {
		static uint32_t hash(const MeshKey &v) {
			uint32_t res = HASH_MURMUR3_SEED;
			res = godot::hash_murmur3_one_64(v.mesh_rid.get_id(), res);
			res = godot::hash_murmur3_one_64(v.instance_id, res);
			return godot::hash_fmix32(res);
		}
	};

	MeshEncoder mesh_encoder;
	SkeletonLoader *skeletons = nullptr;

	RID_Associated<uint32_t> instance_rid_to_idx;
	godot::HashMap<MeshKey, uint32_t, Hasher> mesh_to_idx;
	godot::LocalVector<Mesh> meshes;
	godot::LocalVector<uint32_t> mesh_rid_idxs;
	LocalBitVector surface_info_dirty_idxs;
	LocalBitVector dirty_mesh_rid_idxs;
	LocalBitVector no_compact_idxs;

	LocalBitVector mesh_needs_bounds_update;
	LocalBitVector mesh_needs_reencoding;
};

} //namespace gdrk

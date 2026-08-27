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

#ifndef RESOURCE_LOADERS_H
#define RESOURCE_LOADERS_H

#import <Metal/Metal.h>

#import "program_cache.h"
#import "utility.h"

#import "../object_loader.h"

#undef check
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/classes/shape3d.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/skin_reference.hpp>
#include <godot_cpp/classes/texture2d.hpp>

#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/templates/hash_set.hpp>

#include <typeinfo>

namespace gdrk {

struct alignas(8) Dependency {
	uint32_t src;
	uint32_t dst;
};

// Utility class for representing a delta to a dependency list
class ChangedDependencyListSet {
public:
	explicit ChangedDependencyListSet(uint32_t p_set_size) {
		changed_dst_idxs.resize(p_set_size);
	}

	_FORCE_INLINE_ bool is_changed(uint32_t p_dst_idx) const {
		return changed_dst_idxs.has(p_dst_idx);
	}

	_FORCE_INLINE_ void mark_changed(uint32_t p_dst_idx) {
		changed_dst_idxs.insert(p_dst_idx);
	}

	_FORCE_INLINE_ void add_changed_dep(uint32_t p_src, uint32_t p_dst) {
		changed_deps.push_back(Dependency{
				.src = p_src,
				.dst = p_dst,
		});
	}

protected:
	friend class DependencyList;

	LocalBitVector changed_dst_idxs;
	godot::LocalVector<Dependency> changed_deps;
};

template <typename Derived>
class ResourceLoader;

// Utility class for a dependency list that can update depended resources' ref counts
// in their respective loaders when changed.
class DependencyList {
public:
	template <typename Derived>
	void replace_changed(const ChangedDependencyListSet &p_dirty_deps, ResourceLoader<Derived> *p_loader);

	_FORCE_INLINE_ Span<const Dependency> get() const {
		return VECTOR_SPAN(deps);
	}

	const LocalBitVector &changed() const { return changed_dst_idxs; }

protected:
	godot::LocalVector<Dependency> deps;
	LocalBitVector changed_dst_idxs;
};

// Base class for all resource loader types.
// Handles common resource management, including dirty tracking via a hook onto the resource's changed signal
// and reference count tracking with simple garbage collection.
// Derived classes are responsible for implementing at least the following methods:
// find_or_add:
//     Returns the index for the resource with the specified key; otherwise creates a new resource for that key.
//     These take the resource RID and an optional pointer to the resource object; if the latter is provided then change tracking
//     will happen automatically by hooking onto the object's changed signal, otherwise resources must be marked as dirty manually.
// remove:
//     Removes the resource at the specified index.
// update_deps (MaterialLoader only):
//     This updates the material loader's list of texture dependencies for each resource.
//     It also ensures that each material's texture dependencies are registered with the texture loader.
// update:
//     This iterates over all dirty resources to replace their RealityKit representation with a new resource.
//     In the case of MeshLoader and MultiMeshLoader, it also does in-place updates of the vertex buffers and transform buffers
//     without replacing the entire resource
// find_resource:
//     Returns the RealityKit resource for the specified key.
template <typename Derived>
class ResourceLoader : public ObjectLoader<Derived>, public godot::Object {
	TESTABLE();

	static constexpr uint32_t in_remove_queue_mask = 0x80000000;
	static constexpr uint32_t max_remove_queue_size = 4;

public:
	static inline uint32_t max_resources_per_update = 100;

	template <std::invocable<uint32_t> Fn>
	bool for_each_dirty_throttled(const Fn &fn) {
		const bool finished = ObjectLoader<Derived>::dirty_idxs.for_each_n([&](uint32_t idx) {
			if (!static_cast<const Derived *>(this)->is_valid(idx)) {
				return LocalBitVector::IterationResult::SKIPPED;
			}
			const LocalBitVector::IterationResult result = fn(idx);
			return result;
		},
				max_resources_per_update, next_dirty_idx);
		return finished;
	}

	void _reserve(uint32_t p_capacity) {
		ObjectLoader<Derived>::_reserve(p_capacity);
		resource_changed_callables.resize(p_capacity);
		used_in_frame.resize(p_capacity);
		changed_in_frame.resize(p_capacity);

		const uint32_t prev_capacity = resource_ref_counts.size();
		resource_ref_counts.resize(p_capacity);
		std::fill(resource_ref_counts.ptr() + prev_capacity, resource_ref_counts.ptr() + p_capacity, in_remove_queue_mask);
	}

	void remove_unreferenced() {
		const uint32_t capacity = ObjectLoader<Derived>::get_capacity();
		for (uint32_t idx = 0; idx < capacity; idx++) {
			const uint32_t ref_count = get_ref_count(idx);
			const bool tagged_for_removal = is_tagged_for_removal(idx);
			if (ref_count == 0 && !tagged_for_removal) {
				remove_queue.push_back(idx);
				tag_for_removal(idx);
			} else if (ref_count != 0 && tagged_for_removal) {
				tag_keep_active(idx);
			}
		}

		uint32_t kept_indices[max_remove_queue_size] = {};
		int32_t insert_index = int32_t(max_remove_queue_size) - 1;
		for (int32_t i = remove_queue.size() - 1; i >= 0; --i) {
			const uint32_t idx = remove_queue[i];
			const bool tagged_for_removal = is_tagged_for_removal(idx);

			if (!tagged_for_removal) {
				continue;
			}

			if (insert_index >= 0) {
				kept_indices[insert_index--] = idx;
				tag_already_removed(idx);
			} else {
				static_cast<Derived *>(this)->remove(idx);
			}
		}

		int32_t count = int32_t(max_remove_queue_size) - 1 - insert_index;
		memcpy((void *)remove_queue.ptr(), (void *)(kept_indices + insert_index + 1), sizeof(uint32_t) * count);
		remove_queue.resize(count);
		for (int i = 0; i < count; i++) {
			tag_for_removal(remove_queue[i]);
		}
	}

	_FORCE_INLINE_ void reference(uint32_t p_idx) {
		resource_ref_counts[p_idx]++;
	}

	_FORCE_INLINE_ void unreference(uint32_t p_idx) {
		resource_ref_counts[p_idx]--;
	}

	_FORCE_INLINE_ bool is_valid(uint32_t p_idx) const {
		return !is_tagged_for_removal(p_idx);
	}

	_FORCE_INLINE_ void mark_used_in_frame(uint32_t p_idx) {
		used_in_frame.insert(p_idx);
	}

	_FORCE_INLINE_ bool is_used_in_frame(uint32_t p_idx) const {
		return used_in_frame.has(p_idx);
	}

	_FORCE_INLINE_ bool did_change_in_frame(uint32_t p_idx) const {
		return changed_in_frame.has(p_idx);
	}

	void reset_dirty() {
		used_in_frame.for_each([&](uint32_t idx) {
			ObjectLoader<Derived>::mark_clean(idx);
		});
		used_in_frame.clear();
		changed_in_frame.clear();
		next_dirty_idx = 0;
	}

protected:
	void connect_changed(godot::Resource *p_resource, uint32_t p_idx) {
		godot::Callable changed_callable =
				callable_mp(static_cast<Derived *>(this), static_cast<void (Derived::*)(uint32_t)>(&Derived::changed)).bind(p_idx);
		p_resource->connect("changed", changed_callable);
		resource_changed_callables[p_idx] = std::move(changed_callable);
	}

	void disconnect_changed(godot::Resource *p_resource, uint32_t p_idx) {
		p_resource->disconnect("changed", resource_changed_callables[p_idx]);
	}

	void changed(uint32_t p_idx) {
		changed_in_frame.insert(p_idx);
		static_cast<Derived *>(this)->mark_dirty(p_idx);
	}

	_FORCE_INLINE_ void mark_changed_in_frame(uint32_t p_idx) {
		changed_in_frame.insert(p_idx);
	}

	uint32_t alloc_idx() {
		const uint32_t res = ObjectLoader<Derived>::alloc_idx();
		resource_ref_counts[res] = 0;
		used_in_frame.insert(res);
		return res;
	}

	void free_idx(uint32_t p_idx) {
		ObjectLoader<Derived>::free_idx(p_idx);
		resource_ref_counts[p_idx] = in_remove_queue_mask;
		// A resource freed while still dirty must not leak its dirty/changed/used
		// bits into a recycled slot now that reset_dirty() keeps unused dirty bits.
		ObjectLoader<Derived>::mark_clean(p_idx);
		changed_in_frame.remove(p_idx);
		used_in_frame.remove(p_idx);
	}

	_FORCE_INLINE_ void tag_for_removal(uint32_t p_idx) {
		resource_ref_counts[p_idx] |= in_remove_queue_mask;
	}

	_FORCE_INLINE_ void tag_already_removed(uint32_t p_idx) {
		resource_ref_counts[p_idx] &= ~in_remove_queue_mask;
	}

	_FORCE_INLINE_ void tag_keep_active(uint32_t p_idx) {
		resource_ref_counts[p_idx] &= ~in_remove_queue_mask;
	}

	_FORCE_INLINE_ uint32_t get_ref_count(uint32_t p_idx) const {
		return resource_ref_counts[p_idx] & ~in_remove_queue_mask;
	}

	_FORCE_INLINE_ bool is_tagged_for_removal(uint32_t p_idx) const {
		return resource_ref_counts[p_idx] & in_remove_queue_mask;
	}

protected:
	uint32_t next_dirty_idx = 0;

private:
	godot::LocalVector<godot::Callable> resource_changed_callables;
	godot::LocalVector<uint32_t> resource_ref_counts;
	godot::LocalVector<uint32_t> remove_queue;
	LocalBitVector used_in_frame;
	LocalBitVector changed_in_frame;
};

template <typename Derived>
void DependencyList::replace_changed(const ChangedDependencyListSet &p_dirty_deps, ResourceLoader<Derived> *p_loader) {
	changed_dst_idxs = p_dirty_deps.changed_dst_idxs;
	if (p_dirty_deps.changed_dst_idxs.count() > 0) {
		godot::LocalVector<Dependency> new_deps;
		new_deps.reserve(deps.size());
		for (const Dependency dep : deps) {
			if (!p_dirty_deps.changed_dst_idxs.has(dep.dst)) {
				new_deps.push_back(dep);
			} else {
				p_loader->unreference(dep.src);
			}
		}

		for (const Dependency dep : p_dirty_deps.changed_deps) {
			p_loader->reference(dep.src);
			new_deps.push_back(dep);
		}

		deps = std::move(new_deps);
	}
}

} // namespace gdrk

#endif // RESOURCE_LOADERS_H

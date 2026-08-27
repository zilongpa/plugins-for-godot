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

#include "octree.h"

#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/templates/hash_set.hpp>
#include <godot_cpp/variant/string.hpp>

#include "signposts.h"

#ifndef ENABLE_CULLING_FRAME_STATS
#define ENABLE_CULLING_FRAME_STATS 0
#endif

namespace gdrk {

class CullingSystem {
public:
	static constexpr int default_min_stable_frame_count = 10;

private:
	struct CullingEntry {
		godot::AABB aabb = godot::AABB(
				godot::Vector3(1e9f, 1e9f, 1e9f),
				godot::Vector3(0.0f, 0.0f, 0.0f));
		bool active = false;
		int stable_frame_count = 0;

		// External data used to reference the entry in the system
		uint32_t node_index;
		uint32_t subnode_index;
	};

public:
	using Collector = Octree<CullingEntry>::Collector;

#if ENABLE_CULLING_FRAME_STATS
	struct FrameStats {
		int registration_count = 0;
		int unregistration_count = 0;
		int unexpected_unregistration_count = 0;
		int update_count = 0;
		int update_not_found = 0;
		int update_same_count = 0;

		int static_count = 0;
		int static_active_count = 0;
		int static_activating_count = 0;
		int static_deactivating_count = 0;
		int static_to_dynamic = 0;

		int dynamic_count = 0;
		int dynamic_active_count = 0;
		int dynamic_activating_count = 0;
		int dynamic_deactivating_count = 0;
		int dynamic_to_static = 0;

		inline int total() const { return static_count + dynamic_count; }
		inline int active_count() const { return static_active_count + dynamic_active_count; }

		inline float active_percent() const {
			return total() > 0 ? 100.0f * float(active_count()) / float(total()) : 0.0f;
		}
		inline float static_percent() const {
			return total() > 0 ? 100.0f * float(static_count) / float(total()) : 0.0f;
		}
		inline float dynamic_percent() const {
			return total() > 0 ? 100.0f * float(dynamic_count) / float(total()) : 0.0f;
		}
		inline float static_active_percent() const {
			return static_count > 0 ? 100.0f * float(static_active_count) / float(static_count) : 0.0f;
		}
		inline float dynamic_active_percent() const {
			return dynamic_count > 0 ? 100.0f * float(dynamic_active_count) / float(dynamic_count) : 0.0f;
		}

		inline godot::String to_string() const {
			const int t = total();
			const int a = active_count();
			return godot::String("CullingSystem::FrameStats::Global  -- total: ") + godot::String::num_int64(t) +
					", active: " + godot::String::num_int64(a) + "/" + godot::String::num_int64(t) +
					" (" + godot::String::num(active_percent(), 1) + "%), registrations: " + godot::String::num_int64(registration_count) +
					", unregistrations: " + godot::String::num_int64(unregistration_count) +
					" (unexpected: " + godot::String::num_int64(unexpected_unregistration_count) + ")" +
					", updates: " + godot::String::num_int64(update_count) + ", update_not_found: " + godot::String::num_int64(update_not_found) +
					", update_same_count: " + godot::String::num_int64(update_same_count) + "\n" +
					"CullingSystem::FrameStats::Static  -- " +
					godot::String::num_int64(static_count) + "/" + godot::String::num_int64(t) +
					" (" + godot::String::num(static_percent(), 1) + "%), active: " +
					godot::String::num_int64(static_active_count) + "/" + godot::String::num_int64(static_count) +
					" (" + godot::String::num(static_active_percent(), 1) + "%), activating: " + godot::String::num_int64(static_activating_count) +
					", deactivating: " + godot::String::num_int64(static_deactivating_count) +
					", to_dynamic: " + godot::String::num_int64(static_to_dynamic) + "\n" +
					"CullingSystem::FrameStats::Dynamic -- " +
					godot::String::num_int64(dynamic_count) + "/" + godot::String::num_int64(t) +
					" (" + godot::String::num(dynamic_percent(), 1) + "%), active: " +
					godot::String::num_int64(dynamic_active_count) + "/" + godot::String::num_int64(dynamic_count) +
					" (" + godot::String::num(dynamic_active_percent(), 1) + "%), activating: " + godot::String::num_int64(dynamic_activating_count) +
					", deactivating: " + godot::String::num_int64(dynamic_deactivating_count) +
					", to_static: " + godot::String::num_int64(dynamic_to_static);
		}
	};

#define FRAME_STATS_INC(prop) frame_stats.prop += 1
#define FRAME_STATS_SET(prop, val) frame_stats.prop = val
#else
#define FRAME_STATS_INC(prop) ((void)0)
#define FRAME_STATS_SET(prop, val) ((void)0)
#endif

	static constexpr float epsilon = 0.001;

	inline bool almost_equal(const godot::AABB &a, const godot::AABB &b) {
		return (a.position - b.position).length() < epsilon &&
				(a.size - b.size).length() < epsilon;
	}

	CullingSystem() = default;

	inline ~CullingSystem() {
		for (const auto &kv : entries) {
			godot::memdelete(kv.value);
		}
	}

	CullingSystem(const CullingSystem &) = delete;
	CullingSystem &operator=(const CullingSystem &) = delete;

	inline static uint64_t get_id(uint32_t node_index, uint32_t subnode_index) {
		return (((uint64_t)node_index) << 32) | (uint64_t)subnode_index;
	}

	inline void mark_active(uint32_t p_node_index, uint32_t p_subnode_index) {
		uint64_t entry_id = CullingSystem::get_id(p_node_index, p_subnode_index);
		CullingEntry **found = entries.getptr(entry_id);
		if (!found) {
			return;
		}

		CullingEntry *entry = *found;
		entry->active = true;
		if (entry->stable_frame_count > min_stable_frame_count) {
			static_active_entries.insert(entry);
		}
	}

	inline void register_entry(uint32_t p_node_index, uint32_t p_subnode_index) {
		FRAME_STATS_INC(registration_count);
		uint64_t entry_id = CullingSystem::get_id(p_node_index, p_subnode_index);

		// If re-registering an already-stable entry it transitions back to dynamic.
		CullingEntry **found = entries.getptr(entry_id);
		if (found) {
			_remove_entry(entry_id, *found);
		}

		CullingEntry *entry = memnew(CullingEntry);
		entry->node_index = p_node_index;
		entry->subnode_index = p_subnode_index;

		entries[entry_id] = entry;
		dynamic_entries[entry_id] = entry;
	}

	inline void unregister_entry(uint32_t p_node_index, uint32_t p_subnode_index) {
		uint64_t entry_id = CullingSystem::get_id(p_node_index, p_subnode_index);
		CullingEntry **found = entries.getptr(entry_id);
		if (!found) {
			FRAME_STATS_INC(unexpected_unregistration_count);
			return;
		}

		FRAME_STATS_INC(unregistration_count);
		CullingEntry *entry = *found;
		_remove_entry(entry_id, entry);
	}

	inline void update_entry(uint32_t p_node_index, uint32_t p_subnode_index, godot::AABB p_aabb) {
		uint64_t entry_id = CullingSystem::get_id(p_node_index, p_subnode_index);
		CullingEntry **found = entries.getptr(entry_id);
		if (!found) {
			FRAME_STATS_INC(update_not_found);
			return;
		}

		CullingEntry *entry = *found;

		if (almost_equal(entry->aabb, p_aabb)) {
			FRAME_STATS_INC(update_same_count);
			return;
		}

		FRAME_STATS_INC(update_count);

		// Remove from current pool.
		if (entry->stable_frame_count > min_stable_frame_count) {
			octree.remove(entry);
			if (entry->active) {
				static_active_entries.erase(entry);
			}
			FRAME_STATS_INC(static_to_dynamic);
		} else {
			dynamic_entries.erase(entry_id);
		}

		entry->aabb = p_aabb;
		entry->stable_frame_count = 0;
		dynamic_entries[entry_id] = entry;
	}

	inline void reset_frame_stats() {
#if ENABLE_CULLING_FRAME_STATS
		frame_stats = FrameStats{};
#endif
	}

	// Runs one culling frame. Computes which entries moved into / out of
	// the camera volume and invokes the corresponding callback with the entry ids.
	// on_activate(node_index, subnode_index)   – called for each newly-visible entry.
	// on_deactivate(node_index, subnode_index) – called for each newly-hidden entry.
	template <std::invocable<uint32_t, uint32_t> ActivateFn, std::invocable<uint32_t, uint32_t> DeactivateFn>
	inline void tick(const Collector &p_collector,
			const ActivateFn &p_on_activate, const DeactivateFn &p_on_deactivate) {
		PROFILE_FUNC_SCOPE;
		// 1. Query octree for static entries within the camera volume.
		godot::HashSet<CullingEntry *> currently_active;
		octree.collect_all(p_collector, currently_active);

		// 2. Diff against previous static active set.
		godot::LocalVector<CullingEntry *> activating;
		godot::LocalVector<CullingEntry *> deactivating;

		for (CullingEntry *entry : static_active_entries) {
			if (!currently_active.has(entry)) {
				deactivating.push_back(entry);
			}
		}
		for (CullingEntry *entry : currently_active) {
			if (!static_active_entries.has(entry)) {
				activating.push_back(entry);
			}
		}

		FRAME_STATS_SET(static_activating_count, (int)activating.size());
		FRAME_STATS_SET(static_deactivating_count, (int)deactivating.size());

		static_active_entries = std::move(currently_active);

		// 3. Process dynamic entries (not yet in the octree).
		godot::LocalVector<uint64_t> to_promote;
		for (const auto &kv : dynamic_entries) {
			CullingEntry *entry = kv.value;
			const bool was_active = entry->active;
			const bool is_in_range = p_collector.is_object_inbound(*entry);

			if (is_in_range != was_active) {
				if (is_in_range) {
					FRAME_STATS_INC(dynamic_activating_count);
					activating.push_back(entry);
				} else {
					FRAME_STATS_INC(dynamic_deactivating_count);
					deactivating.push_back(entry);
				}
			}

			if (is_in_range) {
				FRAME_STATS_INC(dynamic_active_count);
			}

			entry->stable_frame_count++;
			if (entry->stable_frame_count > min_stable_frame_count) {
				FRAME_STATS_INC(dynamic_to_static);
				octree.insert(entry);
				if (is_in_range) {
					static_active_entries.insert(entry);
				}
				to_promote.push_back(kv.key);
			}
		}

		for (uint64_t id : to_promote) {
			dynamic_entries.erase(id);
		}

		// Snapshot counts after dynamic processing and promotion.
		FRAME_STATS_SET(static_count, octree.root_node->object_count);
		FRAME_STATS_SET(static_active_count, (int)static_active_entries.size());
		FRAME_STATS_SET(dynamic_count, (int)dynamic_entries.size());

		// 4. Fire callbacks.
		for (CullingEntry *entry : activating) {
			entry->active = true;
			p_on_activate(entry->node_index, entry->subnode_index);
		}
		for (CullingEntry *entry : deactivating) {
			entry->active = false;
			p_on_deactivate(entry->node_index, entry->subnode_index);
		}
	}

#if ENABLE_CULLING_FRAME_STATS
	inline const FrameStats &get_frame_stats() {
		return frame_stats;
	}
#endif

	inline bool is_static(uint32_t p_node_index, uint32_t p_subnode_index) const {
		uint64_t id = get_id(p_node_index, p_subnode_index);
		return entries.has(id) && !dynamic_entries.has(id);
	}

	inline bool is_dynamic(uint32_t p_node_index, uint32_t p_subnode_index) const {
		uint64_t id = get_id(p_node_index, p_subnode_index);
		return dynamic_entries.has(id);
	}

	inline std::optional<godot::AABB> get_entry_aabb(uint32_t p_node_index, uint32_t p_subnode_index) const {
		uint64_t entry_id = get_id(p_node_index, p_subnode_index);
		const CullingEntry *const *found = entries.getptr(entry_id);
		if (!found) {
			return std::nullopt;
		}
		return (*found)->aabb;
	}

	template <std::invocable<const CullingEntry &> Fn>
	inline void for_each_entry(const Fn &p_fn) const {
		for (const auto &kv : entries) {
			p_fn(*kv.value);
		}
	}

	template <std::invocable<const CullingEntry &> Fn>
	inline void for_each_dynamic_entry(const Fn &p_fn) const {
		for (const auto &kv : dynamic_entries) {
			p_fn(*kv.value);
		}
	}

	template <std::invocable<const CullingEntry &> Fn>
	inline void for_each_static_entry(const Fn &p_fn) {
		octree.traverse_all_objects([&](CullingEntry *e) {
			p_fn(*e);
			return Octree<CullingEntry>::CONTINUE;
		});
	}

	inline godot::String entries_to_string() {
		godot::String static_active_str;
		godot::String static_inactive_str;

		octree.traverse_all_objects([&](CullingEntry *e) {
			if (static_active_entries.has(e)) {
				static_active_str += _entry_to_string(e) + "\n";
			} else {
				static_inactive_str += _entry_to_string(e) + "\n";
			}
			return Octree<CullingEntry>::CONTINUE;
		});

		godot::String dynamic_active_str;
		godot::String dynamic_inactive_str;
		for (const auto &kv : dynamic_entries) {
			if (kv.value->active) {
				dynamic_active_str += _entry_to_string(kv.value) + "\n";
			} else {
				dynamic_inactive_str += _entry_to_string(kv.value) + "\n";
			}
		}

		return godot::String("CullingSystem::Entries::Static (active)\n") + static_active_str +
				"CullingSystem::Entries::Static (inactive)\n" + static_inactive_str +
				"CullingSystem::Entries::Dynamic (active)\n" + dynamic_active_str +
				"CullingSystem::Entries::Dynamic (inactive)\n" + dynamic_inactive_str;
	}

private:
	// Removes entry from all internal collections and frees it.
	// Used by both register_entry (re-registration) and unregister_entry
	// so that register_entry doesn't inflate unexpected_unregistration_count.
	inline void _remove_entry(uint64_t p_id, CullingEntry *entry) {
		if (entry->stable_frame_count > min_stable_frame_count) {
			octree.remove(entry);
			static_active_entries.erase(entry);
		} else {
			dynamic_entries.erase(p_id);
		}
		entries.erase(p_id);
		godot::memdelete(entry);
	}

	inline static godot::String _entry_to_string(const CullingEntry *e) {
		return "  [id=" + godot::String::num_uint64(CullingSystem::get_id(e->node_index, e->subnode_index)) +
				"] active=" + (e->active ? "true" : "false") +
				" aabb_pos=(" + godot::String::num(e->aabb.position.x, 2) +
				", " + godot::String::num(e->aabb.position.y, 2) +
				", " + godot::String::num(e->aabb.position.z, 2) +
				") aabb_size=(" + godot::String::num(e->aabb.size.x, 2) +
				", " + godot::String::num(e->aabb.size.y, 2) +
				", " + godot::String::num(e->aabb.size.z, 2) +
				") stable=" + godot::String::num_int64(e->stable_frame_count);
	}

	Octree<CullingEntry> octree;
	godot::HashMap<uint64_t, CullingEntry *> entries;
	godot::HashMap<uint64_t, CullingEntry *> dynamic_entries;
	godot::HashSet<CullingEntry *> static_active_entries;
	int min_stable_frame_count = default_min_stable_frame_count;

#if ENABLE_CULLING_FRAME_STATS
	FrameStats frame_stats;
#endif
};

} // namespace gdrk

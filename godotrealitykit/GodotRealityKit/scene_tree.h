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

#ifndef SCENE_TREE_H
#define SCENE_TREE_H

// clang-format off
#import "GodotRealityKit.h"
#import "GodotRealityKit-Swift.h"
// clang-format on

#undef check
#include "volume_window_options.h"

#include <godot_cpp/classes/input_event_from_window.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/xr_interface.hpp>
#include <godot_cpp/templates/local_vector.hpp>

#include <map>
#include <tuple>

class GDRKBridgeDelegate;

namespace gdrk {

class NodeLoaders;
class MeshLoader;
class MultiMeshLoader;
class MaterialLoader;
class TextureLoader;
class ShapeLoader;
class EnvironmentLoader;
class SkyboxLoader;
class SkeletonLoader;

using ResourceLoaderSet = std::tuple<
		MeshLoader *,
		MultiMeshLoader *,
		MaterialLoader *,
		TextureLoader *,
		ShapeLoader *,
		EnvironmentLoader *,
		SkyboxLoader *,
		SkeletonLoader *>;

struct ColliderInputEventParams {
	uint64_t collider_id;
	uint64_t camera_id;
	godot::Ref<godot::InputEventFromWindow> input_event;
	godot::Vector3 position;
	godot::Vector3 normal;
	int64_t shape_idx;
};

// High-level class responsible for loading the Godot scene into RealityKit
// The idea is to keep things reasonably efficient and data-oriented:
// Ex. First iterate over dirty textures and update them, then iterate over dirty materials
// (which potentially reference the new textures) and update them, then iterate over all the mesh instance nodes
// (which potentially reference the new materials) and update them, and so on.
// See update().
class SceneLoader {
public:
	~SceneLoader();
	std::shared_ptr<GDRKBridgeLifetime> lifetime = std::make_shared<GDRKBridgeLifetime>();
	uint64_t volume_id = 0;
	bool input_enabled = true;
	void stop_input();
	void cancel_press(int64_t p_id);
	bool ready_to_release();

	void initialize(godot::Node *p_node, GodotRealityKit::Entity p_entity);

	void update();

	godot::Node *get_root_node() { return godot::Object::cast_to<godot::Node>(godot::ObjectDB::get_instance(root_node_id)); }

	NodeLoaders *get_nodes() { return nodes; }
	ResourceLoaderSet &get_resource_loaders() { return resource_loaders; }
	MaterialLoader *get_materials();

	godot::Vector3 get_viewport_size() const { return viewport_size; }
	void set_viewport_size(const godot::Vector3 &p_viewport_size) {
		viewport_size = p_viewport_size;
	}

	void push_input_event(const ColliderInputEventParams &p_input_event) {
		input_event_queue.push_back(p_input_event);
	}

	void flush_input_events();

	void call_on_next_frame_completion(const std::function<void()> &p_on_next_frame_completion);

private:
	void dump_metal_capture(id<MTLCommandQueue> p_command_queue);
	void reset_dirty_resources();

	friend class ::GDRKBridgeDelegate;

	bool took_capture = true;
	uint32_t frame_count = 0;
	uint32_t current_command_buffer_idx = 0;
	godot::TightLocalVector<id<MTLCommandBuffer>> command_buffers;

	uint64_t root_node_id = 0;
	GodotRealityKit::Entity root_entity = GodotRealityKit::Entity::initAndMaterialize();

	ResourceLoaderSet resource_loaders = {};

	NodeLoaders *nodes = nullptr;

	godot::Vector3 viewport_size = godot::Vector3(1280.0, 1280.0, 1280.0);
	godot::LocalVector<ColliderInputEventParams> input_event_queue;

	static constexpr uint32_t max_active_presses = 2;
	mutable std::array<int64_t, max_active_presses> active_presses = { -1, -1 };
	mutable std::array<simd_float3, max_active_presses> last_active_press_position;
	mutable std::array<simd_float2, max_active_presses> last_active_press_location;
	mutable uint32_t next_active_press_idx = 0;
	std::array<ColliderInputEventParams, max_active_presses> active_press_targets = {};

	std::optional<std::function<void()>> on_next_frame_completion;
	bool loading_in_progress = false;
};

// This class overrides the Godot main loop.
// Its primary jobs are to overtake the Godot view hierarchy in _initialize()
// and to update the RealityKit scene after each _process() call.
class RealitySceneTree : public godot::SceneTree {
	GDCLASS(RealitySceneTree, SceneTree);

protected:
	static void _bind_methods();

public:
	~RealitySceneTree() override;

	void _initialize() override;

	bool _process(double p_time) override;
	bool _physics_process(double p_time) override;

	SceneLoader *get_loader() { return loader; }
	SceneLoader *get_loader_for_node(godot::Node *p_node);
	void update_loaders();
	enum VolumeWindowState { INVALID = -1,
		CLOSED,
		OPENING,
		OPEN,
		CLOSING,
		DESTROYING };
	int64_t open_volume_window(const godot::String &p_scene_path, const godot::String &p_title, const godot::Ref<RealityVolumeWindowOptions> &p_options = {});
	godot::Error reopen_volume_window(int64_t p_id);
	godot::Error close_volume_window(int64_t p_id);
	godot::Error destroy_volume_window(int64_t p_id);
	godot::PackedInt64Array get_volume_window_ids() const;
	bool has_volume_window(int64_t p_id) const;
	VolumeWindowState get_volume_window_state(int64_t p_id) const;
	godot::Node *get_volume_window_root(int64_t p_id) const;
	godot::Viewport *get_volume_window_viewport(int64_t p_id) const;
	int64_t get_volume_window_id(godot::Node *p_node) const;
	godot::String get_volume_window_title(int64_t p_id) const;
	godot::Error set_volume_window_title(int64_t p_id, const godot::String &p_title);
	godot::Ref<RealityVolumeWindowOptions> get_volume_window_options(int64_t p_id) const;
	godot::Error set_volume_window_options(int64_t p_id, const godot::Ref<RealityVolumeWindowOptions> &p_options);
	godot::Vector3 get_volume_window_size(int64_t p_id) const;
	void native_window_event(uint64_t p_id, uint64_t p_generation, int p_event, const godot::String &p_error);
	void native_window_size(uint64_t p_id, uint64_t p_generation, const godot::Vector3 &p_size);

	const GDRKBridgeDelegate::ExtensionSettings &get_extension_settings() const { return extension_settings; }

private:
	void clear_boot_image();

	void dump_reality_file_and_quit();

	GodotRealityKit::Bridge bridge = GodotRealityKit::Bridge::init();
	SceneLoader *loader = nullptr;
	struct VolumeWindow {
		SceneLoader *loader = nullptr;
		uint64_t root_id = 0, viewport_id = 0, generation = 0;
		VolumeWindowState state = CLOSED;
		bool desired_open = false, native_closed = true;
		godot::String title;
		godot::Ref<RealityVolumeWindowOptions> options;
		godot::Vector3 size;
	};
	std::map<int64_t, VolumeWindow> volumes;
	int64_t next_volume_id = 1;
	void set_window_state(int64_t p_id, VolumeWindowState p_state);
	void apply_window_options(int64_t p_id);
	void retire_windows();
	void volume_root_exiting(int64_t p_id);

	GDRKBridgeDelegate::ExtensionSettings extension_settings;
#if TARGET_OS_XR
	// The accessory-backed controller interface, when this scene tree registered one.
	godot::Ref<godot::XRInterface> controller_interface;
#endif
	bool enabled = true;
	bool paused_for_blocking_task = false;
};

} // namespace gdrk

VARIANT_ENUM_CAST(gdrk::RealitySceneTree::VolumeWindowState);

#endif // SCENE_TREE_H

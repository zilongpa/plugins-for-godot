//===----------------------------------------------------------------------===//
// Copyright © 2026 GodotRealityKit contributors.
//
// Licensed under the MIT license (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// LICENSE
//
//===----------------------------------------------------------------------===//

#ifndef WINDOW_HOSTS_H
#define WINDOW_HOSTS_H

#import "GodotRealityKit.h"
#import "GodotRealityKit-Swift.h"
#undef check

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/window.hpp>

#include <unordered_map>

namespace gdrk {

class SceneLoader;
class RealityPortalCamera3D;

// Godot Windows that hold a RealityVolumeCamera3D or a RealityPortalCamera3D
// open as RealityKit volumes or portal windows. The engine presents them like
// its other native windows; each has its own scene loader for the Window's
// subtree, while the rest of the scene stays with the main loader, if any.
class WindowHosts {
public:
	static WindowHosts *get_singleton();

	// Provides the content of these windows to the engine (visionOS only).
	void initialize();
	void finalize();

	// The camera that makes p_window a volume or a portal, outside nested Windows.
	static godot::Node3D *find_window_camera(godot::Node *p_window);
	static RealityPortalCamera3D *find_portal_camera(godot::Node *p_window);

	// The nearest Window around p_node, when it opens as a volume or portal.
	godot::Window *host_window_of(godot::Node *p_node);
	// The loader of the open volume or portal containing p_node, if any.
	SceneLoader *loader_for(godot::Node *p_node);
	SceneLoader *loader_of_window(uint64_t p_window_id) const;

	void node_added(godot::Node *p_node);
	void node_removed(godot::Node *p_node);
	void update();
	void flush_input_events();

	// Engine callbacks, on the main thread.
	bool provides_content(uint64_t p_window_id);
	bool is_volumetric(uint64_t p_window_id) const;
	godot::Vector3 volume_size(uint64_t p_window_id);
	void *make_content(uint64_t p_window_id);
	void window_closed(uint64_t p_window_id);

private:
	struct Host {
		godot::ObjectID window;
		SceneLoader *loader = nullptr;
		GDRKBridgeDelegate *delegate = nullptr;
		GodotRealityKit::Entity root = GodotRealityKit::Entity::init();
		bool volumetric = true;
	};

	Host *host_of_window(godot::Window *p_window);
	bool is_host_window(godot::Window *p_window);
	void unload_subtree(SceneLoader *p_loader, godot::Node *p_node);
	void load_subtree(SceneLoader *p_loader, godot::Node *p_node);

	std::unordered_map<uint64_t, Host> hosts; // By DisplayServer window ID.
	// Whether a Window holds a volume or portal camera, by instance ID.
	std::unordered_map<uint64_t, bool> host_window_cache;
	id provider = nil;
};

} // namespace gdrk

#endif // WINDOW_HOSTS_H

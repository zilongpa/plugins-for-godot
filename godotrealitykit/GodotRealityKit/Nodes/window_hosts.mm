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

#import "window_hosts.h"
#import "controller_xr_interface.h"
#import "node_loaders.h"
#import "portal_camera_3d.h"
#import "scene_tree.h"
#import "types.h"
#import "utility.h"
#import "volume_camera_3d.h"

#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/object.hpp>

#if TARGET_OS_XR

// The engine's window API, declared here because extensions do not link
// against the engine. Keep in sync with drivers/apple_embedded/godot_visionos_windows.h.

typedef NS_ENUM(NSInteger, GDTWindowStyle) {
	GDTWindowStylePlain = 0,
	GDTWindowStyleVolumetric,
};

typedef struct {
	double width;
	double height;
	double depth;
} GDTVolumeSize;

@protocol GDTWindowContentProvider <NSObject>
- (BOOL)providesContentForWindow:(uint64_t)windowID;
- (GDTWindowStyle)styleForWindow:(uint64_t)windowID;
- (GDTVolumeSize)volumeSizeForWindow:(uint64_t)windowID;
- (id)contentForWindow:(uint64_t)windowID;
- (void)windowDidClose:(uint64_t)windowID;
@end

@protocol GDTVisionOSWindowsClass
+ (void)setContentProvider:(id<GDTWindowContentProvider>)provider;
@end

@interface GDRKWindowContentProvider : NSObject <GDTWindowContentProvider>
@end

@implementation GDRKWindowContentProvider

- (BOOL)providesContentForWindow:(uint64_t)windowID {
	return gdrk::WindowHosts::get_singleton()->provides_content(windowID);
}

- (GDTWindowStyle)styleForWindow:(uint64_t)windowID {
	return gdrk::WindowHosts::get_singleton()->is_volumetric(windowID) ? GDTWindowStyleVolumetric : GDTWindowStylePlain;
}

- (GDTVolumeSize)volumeSizeForWindow:(uint64_t)windowID {
	const godot::Vector3 size = gdrk::WindowHosts::get_singleton()->volume_size(windowID);
	return GDTVolumeSize{ size.x, size.y, size.z };
}

- (id)contentForWindow:(uint64_t)windowID {
	void *content = gdrk::WindowHosts::get_singleton()->make_content(windowID);
	return content ? (__bridge_transfer id)content : nil;
}

- (void)windowDidClose:(uint64_t)windowID {
	gdrk::WindowHosts::get_singleton()->window_closed(windowID);
}

@end

#endif // TARGET_OS_XR

namespace gdrk {

WindowHosts *WindowHosts::get_singleton() {
	static WindowHosts singleton;
	return &singleton;
}

void WindowHosts::initialize() {
#if TARGET_OS_XR
	Class windows = NSClassFromString(@"GDTVisionOSWindows");
	if (![windows respondsToSelector:@selector(setContentProvider:)]) {
		WARN_PRINT("GodotRealityKit: this Godot build cannot open Windows as volumes or portals.");
		return;
	}
	provider = [GDRKWindowContentProvider new];
	[(Class<GDTVisionOSWindowsClass>)windows setContentProvider:provider];
#endif
}

void WindowHosts::finalize() {
#if TARGET_OS_XR
	if (provider) {
		[(Class<GDTVisionOSWindowsClass>)NSClassFromString(@"GDTVisionOSWindows") setContentProvider:nil];
		provider = nil;
	}
#endif
	for (auto &[window_id, host] : hosts) {
		godot::memdelete(host.loader);
		delete host.delegate;
	}
	hosts.clear();
}

// MARK: Ownership

static godot::Node3D *find_camera_in(godot::Node *p_node) {
	for (int i = 0; i < p_node->get_child_count(); i++) {
		godot::Node *child = p_node->get_child(i);
		if (godot::Object::cast_to<godot::Window>(child)) {
			continue;
		}
		if (godot::Object::cast_to<RealityVolumeCamera3D>(child) || godot::Object::cast_to<RealityPortalCamera3D>(child)) {
			return godot::Object::cast_to<godot::Node3D>(child);
		}
		if (godot::Node3D *camera = find_camera_in(child)) {
			return camera;
		}
	}
	return nullptr;
}

godot::Node3D *WindowHosts::find_window_camera(godot::Node *p_window) {
	return p_window ? find_camera_in(p_window) : nullptr;
}

RealityPortalCamera3D *WindowHosts::find_portal_camera(godot::Node *p_window) {
	return godot::Object::cast_to<RealityPortalCamera3D>(find_window_camera(p_window));
}

bool WindowHosts::is_host_window(godot::Window *p_window) {
	const uint64_t id = p_window->get_instance_id();
	auto cached = host_window_cache.find(id);
	if (cached != host_window_cache.end()) {
		return cached->second;
	}
	const bool is_host = find_window_camera(p_window) != nullptr;
	host_window_cache[id] = is_host;
	return is_host;
}

godot::Window *WindowHosts::host_window_of(godot::Node *p_node) {
	// The nearest Window decides; the root window is never a volume or portal.
	for (godot::Node *node = p_node; node; node = node->get_parent()) {
		if (godot::Window *window = godot::Object::cast_to<godot::Window>(node)) {
			if (!window->get_parent()) {
				return nullptr;
			}
			return is_host_window(window) ? window : nullptr;
		}
	}
	return nullptr;
}

WindowHosts::Host *WindowHosts::host_of_window(godot::Window *p_window) {
	if (!p_window) {
		return nullptr;
	}
	auto found = hosts.find(uint64_t(p_window->get_window_id()));
	if (found == hosts.end() || uint64_t(found->second.window) != p_window->get_instance_id()) {
		return nullptr;
	}
	return &found->second;
}

SceneLoader *WindowHosts::loader_for(godot::Node *p_node) {
	Host *host = host_of_window(host_window_of(p_node));
	return host ? host->loader : nullptr;
}

SceneLoader *WindowHosts::loader_of_window(uint64_t p_window_id) const {
	auto found = hosts.find(p_window_id);
	return found != hosts.end() ? found->second.loader : nullptr;
}

void WindowHosts::node_added(godot::Node *p_node) {
	if (godot::Object::cast_to<godot::Window>(p_node) || godot::Object::cast_to<RealityVolumeCamera3D>(p_node) ||
			godot::Object::cast_to<RealityPortalCamera3D>(p_node)) {
		host_window_cache.clear();
	}
	if (SceneLoader *loader = loader_for(p_node)) {
		loader->get_nodes()->node_added(p_node);
	}
}

void WindowHosts::node_removed(godot::Node *p_node) {
	if (SceneLoader *loader = loader_for(p_node)) {
		loader->get_nodes()->node_removed(p_node);
	}
	if (godot::Object::cast_to<godot::Window>(p_node) || godot::Object::cast_to<RealityVolumeCamera3D>(p_node) ||
			godot::Object::cast_to<RealityPortalCamera3D>(p_node)) {
		host_window_cache.clear();
	}
}

void WindowHosts::update() {
	for (auto &[window_id, host] : hosts) {
		host.loader->update();
	}
}

void WindowHosts::flush_input_events() {
	for (auto &[window_id, host] : hosts) {
		host.loader->flush_input_events();
	}
}

// The reverse of load_subtree(): the loader stops following the nodes, so
// their signals no longer reach it once it is freed.
void WindowHosts::unload_subtree(SceneLoader *p_loader, godot::Node *p_node) {
	for (int i = p_node->get_child_count() - 1; i >= 0; i--) {
		godot::Node *child = p_node->get_child(i);
		if (!godot::Object::cast_to<godot::Window>(child)) {
			unload_subtree(p_loader, child);
		}
	}
	p_loader->get_nodes()->node_removed(p_node);
}

void WindowHosts::load_subtree(SceneLoader *p_loader, godot::Node *p_node) {
	p_loader->get_nodes()->node_added(p_node);
	for (int i = 0; i < p_node->get_child_count(); i++) {
		godot::Node *child = p_node->get_child(i);
		if (!godot::Object::cast_to<godot::Window>(child)) {
			load_subtree(p_loader, child);
		}
	}
}

// MARK: Engine callbacks

bool WindowHosts::provides_content(uint64_t p_window_id) {
	godot::DisplayServer *display_server = godot::DisplayServer::get_singleton();
	godot::Window *window = godot::Object::cast_to<godot::Window>(
			godot::ObjectDB::get_instance(display_server->window_get_attached_instance_id(int32_t(p_window_id))));
	if (!window || !is_host_window(window)) {
		return false;
	}
	window_closed(p_window_id);

	Host host;
	host.window = godot::ObjectID(window->get_instance_id());
	host.volumetric = godot::Object::cast_to<RealityVolumeCamera3D>(find_window_camera(window)) != nullptr;
	host.root = GodotRealityKit::Entity::initAndMaterialize();
	host.loader = memnew(SceneLoader);
	host.loader->initialize(window, host.root);
	host.delegate = new GDRKBridgeDelegate(host.loader, p_window_id);
	load_subtree(host.loader, window);

	// RealityKit draws this Window's world instead of Godot.
	rendering_server()->viewport_set_update_mode(window->get_viewport_rid(), godot::RenderingServer::VIEWPORT_UPDATE_DISABLED);
	hosts.emplace(p_window_id, host);
	return true;
}

bool WindowHosts::is_volumetric(uint64_t p_window_id) const {
	auto found = hosts.find(p_window_id);
	return found != hosts.end() && found->second.volumetric;
}

godot::Vector3 WindowHosts::volume_size(uint64_t p_window_id) {
	auto found = hosts.find(p_window_id);
	godot::Window *window = found != hosts.end() ? godot::Object::cast_to<godot::Window>(godot::ObjectDB::get_instance(found->second.window)) : nullptr;
	RealityVolumeCamera3D *camera = godot::Object::cast_to<RealityVolumeCamera3D>(find_window_camera(window));
	return camera ? camera->get_window_size() : godot::Vector3();
}

void *WindowHosts::make_content(uint64_t p_window_id) {
#if TARGET_OS_XR
	auto found = hosts.find(p_window_id);
	if (found == hosts.end()) {
		return nullptr;
	}
	Host &host = found->second;
	godot::Window *window = godot::Object::cast_to<godot::Window>(godot::ObjectDB::get_instance(host.window));
	if (!window) {
		return nullptr;
	}
	if (!host.volumetric) {
		return GodotRealityKit::WindowContent::makePortal(host.root, *host.delegate);
	}
	RealityVolumeCamera3D *camera = godot::Object::cast_to<RealityVolumeCamera3D>(find_window_camera(window));
	const GDRKVolumeSize size = {
		.size = to_simd3(camera->get_window_size()),
		.minimum = to_simd3(camera->get_window_min_size()),
		.maximum = to_simd3(camera->get_window_max_size()),
		.resizable = !window->get_flag(godot::Window::FLAG_RESIZE_DISABLED),
	};
	return GodotRealityKit::WindowContent::makeVolume(host.root, *host.delegate, size);
#else
	return nullptr;
#endif
}

void WindowHosts::window_closed(uint64_t p_window_id) {
	auto found = hosts.find(p_window_id);
	if (found == hosts.end()) {
		return;
	}
	// A closed volume has no size; reopening it reports its size again.
	godot::Window *window = godot::Object::cast_to<godot::Window>(godot::ObjectDB::get_instance(found->second.window));
	if (RealityVolumeCamera3D *camera = godot::Object::cast_to<RealityVolumeCamera3D>(find_window_camera(window))) {
		camera->set_window_measured_size(godot::Vector3());
	}
	// The Window's nodes outlive its loader when the Window is only hidden.
	if (window) {
		unload_subtree(found->second.loader, window);
	}
	godot::memdelete(found->second.loader);
	delete found->second.delegate;
	hosts.erase(found);
#if TARGET_OS_XR
	if (RealityControllerXRInterface *controller_interface = RealityControllerXRInterface::get_active()) {
		controller_interface->forget_window(p_window_id);
	}
#endif
}

} // namespace gdrk

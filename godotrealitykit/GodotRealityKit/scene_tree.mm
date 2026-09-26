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

#import "scene_tree.h"

#import "controller_xr_interface.h"
#import "input_events.h"
#import "node_loaders.h"
#import "resource_loaders.h"

#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/packed_scene.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/sub_viewport.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/classes/xr_interface.hpp>
#include <godot_cpp/classes/xr_server.hpp>

namespace {

bool should_dump_reality_file() {
	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	const bool res = [defaults boolForKey:@"gdrk-reality-file-dump"];
	if (res) {
		printf("User default \"gdrk-reality-file-dump\" enabled: will dump first frame to a reality file and then quit\n");
	}

	return res;
}

bool should_dump_metal_capture() {
	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	const bool res = [defaults boolForKey:@"gdrk-metal-capture-dump"];
	if (res) {
		printf("User default \"gdrk-reality-file-dump\" enabled: will capture and dump first frame's Metal workload to a gpucapture file\n");
	}

	return res;
}

godot::CharString get_scene_name() {
	godot::ProjectSettings *project_settings = godot::ProjectSettings::get_singleton();
	godot::String main_scene_path = project_settings->get_setting("application/run/main_scene");
	godot::StringName main_scene_name = main_scene_path.trim_prefix("res://").trim_suffix("/scene.tscn");
	return main_scene_name.to_lower().to_snake_case().ascii();
}

} //namespace

namespace gdrk {

// High-level class responsible for loading the Godot scene into RealityKit
// The idea is to keep things reasonably efficient and data-oriented:
// Ex. First iterate over dirty textures and update them, then iterate over dirty materials
// (which potentially reference the new textures) and update them, then iterate over all the mesh instance nodes
// (which potentially reference the new materials) and update them, and so on.
// See update().
MaterialLoader *SceneLoader::get_materials() {
	return std::get<MaterialLoader *>(resource_loaders);
}

void SceneLoader::initialize(godot::Node *p_node, GodotRealityKit::Entity p_entity) {
	PROFILE_FUNC_SCOPE;

	root_node_id = p_node ? p_node->get_instance_id() : 0;
	lifetime->loader = this;
	root_entity = p_entity;

	const uint32_t frame_delay = rendering_device()->get_frame_delay();
	command_buffers.resize(frame_delay);

	std::get<TextureLoader *>(resource_loaders) = memnew(gdrk::TextureLoader);
	std::get<MaterialLoader *>(resource_loaders) = memnew(gdrk::MaterialLoader);
	std::get<MeshLoader *>(resource_loaders) = memnew(gdrk::MeshLoader);
	std::get<MultiMeshLoader *>(resource_loaders) = memnew(gdrk::MultiMeshLoader);
	std::get<ShapeLoader *>(resource_loaders) = memnew(gdrk::ShapeLoader);
	std::get<EnvironmentLoader *>(resource_loaders) = memnew(gdrk::EnvironmentLoader);
	std::get<SkyboxLoader *>(resource_loaders) = memnew(gdrk::SkyboxLoader);
	std::get<SkeletonLoader *>(resource_loaders) = memnew(gdrk::SkeletonLoader);

	nodes = memnew(gdrk::NodeLoaders);
	nodes->initialize(root_entity);

	std::get<MeshLoader *>(resource_loaders)->initialize(std::get<SkeletonLoader *>(resource_loaders));

	took_capture = !should_dump_metal_capture();

	static dispatch_once_t initialize_once;
	dispatch_once(&initialize_once, ^{ GodotRealityKit::Initialize(); });
}

bool SceneLoader::ready_to_release() {
	if (get_materials() && get_materials()->has_programs_loading()) {
		return false;
	}
	for (auto buffer : command_buffers) {
		if (!buffer) {
			continue;
		}
		if (buffer.status == MTLCommandBufferStatusNotEnqueued) {
			return false;
		}
		[buffer waitUntilCompleted];
	}
	return true;
}
void SceneLoader::stop_input() {
	input_enabled = false;
	for (int64_t press : active_presses) {
		if (press != -1) {
			cancel_press(press);
		}
	}
	flush_input_events();
	active_presses.fill(-1);
}
SceneLoader::~SceneLoader() {
	lifetime->loader = nullptr;
	ready_to_release();
	if (loading_in_progress) {
		GodotRealityKit::stopBlockingAsyncTask();
	}
	on_next_frame_completion.reset();
	if (nodes) {
		godot::memdelete(nodes);
	}

	for_each_loader(resource_loaders, [](auto *&loader) {
		if (loader) {
			godot::memdelete(loader);
		}
	});
}

void SceneLoader::update() {
	PROFILE_FUNC_SCOPE;

	id<MTLCommandBuffer> prev_buffer = command_buffers[current_command_buffer_idx];
	if (prev_buffer) {
		const MTLCommandBufferStatus status = [prev_buffer status];
		if (status == MTLCommandBufferStatusNotEnqueued) {
			return;
		}
		[prev_buffer waitUntilCompleted];
	}

	TextureLoader *textures = std::get<TextureLoader *>(resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(resource_loaders);
	MeshLoader *meshes = std::get<MeshLoader *>(resource_loaders);
	MultiMeshLoader *multimeshes = std::get<MultiMeshLoader *>(resource_loaders);
	ShapeLoader *shapes = std::get<ShapeLoader *>(resource_loaders);
	EnvironmentLoader *environments = std::get<EnvironmentLoader *>(resource_loaders);
	SkyboxLoader *skyboxes = std::get<SkyboxLoader *>(resource_loaders);
	SkeletonLoader *skeletons = std::get<SkeletonLoader *>(resource_loaders);

	frame_count++;
	nodes->update_deps(resource_loaders);
	materials->update_deps(textures);

	if (materials->has_programs_loading()) {
		return;
	}

	textures->remove_unreferenced();
	meshes->remove_unreferenced();
	skeletons->remove_unreferenced();
	multimeshes->remove_unreferenced();
	shapes->remove_unreferenced();
	environments->remove_unreferenced();
	skyboxes->remove_unreferenced();

	id<MTLCommandQueue> command_queue = gdrk::get_metal_command_queue(rendering_device());

	if (!took_capture) {
		dump_metal_capture(command_queue);
		took_capture = true;
	}

	if (!loading_in_progress) {
		meshes->prepare_frame_changes();
		nodes->update_transforms();
		nodes->update_dirty_flags(resource_loaders);
		nodes->update_visibility_states(resource_loaders);
		nodes->update_deps_usage(resource_loaders);
	}

	id<MTLCommandBuffer> command_buffer = [command_queue commandBuffer];

	bool finished = true;
	finished &= materials->update(command_buffer, textures);
	finished &= textures->update(command_buffer);
	finished &= meshes->update(command_buffer);
	finished &= multimeshes->update();
	finished &= shapes->update();
	finished &= environments->update();
	finished &= skyboxes->update(command_buffer);

	[command_buffer commit];
	command_buffers[current_command_buffer_idx] = command_buffer;
	current_command_buffer_idx = (current_command_buffer_idx + 1) % command_buffers.size();

	MTLCaptureManager *capture_manager = [MTLCaptureManager sharedCaptureManager];
	if ([capture_manager isCapturing]) {
		[capture_manager stopCapture];
	}

	if (!finished && !loading_in_progress) {
		loading_in_progress = true;
		GodotRealityKit::startBlockingAsyncTask();
	} else if (finished && loading_in_progress) {
		loading_in_progress = false;
		GodotRealityKit::stopBlockingAsyncTask();
		reset_dirty_resources();
		return;
	}

	if (!finished) {
		return;
	}

	nodes->update(resource_loaders);

	reset_dirty_resources();
	nodes->reset_dirty();

	if (!get_scene_tree()->is_paused() && on_next_frame_completion != std::nullopt) {
		[command_buffer waitUntilCompleted];
		(*on_next_frame_completion)();
		on_next_frame_completion = std::nullopt;
	}

#if !TARGET_OS_OSX
	if (GodotRealityKit::hasOriginalScene() && GodotRealityKit::isSceneVisible()) {
		[command_buffer waitUntilCompleted];
		GodotRealityKit::destroyOriginalScene();
	}
#endif
}

void SceneLoader::call_on_next_frame_completion(const std::function<void()> &p_on_next_frame_completion) {
	on_next_frame_completion = p_on_next_frame_completion;
}

void SceneLoader::cancel_press(int64_t id) {
	for (uint32_t i = 0; i < max_active_presses; ++i) {
		if (active_presses[i] != id) {
			continue;
		}
		active_presses[i] = -1;
		auto params = active_press_targets[i];
		if (!params.collider_id) {
			continue;
		}
		godot::Ref<InputEventSpatialTouch> event;
		event.instantiate();
		event->set_index(int32_t(id));
		event->set_pressed(false);
		event->set_canceled(true);
		event->set_volume_window_id(volume_id);
		event->set_world_position(from_simd3(last_active_press_position[i]));
		event->set_position(from_simd2(last_active_press_location[i]));
		params.input_event = event;
		push_input_event(params);
	}
}

void SceneLoader::flush_input_events() {
	auto events = std::move(input_event_queue);
	for (const ColliderInputEventParams &params : events) {
		godot::Node3D *camera =
				godot::Object::cast_to<godot::Node3D>(godot::ObjectDB::get_instance(params.camera_id));
		if (!camera) {
			continue;
		}

		godot::CollisionObject3D *collision_object =
				godot::Object::cast_to<godot::CollisionObject3D>(godot::ObjectDB::get_instance(params.collider_id));
		if (!collision_object) {
			continue;
		}

		collision_object->emit_signal("input_event", camera, params.input_event, params.position, params.normal, params.shape_idx);
	}
}

void SceneLoader::reset_dirty_resources() {
	TextureLoader *textures = std::get<TextureLoader *>(resource_loaders);
	MaterialLoader *materials = std::get<MaterialLoader *>(resource_loaders);
	MeshLoader *meshes = std::get<MeshLoader *>(resource_loaders);
	MultiMeshLoader *multimeshes = std::get<MultiMeshLoader *>(resource_loaders);
	ShapeLoader *shapes = std::get<ShapeLoader *>(resource_loaders);
	EnvironmentLoader *environments = std::get<EnvironmentLoader *>(resource_loaders);
	SkyboxLoader *skyboxes = std::get<SkyboxLoader *>(resource_loaders);
	SkeletonLoader *skeletons = std::get<SkeletonLoader *>(resource_loaders);

	textures->reset_dirty();
	materials->reset_dirty();
	meshes->reset_dirty();
	multimeshes->reset_dirty();
	shapes->reset_dirty();
	environments->reset_dirty();
	skyboxes->reset_dirty();
	skeletons->reset_dirty();
}

void SceneLoader::dump_metal_capture(id<MTLCommandQueue> p_command_queue) {
	const uint32_t random_id = rand() % 9999;
	NSString *ns_file_name = [NSString stringWithFormat:@"%s_%u.gputrace",
			get_scene_name().ptr(), random_id];
	NSURL *tmp_dir = [NSURL fileURLWithPath:@"~/Documents/" isDirectory:YES];
	NSURL *file_path = [tmp_dir URLByAppendingPathComponent:ns_file_name];

	MTLCaptureDescriptor *capture_descriptor = [[MTLCaptureDescriptor alloc] init];
	capture_descriptor.captureObject = p_command_queue;
	capture_descriptor.destination = MTLCaptureDestinationGPUTraceDocument;
	capture_descriptor.outputURL = file_path;

	NSError *error;
	[[MTLCaptureManager sharedCaptureManager] startCaptureWithDescriptor:capture_descriptor error:&error];

	if (error) {
		ERR_PRINT([[error localizedDescription] UTF8String]);
	} else {
		printf("Dumping Metal capture to %s\n", [[file_path absoluteString] UTF8String]);
	}
}

void RealitySceneTree::_bind_methods() {
	using namespace godot;
	ClassDB::bind_method(D_METHOD("open_volume_window", "scene_path", "title", "options"), &RealitySceneTree::open_volume_window, DEFVAL(Ref<RealityVolumeWindowOptions>()));
#define WINDOW_METHOD(name) ClassDB::bind_method(D_METHOD(#name, "window_id"), &RealitySceneTree::name)
	WINDOW_METHOD(reopen_volume_window);
	WINDOW_METHOD(close_volume_window);
	WINDOW_METHOD(destroy_volume_window);
	WINDOW_METHOD(has_volume_window);
	WINDOW_METHOD(get_volume_window_state);
	WINDOW_METHOD(get_volume_window_root);
	WINDOW_METHOD(get_volume_window_viewport);
	WINDOW_METHOD(get_volume_window_title);
	WINDOW_METHOD(get_volume_window_options);
	WINDOW_METHOD(get_volume_window_size);
#undef WINDOW_METHOD
	ClassDB::bind_method(D_METHOD("get_volume_window_ids"), &RealitySceneTree::get_volume_window_ids);
	ClassDB::bind_method(D_METHOD("get_volume_window_id", "node"), &RealitySceneTree::get_volume_window_id);
	ClassDB::bind_method(D_METHOD("set_volume_window_title", "window_id", "title"), &RealitySceneTree::set_volume_window_title);
	ClassDB::bind_method(D_METHOD("set_volume_window_options", "window_id", "options"), &RealitySceneTree::set_volume_window_options);
	BIND_ENUM_CONSTANT(INVALID);
	BIND_ENUM_CONSTANT(CLOSED);
	BIND_ENUM_CONSTANT(OPENING);
	BIND_ENUM_CONSTANT(OPEN);
	BIND_ENUM_CONSTANT(CLOSING);
	BIND_ENUM_CONSTANT(DESTROYING);
	ADD_SIGNAL(MethodInfo("volume_window_state_changed", PropertyInfo(Variant::INT, "window_id"), PropertyInfo(Variant::INT, "state")));
	ADD_SIGNAL(MethodInfo("volume_window_operation_failed", PropertyInfo(Variant::INT, "window_id"), PropertyInfo(Variant::STRING, "operation"), PropertyInfo(Variant::INT, "error"), PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("volume_window_size_changed", PropertyInfo(Variant::INT, "window_id"), PropertyInfo(Variant::VECTOR3, "size")));
	ADD_SIGNAL(MethodInfo("volume_window_destroyed", PropertyInfo(Variant::INT, "window_id")));
}

bool RealitySceneTree::has_volume_window(int64_t id) const {
	return volumes.count(id) != 0;
}
RealitySceneTree::VolumeWindowState RealitySceneTree::get_volume_window_state(int64_t id) const {
	auto it = volumes.find(id);
	return it == volumes.end() ? INVALID : it->second.state;
}
godot::PackedInt64Array RealitySceneTree::get_volume_window_ids() const {
	godot::PackedInt64Array ids;
	for (const auto &[id, record] : volumes) {
		ids.push_back(id);
	}
	return ids;
}
godot::Node *RealitySceneTree::get_volume_window_root(int64_t id) const {
	auto it = volumes.find(id);
	return it == volumes.end() ? nullptr : godot::Object::cast_to<godot::Node>(godot::ObjectDB::get_instance(it->second.root_id));
}
godot::Viewport *RealitySceneTree::get_volume_window_viewport(int64_t id) const {
	auto it = volumes.find(id);
	return it == volumes.end() ? nullptr : godot::Object::cast_to<godot::Viewport>(godot::ObjectDB::get_instance(it->second.viewport_id));
}
int64_t RealitySceneTree::get_volume_window_id(godot::Node *node) const {
	if (!node) {
		return -1;
	}
	// Compare viewports as well as ancestry: a native 2D Window under the main scene is not a volume.
	for (const auto &[id, record] : volumes) {
		auto *root = get_volume_window_root(id);
		if (root && node->get_viewport() == get_volume_window_viewport(id) && (root == node || root->is_ancestor_of(node))) {
			return id;
		}
	}
	return -1;
}
SceneLoader *RealitySceneTree::get_loader_for_node(godot::Node *node) {
	auto it = volumes.find(get_volume_window_id(node));
	return it == volumes.end() ? nullptr : it->second.loader;
}
godot::String RealitySceneTree::get_volume_window_title(int64_t id) const {
	auto it = volumes.find(id);
	return it == volumes.end() ? godot::String() : it->second.title;
}
godot::Vector3 RealitySceneTree::get_volume_window_size(int64_t id) const {
	auto it = volumes.find(id);
	return it == volumes.end() ? godot::Vector3() : it->second.size;
}
godot::Ref<RealityVolumeWindowOptions> RealitySceneTree::get_volume_window_options(int64_t id) const {
	auto it = volumes.find(id);
	return it == volumes.end() ? godot::Ref<RealityVolumeWindowOptions>() : it->second.options->snapshot();
}
void RealitySceneTree::set_window_state(int64_t id, VolumeWindowState state) {
	auto &record = volumes.at(id);
	if (record.state == state) {
		return;
	}
	record.state = state;
#if TARGET_OS_XR
	bool pending = false;
	for (const auto &[key, r] : volumes) {
		pending |= r.state == OPENING || r.state == CLOSING || r.state == DESTROYING;
	}
	bridge.setVolumeRequestsPending(pending);
#endif
	emit_signal("volume_window_state_changed", id, state);
}
void RealitySceneTree::apply_window_options(int64_t id) {
#if TARGET_OS_XR
	auto &r = volumes.at(id);
	auto o = r.options;
	bridge.configureVolumeWindow(id, r.generation, swift::String::init([NSString stringWithUTF8String:r.title.utf8().get_data()]),
			GDRKVolumeConfiguration{ to_simd3(o->get_initial_size()), to_simd3(o->get_minimum_size()), to_simd3(o->get_maximum_size()), to_simd3(r.size), o->get_resize_mode(), o->get_baseplate_visibility() });
#endif
}
godot::Error RealitySceneTree::set_volume_window_title(int64_t id, const godot::String &title) {
	auto it = volumes.find(id);
	if (it == volumes.end()) {
		return godot::ERR_DOES_NOT_EXIST;
	}
	if (it->second.state == DESTROYING) {
		return godot::ERR_BUSY;
	}
	it->second.title = title;
	apply_window_options(id);
	return godot::OK;
}
godot::Error RealitySceneTree::set_volume_window_options(int64_t id, const godot::Ref<RealityVolumeWindowOptions> &options) {
	auto it = volumes.find(id);
	if (it == volumes.end()) {
		return godot::ERR_DOES_NOT_EXIST;
	}
	if (it->second.state == DESTROYING) {
		return godot::ERR_BUSY;
	}
	if (options.is_valid() && !options->is_valid()) {
		return godot::ERR_INVALID_PARAMETER;
	}
	if (options.is_valid()) {
		it->second.options = options->snapshot();
	} else {
		it->second.options.instantiate();
	}
	apply_window_options(id);
	return godot::OK;
}
void RealitySceneTree::update_loaders() {
	retire_windows();
	for (auto &[id, r] : volumes) {
		if (r.state != DESTROYING && r.loader && get_volume_window_root(id)) {
			r.loader->update();
		}
	}
}
int64_t RealitySceneTree::open_volume_window(const godot::String &path, const godot::String &title, const godot::Ref<RealityVolumeWindowOptions> &options) {
#if TARGET_OS_XR
	if (!enabled || !loader || extension_settings.presentationStyle != kVolumetricWindow || (options.is_valid() && !options->is_valid())) {
		return -1;
	}
	godot::Ref<godot::PackedScene> packed = godot::ResourceLoader::get_singleton()->load(path, "PackedScene");
	if (packed.is_null()) {
		emit_signal("volume_window_operation_failed", -1, "open", godot::ERR_CANT_OPEN, "Unable to load volume scene: " + path);
		return -1;
	}
	auto *scene = packed->instantiate();
	if (!scene) {
		return -1;
	}
	const int64_t id = next_volume_id++;
	auto *viewport = memnew(godot::SubViewport);
	viewport->set_name("VolumeWindow_" + godot::String::num_int64(id));
	viewport->set_use_own_world_3d(true);
	viewport->set_size(godot::Vector2i(1280, 1280));
	viewport->set_update_mode(godot::SubViewport::UPDATE_DISABLED);
	auto entity = GodotRealityKit::Entity::initAndMaterialize();
	auto *extra = memnew(SceneLoader);
	extra->volume_id = id;
	extra->initialize(scene, entity);
	extra->get_nodes()->window_scene_root = scene;
	auto &r = volumes[id];
	r.loader = extra;
	r.root_id = scene->get_instance_id();
	r.viewport_id = viewport->get_instance_id();
	r.title = title;
	if (options.is_valid()) {
		r.options = options->snapshot();
	} else {
		r.options.instantiate();
	}
	// Register before _ready, so XRController3D can discover its volume without metadata.
	connect("node_added", callable_mp(extra->get_nodes(), &NodeLoaders::node_added));
	connect("node_removed", callable_mp(extra->get_nodes(), &NodeLoaders::node_removed));
	scene->connect("tree_exiting", callable_mp(this, &RealitySceneTree::volume_root_exiting).bind(id));
	viewport->add_child(scene);
	get_root()->add_child(viewport);
	if (r.state != DESTROYING) {
		reopen_volume_window(id);
	}
	return id;
#else
	return -1;
#endif
}
godot::Error RealitySceneTree::reopen_volume_window(int64_t id) {
#if !TARGET_OS_XR
	return godot::ERR_UNAVAILABLE;
#else
	if (!enabled || extension_settings.presentationStyle != kVolumetricWindow) {
		return godot::ERR_UNAVAILABLE;
	}
#endif
	auto it = volumes.find(id);
	if (it == volumes.end()) {
		return godot::ERR_DOES_NOT_EXIST;
	}
	auto &r = it->second;
	if (r.state == DESTROYING) {
		return godot::ERR_BUSY;
	}
	if (!get_volume_window_root(id)) {
		return godot::ERR_DOES_NOT_EXIST;
	}
	r.desired_open = true;
	if (r.state != CLOSED) {
		return godot::OK;
	}
#if TARGET_OS_XR
	r.generation++;
	r.loader->lifetime->generation = r.generation;
	r.native_closed = false;
	set_window_state(id, OPENING);
	bridge.registerVolumeWindow(r.loader->get_nodes()->get_root_entity(), GDRKBridgeDelegate(r.loader), id, r.generation);
	apply_window_options(id);
	bridge.reopenVolumeWindow(id, r.generation);
	return godot::OK;
#else
	return godot::ERR_UNAVAILABLE;
#endif
}
godot::Error RealitySceneTree::close_volume_window(int64_t id) {
#if !TARGET_OS_XR
	return godot::ERR_UNAVAILABLE;
#else
	if (!enabled || extension_settings.presentationStyle != kVolumetricWindow) {
		return godot::ERR_UNAVAILABLE;
	}
#endif
	auto it = volumes.find(id);
	if (it == volumes.end()) {
		return godot::ERR_DOES_NOT_EXIST;
	}
	auto &r = it->second;
	if (r.state == DESTROYING) {
		return godot::ERR_BUSY;
	}
	r.desired_open = false;
	if (r.state == CLOSED || r.state == CLOSING) {
		return godot::OK;
	}
	set_window_state(id, CLOSING);
	if (r.state == DESTROYING) {
		return godot::OK;
	}
	r.loader->stop_input();
	if (r.state == DESTROYING) {
		return godot::OK;
	}
	if (auto *xr = RealityControllerXRInterface::get_active()) {
		xr->suspend_volume(id);
	}
#if TARGET_OS_XR
	bridge.closeVolumeWindow(id, r.generation);
#endif
	return godot::OK;
}
godot::Error RealitySceneTree::destroy_volume_window(int64_t id) {
	if (id == 0) {
		return godot::ERR_UNAVAILABLE;
	}
	auto it = volumes.find(id);
	if (it == volumes.end()) {
		return godot::ERR_DOES_NOT_EXIST;
	}
	auto &r = it->second;
	if (r.state == DESTROYING) {
		return godot::OK;
	}
	r.desired_open = false;
	set_window_state(id, DESTROYING);
	r.loader->stop_input();
	if (auto *xr = RealityControllerXRInterface::get_active()) {
		xr->remove_volume(id);
	}
#if TARGET_OS_XR
	if (!r.native_closed) {
		bridge.closeVolumeWindow(id, r.generation);
	}
#endif
	return godot::OK;
}
void RealitySceneTree::native_window_event(uint64_t id, uint64_t generation, int event, const godot::String &error) {
	auto it = volumes.find(id);
	if (it == volumes.end() || it->second.generation != generation || !it->second.loader) {
		return;
	}
	auto &r = it->second;
	if (event == 0) {
		r.native_closed = false;
		if (r.state == DESTROYING || !r.desired_open) {
#if TARGET_OS_XR
			bridge.closeVolumeWindow(id, generation);
#endif
		} else {
			r.loader->input_enabled = true;
			set_window_state(id, OPEN);
		}
	} else if (event == 1 || event == 2) {
		r.native_closed = true;
		if (event == 1 && (r.state == OPEN || r.state == OPENING)) {
			r.desired_open = false;
			set_window_state(id, CLOSING);
		}
		r.loader->stop_input();
		if (auto *xr = RealityControllerXRInterface::get_active()) {
			xr->suspend_volume(id);
		}
		// System close never implicitly reopens. An explicit reopen queued during CLOSING does.
		bool reopen = r.state == CLOSING && r.desired_open && event == 1;
		r.desired_open = reopen;
		if (r.state != DESTROYING) {
			set_window_state(id, CLOSED);
		}
		if (event == 2) {
			emit_signal("volume_window_operation_failed", id, "open", godot::ERR_CANT_OPEN, error);
		}
		if (reopen) {
			reopen_volume_window(id);
		}
		if (r.state == DESTROYING) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (auto *tree = godot::Object::cast_to<RealitySceneTree>(get_scene_tree())) {
					tree->retire_windows();
				}
			});
		}
	} else if (event == 4) {
		emit_signal("volume_window_operation_failed", id, "configure", godot::FAILED, error);
	} else if (event == 3) {
		// A rejected native close must not free a still-live host.
		r.desired_open = true;
		r.loader->input_enabled = true;
		set_window_state(id, OPEN);
		emit_signal("volume_window_operation_failed", id, "close", godot::FAILED, error);
	}
}
void RealitySceneTree::native_window_size(uint64_t id, uint64_t generation, const godot::Vector3 &size) {
	auto it = volumes.find(id);
	if (it == volumes.end() || it->second.generation != generation || it->second.state == DESTROYING) {
		return;
	}
	if (!it->second.size.is_equal_approx(size)) {
		it->second.size = size;
		if (it->second.options->get_resize_mode() == RealityVolumeWindowOptions::RESIZE_FIXED) {
			// An unspecified fixed size freezes the first actual system measurement.
			apply_window_options(id);
		}
		emit_signal("volume_window_size_changed", id, size);
	}
}
void RealitySceneTree::volume_root_exiting(int64_t id) {
	if (id == 0) {
		close_volume_window(0);
	} else {
		destroy_volume_window(id);
	}
}
void RealitySceneTree::retire_windows() {
	godot::LocalVector<int64_t> retired;
	for (auto &[id, r] : volumes) {
		if (!id || r.state != DESTROYING || !r.native_closed) {
			continue;
		}
		if (!r.loader) {
			if (!get_volume_window_viewport(id)) {
				retired.push_back(id);
			}
			continue;
		}
		if (!r.loader->ready_to_release()) {
			continue;
		}
		r.loader->lifetime->loader = nullptr;
#if TARGET_OS_XR
		bridge.forgetVolumeWindow(id, r.generation);
#endif
		disconnect("node_added", callable_mp(r.loader->get_nodes(), &NodeLoaders::node_added));
		disconnect("node_removed", callable_mp(r.loader->get_nodes(), &NodeLoaders::node_removed));
		if (auto *root = get_volume_window_root(id)) {
			root->disconnect("tree_exiting", callable_mp(this, &RealitySceneTree::volume_root_exiting).bind(id));
		}
		if (auto *viewport = get_volume_window_viewport(id)) {
			viewport->queue_free();
		}
		godot::memdelete(r.loader);
		r.loader = nullptr;
	}
	for (int64_t id : retired) {
		volumes.erase(id);
		emit_signal("volume_window_destroyed", id);
	}
#if TARGET_OS_XR
	bool pending = false;
	for (const auto &[id, r] : volumes) {
		pending |= r.state == OPENING || r.state == CLOSING || r.state == DESTROYING;
	}
	bridge.setVolumeRequestsPending(pending);
#endif
}
RealitySceneTree::~RealitySceneTree() {
	for (auto &[id, r] : volumes) {
		if (id && r.loader) {
			godot::memdelete(r.loader);
		}
	}
	if (loader) {
		godot::memdelete(loader);
	}
#if TARGET_OS_XR
	if (controller_interface.is_valid()) {
		controller_interface->uninitialize();
		if (auto *xr = godot::XRServer::get_singleton()) {
			xr->remove_interface(controller_interface);
		}
		controller_interface.unref();
	}
#endif
}

void RealitySceneTree::_initialize() {
	PROFILE_FUNC_SCOPE;

	godot::Engine *engine = godot::Engine::get_singleton();
	godot::RenderingServer *rendering_server = godot::RenderingServer::get_singleton();
	if (engine->is_embedded_in_editor() || engine->is_editor_hint()) {
		enabled = false;
	}

#if TARGET_OS_OSX
	{
		godot::ProjectSettings *ps = godot::ProjectSettings::get_singleton();
		const char *key = "reality_kit/debug_rendering_on_macos";
		const bool macos_debug = ps->has_setting(key) && ps->get_setting(key).booleanize();
		if (!macos_debug) {
			enabled = false;
		} else if (engine->is_embedded_in_editor()) {
			WARN_PRINT("GodotRealityKit: reality_kit/debug_rendering_on_macos is enabled but the game is running embedded in the editor.\n"
					   "Disable \"Embed Game on Next Play\".");
		}
	}
#endif

	if (!enabled) {
		godot::SceneTree::_initialize();
		return;
	}

	loader = memnew(SceneLoader);
	loader->initialize(get_current_scene(), bridge.getRoot());
	connect("node_added", callable_mp(loader->get_nodes(), &gdrk::NodeLoaders::node_added));
	connect("node_removed", callable_mp(loader->get_nodes(), &gdrk::NodeLoaders::node_removed));

	auto &main_volume = volumes[0];
	main_volume.loader = loader;
	main_volume.root_id = get_current_scene() ? get_current_scene()->get_instance_id() : 0;
	main_volume.viewport_id = get_root()->get_instance_id();
	main_volume.options.instantiate();
	main_volume.state = OPENING;
	main_volume.desired_open = true;
	main_volume.native_closed = false;
	if (get_current_scene()) {
		get_current_scene()->connect("tree_exiting", callable_mp(this, &RealitySceneTree::volume_root_exiting).bind(0));
	}
	GDRKBridgeDelegate bridge_delegate = GDRKBridgeDelegate(loader);
	bridge.initialize(bridge_delegate);

	extension_settings = bridge_delegate.getExtensionSettings();

#if TARGET_OS_XR
	godot::ProjectSettings *project_settings = godot::ProjectSettings::get_singleton();
	godot::XRServer *xr_server = godot::XRServer::get_singleton();

	const bool controller_tracking_enabled = project_settings->get("xr/visionos/enable_controller_tracking");
	const bool hand_tracking_enabled = project_settings->get("xr/visionos/enable_hand_tracking");

	// A shared volume has no compositor services session, so the engine's ARKit-backed tracker
	// can't run there. Publish the poses of the controllers' RealityKit accessory anchors
	// instead.
	if (controller_tracking_enabled && extension_settings.presentationStyle == kVolumetricWindow) {
		godot::Ref<RealityControllerXRInterface> accessory_interface;
		accessory_interface.instantiate();
		xr_server->add_interface(accessory_interface);
		accessory_interface->initialize();
		controller_interface = accessory_interface;
	}

	// Both are immersive-only now that a shared volume tracks the controllers through their
	// accessory anchors above.
	const bool controllers_apply = controller_tracking_enabled && extension_settings.presentationStyle == kImmersive;
	const bool hands_apply = hand_tracking_enabled && extension_settings.presentationStyle == kImmersive;

	if (controllers_apply || hands_apply) {
		godot::Ref<godot::XRInterface> xr_interface = xr_server->find_interface("visionOS");
		if (xr_interface.is_valid()) {
			xr_interface->initialize();
		}
	}
#endif // TARGET_OS_XR

	godot::SceneTree::_initialize();

	if (should_dump_reality_file()) {
		dump_reality_file_and_quit();
	}
}

bool RealitySceneTree::_process(double p_time) {
	PROFILE_FUNC_SCOPE;
	if (!enabled) {
		return godot::SceneTree::_process(p_time);
	}

	const godot::RID viewport_rid = get_root()->get_viewport_rid();
	rendering_server()->viewport_set_update_mode(viewport_rid, godot::RenderingServer::VIEWPORT_UPDATE_DISABLED);

	// Early exit if the game is paused while we wait for blocking async tasks
	godot::SceneTree *scene_tree = this;
	retire_windows();
	if (GodotRealityKit::isBlockingAsyncTaskRunning()) {
		if (!paused_for_blocking_task) {
			scene_tree->set_pause(true);
			paused_for_blocking_task = true;
		}

		return false;
	} else {
		if (paused_for_blocking_task) {
			scene_tree->set_pause(false);
			paused_for_blocking_task = false;
		}
	}

	// Only update the RealityKit scene if the app is in the foreground (visible)
#if !TESTING_ENABLED
	if (!bridge.isSceneVisible()) {
		bool pending = false;
		for (const auto &[id, r] : volumes) {
			pending |= r.state == OPENING || r.state == CLOSING || r.state == DESTROYING;
		}
		if (!pending) {
			return false;
		}
	}
#endif

	const bool res = godot::SceneTree::_process(p_time);

	return res;
}

bool RealitySceneTree::_physics_process(double p_time) {
	PROFILE_FUNC_SCOPE;

	if (GodotRealityKit::isBlockingAsyncTaskRunning()) {
		return false;
	}

	const bool res = godot::SceneTree::_physics_process(p_time);
	if (loader) {
		loader->flush_input_events();
	}
	for (auto &[id, r] : volumes) {
		if (id && r.loader && r.loader->input_enabled) {
			r.loader->flush_input_events();
		}
	}
	return res;
}

void RealitySceneTree::clear_boot_image() {
	godot::RenderingServer *rendering_server = godot::RenderingServer::get_singleton();

	godot::PackedByteArray empty_boot_logo_data;
	empty_boot_logo_data.resize(4);
	empty_boot_logo_data.fill(0);

	godot::Ref<godot::Image> empty_boot_logo;
	empty_boot_logo.instantiate();
	empty_boot_logo->set_data(1, 1, false, godot::Image::FORMAT_RGBA8, empty_boot_logo_data);
	rendering_server->set_boot_image(empty_boot_logo, godot::Color(0.0, 0.0, 0.0, 0.0), false);
}

void RealitySceneTree::dump_reality_file_and_quit() {
	loader->call_on_next_frame_completion([this]() {
		const uint32_t random_id = rand() % 9999;
		NSString *ns_file_name = [NSString stringWithFormat:@"%s_%u.reality",
				get_scene_name().ptr(), random_id];
		NSURL *tmp_dir = [NSURL fileURLWithPath:@"~/Documents/" isDirectory:YES];
		NSURL *file_path = [tmp_dir URLByAppendingPathComponent:ns_file_name];

		GDRKEntityWriteDelegate entity_write_delegate = GDRKEntityWriteDelegate([this] {
			quit();
		});

		GodotRealityKit::Entity root_entity = get_loader()->get_nodes()->get_root_entity();
		root_entity.writeAsync(swift::String::init([file_path relativeString]),
				entity_write_delegate);
	});
}

} // namespace gdrk

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

#import "controller_xr_interface.h"

#import "scene_tree.h"
#import "utility.h"

#import <CoreHaptics/CoreHaptics.h>
#import <GameController/GameController.h>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/xr_pose.hpp>
#include <godot_cpp/classes/xr_server.hpp>

#include <algorithm>
#include <cmath>

namespace gdrk {
static double controller_time() { return godot::Time::get_singleton()->get_ticks_usec() / 1000000.0; }

// Deliberately distinct from the engine's "visionOSControllerTracker": both publish controller
// poses, but only one of them is initialized for a given presentation style.
const char *RealityControllerXRInterface::interface_name = "GDRKAccessoryControllerTracker";

RealityControllerXRInterface *RealityControllerXRInterface::active = nullptr;

// The pose XRController3D reads by default.
static const godot::StringName &default_pose_name() {
	static const godot::StringName name("default");
	return name;
}

void RealityControllerXRInterface::_bind_methods() {
	using namespace godot;
	ClassDB::bind_method(D_METHOD("tracker_for_volume", "window_id", "hand"), &RealityControllerXRInterface::tracker_for_volume);
	ClassDB::bind_method(D_METHOD("is_controller_connected", "hand"), &RealityControllerXRInterface::is_controller_connected);
	ClassDB::bind_method(D_METHOD("get_supported_inputs", "hand"), &RealityControllerXRInterface::get_supported_inputs);
	ClassDB::bind_method(D_METHOD("get_supported_poses", "hand"), &RealityControllerXRInterface::get_supported_poses);
	ClassDB::bind_method(D_METHOD("supports_haptics", "hand"), &RealityControllerXRInterface::supports_haptics);
	ADD_SIGNAL(MethodInfo("controller_connection_changed", PropertyInfo(Variant::STRING, "hand"), PropertyInfo(Variant::BOOL, "connected")));
	ADD_SIGNAL(MethodInfo("controller_capabilities_changed", PropertyInfo(Variant::STRING, "hand")));
	ADD_SIGNAL(MethodInfo("tracking_error", PropertyInfo(Variant::STRING, "message")));

	godot::ClassDB::bind_method(godot::D_METHOD("tracker_for_node", "node", "hand"), &RealityControllerXRInterface::tracker_for_node);
	godot::ClassDB::bind_method(godot::D_METHOD("log_diagnostic", "message"), &RealityControllerXRInterface::log_diagnostic);
}

void RealityControllerXRInterface::log_diagnostic(const godot::String &p_message) const {
	// Use the native console even when the embedded engine redirects stdout/stderr.
	NSLog(@"%s", p_message.utf8().get_data());
}

godot::StringName RealityControllerXRInterface::_get_name() const {
	return godot::StringName(interface_name);
}

uint32_t RealityControllerXRInterface::_get_capabilities() const {
	// Tracking only; the RealityKit bridge owns rendering.
	return godot::XRInterface::XR_NONE;
}

bool RealityControllerXRInterface::_is_initialized() const {
	return initialized;
}

bool RealityControllerXRInterface::_initialize() {
	if (initialized) {
		return true;
	}

#if TARGET_OS_XR
	if (!GodotRealityKit::Bridge::isAccessoryTrackingSupported()) {
		return false;
	}
#else
	return false;
#endif
	godot::XRServer *xr_server = godot::XRServer::get_singleton();
	ERR_FAIL_NULL_V(xr_server, false);

	left.tracker.instantiate();
	left.tracker->set_tracker_hand(godot::XRPositionalTracker::TRACKER_HAND_LEFT);
	left.tracker->set_tracker_name("left_hand");
	left.tracker->set_tracker_desc("Spatial controller held in the left hand");
	xr_server->add_tracker(left.tracker);

	right.tracker.instantiate();
	right.tracker->set_tracker_hand(godot::XRPositionalTracker::TRACKER_HAND_RIGHT);
	right.tracker->set_tracker_name("right_hand");
	right.tracker->set_tracker_desc("Spatial controller held in the right hand");
	xr_server->add_tracker(right.tracker);
	left.suspended = true;
	right.suspended = true;

	initialized = true;
	active = this;
	return true;
}

void RealityControllerXRInterface::_uninitialize() {
	if (!initialized) {
		return;
	}

	if (active == this) {
		active = nullptr;
	}

	godot::XRServer *xr_server = godot::XRServer::get_singleton();
	for (Controller *controller : { &left, &right }) {
		if (xr_server != nullptr && controller->tracker.is_valid()) {
			xr_server->remove_tracker(controller->tracker);
		}
		controller->tracker.unref();
		controller->tracked = false;
		controller->pose_published = false;
		release_haptic_engine(*controller);
		if (controller->gc_controller) {
			CFRelease(controller->gc_controller);
		}
		controller->gc_controller = nullptr;
		controller->input = {};
		controller->poses.clear();
		controller->suspended = false;
	}

	for (auto &[id, pair] : windows) {
		for (auto &controller : pair) {
			if (xr_server && controller.tracker.is_valid()) { xr_server->remove_tracker(controller.tracker); }
		}
	}
	windows.clear(); mixer.clear();
	output_amplitude = {}; output_frequency = {}; output_renewal = {};
	initialized = false;
	provider_running = false;
#if TARGET_OS_XR
	GodotRealityKit::Bridge::stopAccessoryTracking();
#endif
}

godot::XRInterface::TrackingStatus RealityControllerXRInterface::_get_tracking_status() const {
	if (!initialized) {
		return godot::XRInterface::XR_NOT_TRACKING;
	}
	if (!provider_running) {
		return godot::XRInterface::XR_NOT_TRACKING;
	}
	bool low = false;
	auto status = [&](const Controller &c) {
		for (const auto &[name, pose] : c.poses) {
			if (c.tracked && pose.confidence == godot::XRPose::XR_TRACKING_CONFIDENCE_HIGH) {
				return true;
			}
			low |= c.tracked && pose.confidence == godot::XRPose::XR_TRACKING_CONFIDENCE_LOW;
		}
		return false;
	};
	if (status(left) || status(right)) {
		return godot::XRInterface::XR_NORMAL_TRACKING;
	}
	for (const auto &[id, pair] : windows) {
		for (const auto &c : pair) {
			if (status(c)) {
				return godot::XRInterface::XR_NORMAL_TRACKING;
			}
		}
	}
	return low ? godot::XRInterface::XR_INSUFFICIENT_FEATURES : godot::XRInterface::XR_NOT_TRACKING;
}

godot::PackedStringArray RealityControllerXRInterface::_get_suggested_tracker_names() const {
	godot::PackedStringArray names;
	names.push_back("left_hand");
	names.push_back("right_hand");
	for (const auto &[id, pair] : windows) {
		for (const auto &c : pair) {
			if (c.tracker.is_valid()) {
				names.push_back(c.tracker->get_tracker_name());
			}
		}
	}
	return names;
}

void RealityControllerXRInterface::set_anchor_pose(godot::XRPositionalTracker::TrackerHand p_hand,
		const godot::Transform3D &p_pose,
		bool p_tracked, uint64_t p_window) {
	Controller &controller = window_controller(p_window, p_hand == godot::XRPositionalTracker::TRACKER_HAND_LEFT);
	controller.updated_at = controller_time();
	controller.pose = p_pose;
	controller.tracked = p_tracked;
}

void RealityControllerXRInterface::set_controller_input(godot::XRPositionalTracker::TrackerHand p_hand,
		const ControllerInput &p_input,
		void *p_gc_controller) {
	Controller &controller = (p_hand == godot::XRPositionalTracker::TRACKER_HAND_LEFT) ? left : right;
	const bool changed = controller.gc_controller != p_gc_controller;
	const bool capabilities_changed = controller.input.supported != p_input.supported || controller.input.poses != p_input.poses || controller.input.haptics != p_input.haptics;
	controller.input = p_input;
	controller.has_input = true;

	if (controller.gc_controller != p_gc_controller) {
		release_haptic_engine(controller);
		if (controller.gc_controller) {
			CFRelease(controller.gc_controller);
		}
		controller.gc_controller = p_gc_controller;
		if (p_gc_controller) {
			CFRetain(p_gc_controller);
		}
	}
	if (!p_gc_controller) {
		const bool is_left = p_hand == godot::XRPositionalTracker::TRACKER_HAND_LEFT;
		controller.tracked = false;
		mixer.remove_hand(is_left);
		for (auto &[id, pair] : windows) {
			pair[is_left ? 0 : 1].tracked = false;
		}
	}
	const godot::String hand = p_hand == godot::XRPositionalTracker::TRACKER_HAND_LEFT ? "left_hand" : "right_hand";
	if (changed) {
		emit_signal("controller_connection_changed", hand, p_gc_controller != nullptr);
	}
	if (capabilities_changed) {
		emit_signal("controller_capabilities_changed", hand);
	}
}

void RealityControllerXRInterface::_process() {
	const double now = controller_time();
	for (Controller *controller : { &left, &right }) {
		if (now - controller->updated_at > 0.5) { controller->tracked = false; }
		publish(*controller);
	}
	for (auto &[id, pair] : windows) {
		for (int i = 0; i < 2; ++i) {
			auto &controller = pair[i];
			if (now - controller.updated_at > 0.5) { controller.tracked = false; }
			const auto &physical = i == 0 ? left : right;
			controller.input = controller.suspended ? ControllerInput() : physical.input;
			controller.has_input = physical.has_input;
			publish(controller);
		}
	}
	mix_haptics();
}

RealityControllerXRInterface::Controller &RealityControllerXRInterface::window_controller(uint64_t id, bool is_left) {
	if (!id) { return is_left ? left : right; }
	auto &controller = windows[id][is_left ? 0 : 1];
	if (controller.tracker.is_null()) {
		controller.suspended = true;
		controller.tracker.instantiate();
		controller.tracker->set_tracker_hand(is_left ? godot::XRPositionalTracker::TRACKER_HAND_LEFT : godot::XRPositionalTracker::TRACKER_HAND_RIGHT);
		controller.tracker->set_tracker_name(godot::String("/gdrk/window/") + godot::String::num_uint64(id) + (is_left ? "/left_hand" : "/right_hand"));
		godot::XRServer::get_singleton()->add_tracker(controller.tracker);
	}
	return controller;
}

godot::StringName RealityControllerXRInterface::tracker_for_node(godot::Node *node, const godot::String &hand) {
	if (!initialized || !node) {
		return {};
	}
	auto *tree = godot::Object::cast_to<RealitySceneTree>(godot::Engine::get_singleton()->get_main_loop());
	return tree ? tracker_for_volume(tree->get_volume_window_id(node), hand) : godot::StringName();
}
godot::StringName RealityControllerXRInterface::tracker_for_volume(int64_t id, const godot::String &hand) {
	if (!initialized || id < 0 || (hand != "left_hand" && hand != "right_hand")) {
		return {};
	}
	auto *tree = godot::Object::cast_to<RealitySceneTree>(godot::Engine::get_singleton()->get_main_loop());
	if (!tree || !tree->has_volume_window(id) || tree->get_volume_window_state(id) == RealitySceneTree::DESTROYING) {
		return {};
	}
	return window_controller(id, hand == "left_hand").tracker->get_tracker_name();
}
const RealityControllerXRInterface::Controller *RealityControllerXRInterface::physical_for_hand(const godot::String &hand) const {
	return hand == "left_hand" ? &left : (hand == "right_hand" ? &right : nullptr);
}
bool RealityControllerXRInterface::is_controller_connected(const godot::String &hand) const {
	auto *c = physical_for_hand(hand);
	return initialized && c && c->gc_controller;
}
godot::PackedStringArray RealityControllerXRInterface::get_supported_inputs(const godot::String &hand) const {
	auto *c = physical_for_hand(hand);
	return c ? c->input.supported : godot::PackedStringArray();
}
godot::PackedStringArray RealityControllerXRInterface::get_supported_poses(const godot::String &hand) const {
	auto *c = physical_for_hand(hand);
	return c ? c->input.poses : godot::PackedStringArray();
}
bool RealityControllerXRInterface::supports_haptics(const godot::String &hand) const {
	auto *c = physical_for_hand(hand);
	return c && c->gc_controller && c->input.haptics;
}
void RealityControllerXRInterface::set_tracking_state(bool running, const godot::String &error) {
	provider_running = running;
	if (!running) {
		suspend_volume(0);
		for (auto &[id, pair] : windows) {
			suspend_volume(id);
		}
	}
	if (!error.is_empty()) {
		emit_signal("tracking_error", error);
	}
}
void RealityControllerXRInterface::suspend_volume(uint64_t id) {
	if (id && !windows.count(id)) {
		return;
	}
	for (int i = 0; i < 2; ++i) {
		auto &c = id ? windows.at(id)[i] : (i ? right : left);
		c.tracked = false;
		c.suspended = true;
		for (auto &[name, pose] : c.poses) {
			pose.confidence = godot::XRPose::XR_TRACKING_CONFIDENCE_NONE;
		}
		if (c.tracker.is_valid()) {
			mixer.remove(godot::String(c.tracker->get_tracker_name()).utf8().get_data());
		}
		publish(c);
	}
	mix_haptics();
}
void RealityControllerXRInterface::remove_volume(uint64_t id) {
	suspend_volume(id);
	auto it = windows.find(id);
	if (it == windows.end()) {
		return;
	}
	for (auto &c : it->second) {
		if (c.tracker.is_valid()) {
			godot::XRServer::get_singleton()->remove_tracker(c.tracker);
		}
	}
	windows.erase(it);
}
void RealityControllerXRInterface::set_named_pose(uint64_t volume, bool is_left, const godot::StringName &name, const godot::Transform3D &transform,
		const godot::Vector3 &velocity, const godot::Vector3 &angular, int confidence, bool supported) {
	auto &c = window_controller(volume, is_left);
	c.suspended = false;
	c.updated_at = controller_time();
	auto &p = c.poses[name];
	p = { transform, velocity, angular, static_cast<godot::XRPose::TrackingConfidence>(confidence), supported };
	if (name == godot::StringName("grip")) {
		c.poses["default"] = p;
	}
	c.tracked = false;
	for (const auto &[key, pose] : c.poses) {
		c.tracked |= pose.confidence != godot::XRPose::XR_TRACKING_CONFIDENCE_NONE;
	}
}

void RealityControllerXRInterface::publish(Controller &p_controller) {
	if (p_controller.tracker.is_null()) {
		return;
	}

	for (const auto &[name, pose] : p_controller.poses) {
		if (p_controller.tracked && pose.supported && pose.confidence != godot::XRPose::XR_TRACKING_CONFIDENCE_NONE) {
			p_controller.tracker->set_pose(name, pose.transform, pose.velocity, pose.angular, pose.confidence);
		} else {
			p_controller.tracker->invalidate_pose(name);
		}
	}

	if (p_controller.has_input) {
		const godot::Ref<godot::XRControllerTracker> &tracker = p_controller.tracker;
		const ControllerInput in = p_controller.suspended ? ControllerInput() : p_controller.input;
		tracker->set_input("trigger", in.trigger);
		tracker->set_input("trigger_click", in.trigger_click);
		tracker->set_input("grip", in.grip);
		tracker->set_input("grip_click", in.grip_click);
		tracker->set_input("ax_button", in.primary_button);
		tracker->set_input("by_button", in.secondary_button);
		tracker->set_input("menu_button", in.menu_button);
		tracker->set_input("primary", in.thumbstick);
		tracker->set_input("primary_click", in.thumbstick_click);
		tracker->set_input("trigger_touch", in.trigger_touch);
		tracker->set_input("grip_touch", in.grip_touch);
		tracker->set_input("primary_touch", in.primary_touch);
		tracker->set_input("ax_touch", in.ax_touch);
		tracker->set_input("by_touch", in.by_touch);
	}
}

RealityControllerXRInterface::Controller *RealityControllerXRInterface::controller_for_tracker(const godot::StringName &p_tracker_name) {
	static const godot::StringName right_hand("right_hand");
	static const godot::StringName left_hand("left_hand");
	if (p_tracker_name == left_hand) {
		return &left;
	}
	if (p_tracker_name == right_hand) {
		return &right;
	}
	for (auto &[id, pair] : windows) {
		for (int i = 0; i < 2; ++i) {
			if (pair[i].tracker.is_valid() && pair[i].tracker->get_tracker_name() == p_tracker_name) { return i == 0 ? &left : &right; }
		}
	}
	return nullptr;
}

void *RealityControllerXRInterface::ensure_haptic_engine(Controller &p_controller) {
	if (p_controller.haptic_engine == nullptr) {
		GCController *gc_controller = (__bridge GCController *)p_controller.gc_controller;
		GCDeviceHaptics *haptics = gc_controller.haptics;
		if (haptics == nil) {
			ERR_PRINT("[GDRK Haptics] Controller exposes no haptics");
			return nullptr;
		}

		CHHapticEngine *engine = [haptics createEngineWithLocality:GCHapticsLocalityAll];
		if (engine == nil) {
			return nullptr;
		}

		p_controller.haptic_engine = (__bridge_retained void *)engine;
	}

	CHHapticEngine *engine = (__bridge CHHapticEngine *)p_controller.haptic_engine;
	NSError *error = nil;
	if (![engine startAndReturnError:&error]) {
		ERR_PRINT("[RealityControllerXRInterface] Haptic engine failed to start");
		return nullptr;
	}

	return p_controller.haptic_engine;
}

void RealityControllerXRInterface::stop_haptic_player(Controller &p_controller) {
	if (p_controller.haptic_player == nullptr) { return; }
	id<CHHapticPatternPlayer> player = (__bridge_transfer id<CHHapticPatternPlayer>)p_controller.haptic_player;
	[player stopAtTime:CHHapticTimeImmediate error:nil];
	p_controller.haptic_player = nullptr;
}

void RealityControllerXRInterface::release_haptic_engine(Controller &p_controller) {
	stop_haptic_player(p_controller);
	if (p_controller.haptic_engine == nullptr) {
		return;
	}

	CHHapticEngine *engine = (__bridge_transfer CHHapticEngine *)p_controller.haptic_engine;
	[engine stopWithCompletionHandler:nil];
	p_controller.haptic_engine = nullptr;
}

// Requests are independent per window tracker. Releasing one cannot stop another.
void RealityControllerXRInterface::_trigger_haptic_pulse(const godot::String &action, const godot::StringName &tracker, double frequency, double amplitude, double duration, double delay) {
	auto *physical = controller_for_tracker(tracker);
	if (!physical) { return; }
    mixer.submit(godot::String(tracker).utf8().get_data(), physical == &left,
        amplitude, frequency, duration, delay, controller_time());
}

void RealityControllerXRInterface::mix_haptics() {
	const double now = controller_time();
    const auto outputs = mixer.evaluate(now, [&](const std::string &key) {
        Controller *source = nullptr;
        const godot::StringName name(key.c_str());
        if (left.tracker.is_valid() && left.tracker->get_tracker_name() == name) { source = &left; }
        if (right.tracker.is_valid() && right.tracker->get_tracker_name() == name) { source = &right; }
        for (auto &[id, pair] : windows) {
            for (auto &candidate : pair) {
                if (candidate.tracker.is_valid() && candidate.tracker->get_tracker_name() == name) { source = &candidate; }
            }
        }
        return source && source->tracked && now - source->updated_at <= 0.5;
    });
    std::array<double, 2> amplitude = {outputs[0].amplitude, outputs[1].amplitude};
    const std::array<double, 2> frequency = {outputs[0].frequency, outputs[1].frequency};
	for (int i = 0; i < 2; ++i) {
		auto &physical = i == 0 ? left : right;
		if (!physical.gc_controller) { amplitude[i] = 0.0; }
		if (amplitude[i] != output_amplitude[i] || frequency[i] != output_frequency[i] || (amplitude[i] > 0.0 && now >= output_renewal[i])) {
			play_haptic_pulse("haptic", i == 0 ? "left_hand" : "right_hand", frequency[i], amplitude[i], 0.12, 0.0);
			output_amplitude[i] = amplitude[i]; output_frequency[i] = frequency[i]; output_renewal[i] = now + 0.08;
		}
	}
}

void RealityControllerXRInterface::play_haptic_pulse(const godot::String &p_action_name, const godot::StringName &p_tracker_name, double p_frequency, double p_amplitude, double p_duration_sec, double p_delay_sec) {
	Controller *controller = controller_for_tracker(p_tracker_name);
	if (controller == nullptr || controller->gc_controller == nullptr) {
		return;
	}

	// Zero amplitude explicitly cancels the previous pulse without creating an engine.
	if (p_amplitude <= 0.0) {
		stop_haptic_player(*controller);
		NSLog(@"[GDRK Haptics] stopped tracker=%s", godot::String(p_tracker_name).utf8().get_data());
		return;
	}
	void *raw_engine = ensure_haptic_engine(*controller);
	if (raw_engine == nullptr) {
		return;
	}
	CHHapticEngine *engine = (__bridge CHHapticEngine *)raw_engine;

	// CoreHaptics has no frequency parameter; approximate the requested pitch as sharpness,
	// normalized against a spatial controller's actuator range (roughly 0-320 Hz).
	const float sharpness = p_frequency > 0.0 ? std::clamp((float)(p_frequency / 320.0), 0.0f, 1.0f) : 0.5f;
	NSArray<CHHapticEventParameter *> *params = @[
		[[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity
													  value:std::clamp((float)p_amplitude, 0.0f, 1.0f)],
		[[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness
													  value:sharpness],
	];

	CHHapticEventType event_type = p_duration_sec > 0.0 ? CHHapticEventTypeHapticContinuous : CHHapticEventTypeHapticTransient;
	CHHapticEvent *event = [[CHHapticEvent alloc] initWithEventType:event_type
														 parameters:params
													   relativeTime:std::max(0.0, p_delay_sec)
														   duration:std::clamp(p_duration_sec, 0.0, 30.0)];

	NSError *error = nil;
	CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[ event ] parameters:@[] error:&error];
	if (pattern == nil) {
		return;
	}

	id<CHHapticPatternPlayer> player = [engine createPlayerWithPattern:pattern error:&error];
	if (player == nil) {
		return;
	}

	const bool first_pulse = controller->haptic_player == nullptr;
	stop_haptic_player(*controller);
	if (![player startAtTime:CHHapticTimeImmediate error:&error]) {
		NSLog(@"[GDRK Haptics] start failed: %@", error);
		return;
	}
	controller->haptic_player = (__bridge_retained void *)player;
	if (first_pulse) {
		NSLog(@"[GDRK Haptics] started tracker=%s amplitude=%.2f duration=%.2f", godot::String(p_tracker_name).utf8().get_data(), p_amplitude, p_duration_sec);
	}
}

} // namespace gdrk

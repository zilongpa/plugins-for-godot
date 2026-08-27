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

#include <godot_cpp/classes/xr_pose.hpp>
#include <godot_cpp/classes/xr_server.hpp>

#include <algorithm>

#import <CoreHaptics/CoreHaptics.h>
#import <GameController/GameController.h>

namespace gdrk {

// Deliberately distinct from the engine's "visionOSControllerTracker": both publish controller
// poses, but only one of them is initialized for a given presentation style.
const char *RealityControllerXRInterface::interface_name = "GDRKAccessoryControllerTracker";

RealityControllerXRInterface *RealityControllerXRInterface::active = nullptr;

// The pose XRController3D reads by default.
static const godot::StringName &default_pose_name() {
	static const godot::StringName name("default");
	return name;
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
		controller->gc_controller = nullptr;
	}

	initialized = false;
}

godot::XRInterface::TrackingStatus RealityControllerXRInterface::_get_tracking_status() const {
	if (!initialized) {
		return godot::XRInterface::XR_NOT_TRACKING;
	}
	// No controller anchored yet is indistinguishable from none connected, so report the
	// optimistic status only once something is actually being tracked.
	return (left.tracked || right.tracked) ? godot::XRInterface::XR_NORMAL_TRACKING
										   : godot::XRInterface::XR_NOT_TRACKING;
}

godot::PackedStringArray RealityControllerXRInterface::_get_suggested_tracker_names() const {
	godot::PackedStringArray names;
	names.push_back("left_hand");
	names.push_back("right_hand");
	return names;
}

void RealityControllerXRInterface::set_anchor_pose(godot::XRPositionalTracker::TrackerHand p_hand,
		const godot::Transform3D &p_pose,
		bool p_tracked) {
	Controller &controller = (p_hand == godot::XRPositionalTracker::TRACKER_HAND_LEFT) ? left : right;
	controller.pose = p_pose;
	controller.tracked = p_tracked;
}

void RealityControllerXRInterface::set_controller_input(godot::XRPositionalTracker::TrackerHand p_hand,
		const ControllerInput &p_input,
		void *p_gc_controller) {
	Controller &controller = (p_hand == godot::XRPositionalTracker::TRACKER_HAND_LEFT) ? left : right;
	controller.input = p_input;
	controller.has_input = true;

	if (controller.gc_controller != p_gc_controller) {
		release_haptic_engine(controller);
		controller.gc_controller = p_gc_controller;
	}
}

void RealityControllerXRInterface::_process() {
	publish(left);
	publish(right);
}

void RealityControllerXRInterface::publish(Controller &p_controller) {
	if (p_controller.tracker.is_null()) {
		return;
	}

	if (p_controller.tracked) {
		// The bridge samples the anchor once per RealityKit update, so there is no meaningful
		// velocity to report.
		p_controller.tracker->set_pose(default_pose_name(), p_controller.pose,
				godot::Vector3(), godot::Vector3(), godot::XRPose::XR_TRACKING_CONFIDENCE_HIGH);
		p_controller.pose_published = true;
	} else if (p_controller.pose_published) {
		p_controller.tracker->invalidate_pose(default_pose_name());
		p_controller.pose_published = false;
	}

	if (p_controller.has_input) {
		const godot::Ref<godot::XRControllerTracker> &tracker = p_controller.tracker;
		const ControllerInput &in = p_controller.input;
		tracker->set_input("trigger", in.trigger);
		tracker->set_input("trigger_click", in.trigger_click);
		tracker->set_input("grip", in.grip);
		tracker->set_input("grip_click", in.grip_click);
		tracker->set_input("ax_button", in.primary_button);
		tracker->set_input("by_button", in.secondary_button);
		tracker->set_input("menu_button", in.menu_button);
		tracker->set_input("primary", in.thumbstick);
		tracker->set_input("primary_click", in.thumbstick_click);
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
	return nullptr;
}

void *RealityControllerXRInterface::ensure_haptic_engine(Controller &p_controller) {
	if (p_controller.haptic_engine == nullptr) {
		GCController *gc_controller = (__bridge GCController *)p_controller.gc_controller;
		GCDeviceHaptics *haptics = gc_controller.haptics;
		if (haptics == nil) {
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

void RealityControllerXRInterface::release_haptic_engine(Controller &p_controller) {
	if (p_controller.haptic_engine == nullptr) {
		return;
	}

	CHHapticEngine *engine = (__bridge_transfer CHHapticEngine *)p_controller.haptic_engine;
	[engine stopWithCompletionHandler:nil];
	p_controller.haptic_engine = nullptr;
}

void RealityControllerXRInterface::_trigger_haptic_pulse(const godot::String &p_action_name, const godot::StringName &p_tracker_name, double p_frequency, double p_amplitude, double p_duration_sec, double p_delay_sec) {
	Controller *controller = controller_for_tracker(p_tracker_name);
	if (controller == nullptr || controller->gc_controller == nullptr) {
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
													  value:(float)p_amplitude],
		[[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness
													  value:sharpness],
	];

	CHHapticEventType event_type = p_duration_sec > 0.0 ? CHHapticEventTypeHapticContinuous : CHHapticEventTypeHapticTransient;
	CHHapticEvent *event = [[CHHapticEvent alloc] initWithEventType:event_type
														 parameters:params
													   relativeTime:p_delay_sec
														   duration:p_duration_sec];

	NSError *error = nil;
	CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[ event ] parameters:@[] error:&error];
	if (pattern == nil) {
		return;
	}

	id<CHHapticPatternPlayer> player = [engine createPlayerWithPattern:pattern error:&error];
	if (player == nil) {
		return;
	}

	[player startAtTime:0 error:&error];
}

} // namespace gdrk

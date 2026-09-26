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

#ifndef CONTROLLER_XR_INTERFACE_H
#define CONTROLLER_XR_INTERFACE_H

#undef check
#include "window_haptic_mixer.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/xr_controller_tracker.hpp>
#include <godot_cpp/classes/xr_interface_extension.hpp>
#include <godot_cpp/classes/xr_pose.hpp>
#include <godot_cpp/classes/xr_positional_tracker.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <array>
#include <map>
#include <string>

namespace gdrk {

// Publishes the spatial controllers' poses as Godot controller trackers.
// A shared volume has no compositor services session, so the engine's visionOS interface
// cannot run its ARKit accessory provider there. The Swift bridge owns one shared
// ARKit provider and converts its anchors into each volume root coordinate space.
// Main-volume trackers retain left_hand/right_hand; extra volumes use scoped names.
// This interface only tracks: it renders nothing and reports no capabilities.
class RealityControllerXRInterface : public godot::XRInterfaceExtension {
	GDCLASS(RealityControllerXRInterface, XRInterfaceExtension);

protected:
	static void _bind_methods();

public:
	static const char *interface_name;
	void log_diagnostic(const godot::String &p_message) const;

	// The initialized instance, or null when the interface isn't running. Poses pushed while
	// this is null are dropped, which is what keeps accessory tracking off outside a shared
	// volume and when controller tracking is disabled (see RealitySceneTree::_initialize).
	static RealityControllerXRInterface *get_active() { return active; }

	godot::StringName _get_name() const override;
	uint32_t _get_capabilities() const override;
	bool _is_initialized() const override;
	bool _initialize() override;
	void _uninitialize() override;
	godot::XRInterface::TrackingStatus _get_tracking_status() const override;
	godot::PackedStringArray _get_suggested_tracker_names() const override;
	void _trigger_haptic_pulse(const godot::String &p_action_name, const godot::StringName &p_tracker_name, double p_frequency, double p_amplitude, double p_duration_sec, double p_delay_sec) override;
	void _process() override;

	// Called from the RealityKit bridge with a controller's accessory anchor transform, in
	// scene-root-local space. Buffered until the next _process() so that poses reach the
	// trackers at a consistent point in the frame.
	void set_anchor_pose(godot::XRPositionalTracker::TrackerHand p_hand,
			const godot::Transform3D &p_pose,
			bool p_tracked, uint64_t p_window = 0);
	void suspend_volume(uint64_t p_id);
	void remove_volume(uint64_t p_id);
	godot::StringName tracker_for_volume(int64_t p_id, const godot::String &p_hand);
	bool is_controller_connected(const godot::String &p_hand) const;
	godot::PackedStringArray get_supported_inputs(const godot::String &p_hand) const;
	godot::PackedStringArray get_supported_poses(const godot::String &p_hand) const;
	bool supports_haptics(const godot::String &p_hand) const;
	void set_tracking_state(bool p_running, const godot::String &p_error);
	void set_named_pose(uint64_t p_volume, bool p_left, const godot::StringName &p_name, const godot::Transform3D &p_pose,
			const godot::Vector3 &p_velocity, const godot::Vector3 &p_angular, int p_confidence, bool p_supported);
	godot::StringName tracker_for_node(godot::Node *p_node, const godot::String &p_hand);

	// A spatial controller's button / thumbstick state, sampled from GCController by the bridge.
	struct ControllerInput {
		float trigger = 0.0f;
		bool trigger_click = false;
		float grip = 0.0f;
		bool grip_click = false;
		bool primary_button = false; // A / X
		bool secondary_button = false; // B / Y
		bool menu_button = false;
		godot::Vector2 thumbstick;
		bool thumbstick_click = false;
		bool trigger_touch = false, grip_touch = false, primary_touch = false, ax_touch = false, by_touch = false;
		godot::PackedStringArray supported;
		godot::PackedStringArray poses;
		bool haptics = false;
	};

	// Called from the RealityKit bridge with a controller's latest input; published on the
	// tracker each _process() so XRController3D's button_pressed / get_input keep working.
	// p_gc_controller is the GCController backing this hand (see set_controller_input in
	// extension.mm), retained until replacement/disconnection to keep asynchronous haptic use safe.
	void set_controller_input(godot::XRPositionalTracker::TrackerHand p_hand,
			const ControllerInput &p_input,
			void *p_gc_controller);

private:
	struct Pose {
		godot::Transform3D transform;
		godot::Vector3 velocity, angular;
		godot::XRPose::TrackingConfidence confidence = godot::XRPose::XR_TRACKING_CONFIDENCE_NONE;
		bool supported = false;
	};
	struct Controller {
		godot::Ref<godot::XRControllerTracker> tracker;
		godot::Transform3D pose;
		std::map<godot::StringName, Pose> poses;
		bool suspended = false;
		bool tracked = false;
		double updated_at = 0.0;
		bool pose_published = false;
		ControllerInput input;
		bool has_input = false;
		void *gc_controller = nullptr; // Retained until replacement or disconnection.
		void *haptic_player = nullptr; // Retained CHHapticPatternPlayer, stopped on contact exit.
		void *haptic_engine = nullptr; // Retained CHHapticEngine *, created lazily.
	};

	static void publish(Controller &p_controller);
	Controller &window_controller(uint64_t p_window, bool p_left);
	void mix_haptics();
	void play_haptic_pulse(const godot::String &p_action_name, const godot::StringName &p_tracker_name, double p_frequency, double p_amplitude, double p_duration_sec, double p_delay_sec);
	std::map<uint64_t, std::array<Controller, 2>> windows;
	WindowHapticMixer mixer;
	std::array<double, 2> output_amplitude = {}, output_frequency = {}, output_renewal = {};

	// Maps a tracker name ("left_hand" / "right_hand") to its controller, or null if the name
	// doesn't match either. Used by _trigger_haptic_pulse, which only gets the tracker name.
	Controller *controller_for_tracker(const godot::StringName &p_tracker_name);

	static void *ensure_haptic_engine(Controller &p_controller);
	static void release_haptic_engine(Controller &p_controller);
	static void stop_haptic_player(Controller &p_controller);

	static RealityControllerXRInterface *active;

	bool initialized = false;
	bool provider_running = false;
	const Controller *physical_for_hand(const godot::String &p_hand) const;
	Controller left;
	Controller right;
};

} // namespace gdrk

#endif // CONTROLLER_XR_INTERFACE_H

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
#include <godot_cpp/classes/xr_controller_tracker.hpp>
#include <godot_cpp/classes/xr_interface_extension.hpp>
#include <godot_cpp/classes/xr_positional_tracker.hpp>

#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace gdrk {

// Publishes the spatial controllers' poses as Godot controller trackers.
// A shared volume has no compositor services session, so the engine's visionOS interface
// cannot run its ARKit accessory provider there. The RealityKit bridge anchors an
// AnchorEntity(.accessory) to each controller instead and pushes its scene-root-local
// transform here (see RealityKitBridge.swift); this interface republishes it on the standard
// "left_hand" / "right_hand" trackers, so XRController3D keeps working unchanged.
// This interface only tracks: it renders nothing and reports no capabilities.
class RealityControllerXRInterface : public godot::XRInterfaceExtension {
	GDCLASS(RealityControllerXRInterface, XRInterfaceExtension);

protected:
	static void _bind_methods() {}

public:
	static const char *interface_name;

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
			bool p_tracked);

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
	};

	// Called from the RealityKit bridge with a controller's latest input; published on the
	// tracker each _process() so XRController3D's button_pressed / get_input keep working.
	// p_gc_controller is the GCController backing this hand (see set_controller_input in
	// extension.mm), kept only to drive _trigger_haptic_pulse; not retained, since the bridge
	// keeps it alive for as long as it stays connected.
	void set_controller_input(godot::XRPositionalTracker::TrackerHand p_hand,
			const ControllerInput &p_input,
			void *p_gc_controller);

private:
	struct Controller {
		godot::Ref<godot::XRControllerTracker> tracker;
		godot::Transform3D pose;
		bool tracked = false;
		bool pose_published = false;
		ControllerInput input;
		bool has_input = false;
		void *gc_controller = nullptr; // Unretained GCController *, refreshed each frame.
		void *haptic_engine = nullptr; // Retained CHHapticEngine *, created lazily.
	};

	static void publish(Controller &p_controller);

	// Maps a tracker name ("left_hand" / "right_hand") to its controller, or null if the name
	// doesn't match either. Used by _trigger_haptic_pulse, which only gets the tracker name.
	Controller *controller_for_tracker(const godot::StringName &p_tracker_name);

	static void *ensure_haptic_engine(Controller &p_controller);
	static void release_haptic_engine(Controller &p_controller);

	static RealityControllerXRInterface *active;

	bool initialized = false;
	Controller left;
	Controller right;
};

} // namespace gdrk

#endif // CONTROLLER_XR_INTERFACE_H

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

#ifndef INPUT_EVENTS_H
#define INPUT_EVENTS_H

#undef check
#include <godot_cpp/classes/input_event_screen_drag.hpp>
#include <godot_cpp/classes/input_event_screen_touch.hpp>

namespace gdrk {

class InputEventSpatialTouch : public godot::InputEventScreenTouch {
	GDCLASS(InputEventSpatialTouch, InputEventScreenTouch)
protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("get_world_position"), &InputEventSpatialTouch::get_world_position);
		godot::ClassDB::bind_method(godot::D_METHOD("set_world_position", "world_position"), &InputEventSpatialTouch::set_world_position);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "world_position"), "set_world_position", "get_world_position");

		godot::ClassDB::bind_method(godot::D_METHOD("get_flag", "flag"), &InputEventSpatialTouch::get_flag);
		godot::ClassDB::bind_method(godot::D_METHOD("set_flag", "flag", "value"), &InputEventSpatialTouch::set_flag);
		ADD_PROPERTYI(godot::PropertyInfo(godot::Variant::BOOL, "has_selection_ray"), "set_flag", "get_flag", FLAG_HAS_SELECTION_RAY);
		ADD_PROPERTYI(godot::PropertyInfo(godot::Variant::BOOL, "has_input_device_pose"), "set_flag", "get_flag", FLAG_HAS_INPUT_DEVICE_POSE);
		ADD_PROPERTYI(godot::PropertyInfo(godot::Variant::BOOL, "has_chirality"), "set_flag", "get_flag", FLAG_HAS_CHIRALITY);

		godot::ClassDB::bind_method(godot::D_METHOD("get_selection_ray_origin"), &InputEventSpatialTouch::get_selection_ray_origin);
		godot::ClassDB::bind_method(godot::D_METHOD("set_selection_ray_origin", "selection_ray_origin"), &InputEventSpatialTouch::set_selection_ray_origin);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "selection_ray_origin"), "set_selection_ray_origin", "get_selection_ray_origin");

		godot::ClassDB::bind_method(godot::D_METHOD("get_selection_ray_direction"), &InputEventSpatialTouch::get_selection_ray_direction);
		godot::ClassDB::bind_method(godot::D_METHOD("set_selection_ray_direction", "selection_ray_direction"), &InputEventSpatialTouch::set_selection_ray_direction);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "selection_ray_direction"), "set_selection_ray_direction", "get_selection_ray_direction");

		godot::ClassDB::bind_method(godot::D_METHOD("get_input_device_pose_position"), &InputEventSpatialTouch::get_input_device_pose_position);
		godot::ClassDB::bind_method(godot::D_METHOD("set_input_device_pose_position", "input_device_pose_position"), &InputEventSpatialTouch::set_input_device_pose_position);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "input_device_pose_position"), "set_input_device_pose_position", "get_input_device_pose_position");

		godot::ClassDB::bind_method(godot::D_METHOD("get_input_device_pose_orientation"), &InputEventSpatialTouch::get_input_device_pose_orientation);
		godot::ClassDB::bind_method(godot::D_METHOD("set_input_device_pose_orientation", "input_device_pose_orientation"), &InputEventSpatialTouch::set_input_device_pose_orientation);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "input_device_pose_orientation"), "set_input_device_pose_orientation", "get_input_device_pose_orientation");

		godot::ClassDB::bind_method(godot::D_METHOD("get_chirality"), &InputEventSpatialTouch::get_chirality);
		godot::ClassDB::bind_method(godot::D_METHOD("set_chirality", "chirality"), &InputEventSpatialTouch::set_chirality);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "chirality"), "set_chirality", "get_chirality");

		BIND_ENUM_CONSTANT(FLAG_HAS_SELECTION_RAY);
		BIND_ENUM_CONSTANT(FLAG_HAS_INPUT_DEVICE_POSE);
		BIND_ENUM_CONSTANT(FLAG_HAS_CHIRALITY);
		BIND_ENUM_CONSTANT(FLAG_MAX);

		BIND_ENUM_CONSTANT(CHIRALITY_LEFT);
		BIND_ENUM_CONSTANT(CHIRALITY_RIGHT);
	}

public:
	godot::Vector3 get_world_position() const { return world_position; }
	void set_world_position(const godot::Vector3 &p_world_position) {
		world_position = p_world_position;
	}

	enum Flags {
		FLAG_HAS_SELECTION_RAY,
		FLAG_HAS_INPUT_DEVICE_POSE,
		FLAG_HAS_CHIRALITY,
		FLAG_MAX,
	};

	enum Chirality {
		CHIRALITY_LEFT,
		CHIRALITY_RIGHT,
	};

	bool get_flag(Flags p_flag) const { return flags[uint32_t(p_flag)]; }
	void set_flag(Flags p_flag, bool p_value) { flags[uint32_t(p_flag)] = p_value; }

	godot::Vector3 get_selection_ray_origin() const { return selection_ray_origin; }
	void set_selection_ray_origin(const godot::Vector3 &p_selection_ray_origin) {
		selection_ray_origin = p_selection_ray_origin;
	}

	godot::Vector3 get_selection_ray_direction() const { return selection_ray_direction; }
	void set_selection_ray_direction(const godot::Vector3 &p_selection_ray_direction) {
		selection_ray_direction = p_selection_ray_direction;
	}

	godot::Vector3 get_input_device_pose_position() const { return input_device_pose_position; }
	void set_input_device_pose_position(const godot::Vector3 &p_input_device_pose_position) {
		input_device_pose_position = p_input_device_pose_position;
	}

	godot::Quaternion get_input_device_pose_orientation() const { return input_device_pose_orientation; }
	void set_input_device_pose_orientation(const godot::Quaternion &p_input_device_pose_orientation) {
		input_device_pose_orientation = p_input_device_pose_orientation;
	}

	Chirality get_chirality() const { return chirality; }
	void set_chirality(Chirality p_chirality) { chirality = p_chirality; }

private:
	godot::Vector3 world_position;

	godot::Vector3 selection_ray_origin;
	godot::Vector3 selection_ray_direction;

	godot::Vector3 input_device_pose_position;
	godot::Quaternion input_device_pose_orientation;

	Chirality chirality = CHIRALITY_RIGHT;

	bool flags[FLAG_MAX] = {};
};

class InputEventSpatialDrag : public godot::InputEventScreenDrag {
	GDCLASS(InputEventSpatialDrag, InputEventScreenDrag)
protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("get_world_position"), &InputEventSpatialDrag::get_world_position);
		godot::ClassDB::bind_method(godot::D_METHOD("set_world_position", "world_position"), &InputEventSpatialDrag::set_world_position);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "world_position"), "set_world_position", "get_world_position");

		godot::ClassDB::bind_method(godot::D_METHOD("get_world_relative"), &InputEventSpatialDrag::get_world_relative);
		godot::ClassDB::bind_method(godot::D_METHOD("set_world_relative", "world_relative"), &InputEventSpatialDrag::set_world_relative);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "world_relative"), "set_world_relative", "get_world_relative");

		godot::ClassDB::bind_method(godot::D_METHOD("get_flag", "flag"), &InputEventSpatialDrag::get_flag);
		godot::ClassDB::bind_method(godot::D_METHOD("set_flag", "flag", "value"), &InputEventSpatialDrag::set_flag);
		ADD_PROPERTYI(godot::PropertyInfo(godot::Variant::BOOL, "has_selection_ray"), "set_flag", "get_flag",
				InputEventSpatialTouch::FLAG_HAS_SELECTION_RAY);
		ADD_PROPERTYI(godot::PropertyInfo(godot::Variant::BOOL, "has_input_device_pose"), "set_flag", "get_flag",
				InputEventSpatialTouch::FLAG_HAS_INPUT_DEVICE_POSE);
		ADD_PROPERTYI(godot::PropertyInfo(godot::Variant::BOOL, "has_chirality"), "set_flag", "get_flag",
				InputEventSpatialTouch::FLAG_HAS_CHIRALITY);

		godot::ClassDB::bind_method(godot::D_METHOD("get_selection_ray_origin"), &InputEventSpatialDrag::get_selection_ray_origin);
		godot::ClassDB::bind_method(godot::D_METHOD("set_selection_ray_origin", "selection_ray_origin"), &InputEventSpatialDrag::set_selection_ray_origin);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "selection_ray_origin"), "set_selection_ray_origin", "get_selection_ray_origin");

		godot::ClassDB::bind_method(godot::D_METHOD("get_selection_ray_direction"), &InputEventSpatialDrag::get_selection_ray_direction);
		godot::ClassDB::bind_method(godot::D_METHOD("set_selection_ray_direction", "selection_ray_direction"), &InputEventSpatialDrag::set_selection_ray_direction);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "selection_ray_direction"), "set_selection_ray_direction", "get_selection_ray_direction");

		godot::ClassDB::bind_method(godot::D_METHOD("get_input_device_pose_position"), &InputEventSpatialDrag::get_input_device_pose_position);
		godot::ClassDB::bind_method(godot::D_METHOD("set_input_device_pose_position", "input_device_pose_position"), &InputEventSpatialDrag::set_input_device_pose_position);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "input_device_pose_position"), "set_input_device_pose_position", "get_input_device_pose_position");

		godot::ClassDB::bind_method(godot::D_METHOD("get_input_device_pose_orientation"), &InputEventSpatialDrag::get_input_device_pose_orientation);
		godot::ClassDB::bind_method(godot::D_METHOD("set_input_device_pose_orientation", "input_device_pose_orientation"), &InputEventSpatialDrag::set_input_device_pose_orientation);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "input_device_pose_orientation"), "set_input_device_pose_orientation", "get_input_device_pose_orientation");

		godot::ClassDB::bind_method(godot::D_METHOD("get_chirality"), &InputEventSpatialDrag::get_chirality);
		godot::ClassDB::bind_method(godot::D_METHOD("set_chirality", "chirality"), &InputEventSpatialDrag::set_chirality);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::INT, "chirality"), "set_chirality", "get_chirality");
	}

public:
	godot::Vector3 get_world_position() const { return world_position; }
	void set_world_position(const godot::Vector3 &p_world_position) {
		world_position = p_world_position;
	}

	godot::Vector3 get_world_relative() const { return world_relative; }
	void set_world_relative(const godot::Vector3 &p_world_relative) {
		world_relative = p_world_relative;
	}

	bool get_flag(InputEventSpatialTouch::Flags p_flag) const { return flags[uint32_t(p_flag)]; }
	void set_flag(InputEventSpatialTouch::Flags p_flag, bool p_value) { flags[uint32_t(p_flag)] = p_value; }

	godot::Vector3 get_selection_ray_origin() const { return selection_ray_origin; }
	void set_selection_ray_origin(const godot::Vector3 &p_selection_ray_origin) {
		selection_ray_origin = p_selection_ray_origin;
	}

	godot::Vector3 get_selection_ray_direction() const { return selection_ray_direction; }
	void set_selection_ray_direction(const godot::Vector3 &p_selection_ray_direction) {
		selection_ray_direction = p_selection_ray_direction;
	}

	godot::Vector3 get_input_device_pose_position() const { return input_device_pose_position; }
	void set_input_device_pose_position(const godot::Vector3 &p_input_device_pose_position) {
		input_device_pose_position = p_input_device_pose_position;
	}

	godot::Quaternion get_input_device_pose_orientation() const { return input_device_pose_orientation; }
	void set_input_device_pose_orientation(const godot::Quaternion &p_input_device_pose_orientation) {
		input_device_pose_orientation = p_input_device_pose_orientation;
	}

	InputEventSpatialTouch::Chirality get_chirality() const { return chirality; }
	void set_chirality(InputEventSpatialTouch::Chirality p_chirality) {
		chirality = p_chirality;
	}

private:
	godot::Vector3 world_position;
	godot::Vector3 world_relative;

	godot::Vector3 selection_ray_origin;
	godot::Vector3 selection_ray_direction;

	godot::Vector3 input_device_pose_position;
	godot::Quaternion input_device_pose_orientation;

	InputEventSpatialTouch::Chirality chirality = InputEventSpatialTouch::CHIRALITY_RIGHT;

	bool flags[InputEventSpatialTouch::FLAG_MAX] = {};
};

} //namespace gdrk

VARIANT_ENUM_CAST(gdrk::InputEventSpatialTouch::Flags)
VARIANT_ENUM_CAST(gdrk::InputEventSpatialTouch::Chirality)

#endif // INPUT_EVENTS_H

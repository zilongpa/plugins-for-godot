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

//  directional_light_shadow_3d.mm
//  GodotRealityKit
#include "directional_light_shadow_3d.h"
#include <godot_cpp/variant/utility_functions.hpp>
#include <iostream>

namespace gdrk {

void RealityKitDirectionalLightShadow3D::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("get_z_near"), &RealityKitDirectionalLightShadow3D::get_z_near);
	godot::ClassDB::bind_method(godot::D_METHOD("set_z_near", "z_near"), &RealityKitDirectionalLightShadow3D::set_z_near);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::FLOAT, "z_near",
						 godot::PROPERTY_HINT_RANGE, "0.001,10.0,0.001,or_greater"),
			"set_z_near", "get_z_near");

	godot::ClassDB::bind_method(godot::D_METHOD("get_z_far"), &RealityKitDirectionalLightShadow3D::get_z_far);
	godot::ClassDB::bind_method(godot::D_METHOD("set_z_far", "z_far"), &RealityKitDirectionalLightShadow3D::set_z_far);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::FLOAT, "z_far",
						 godot::PROPERTY_HINT_RANGE, "0.01,2000.0,0.01,or_greater"),
			"set_z_far", "get_z_far");

	godot::ClassDB::bind_method(godot::D_METHOD("get_orthographic_scale"), &RealityKitDirectionalLightShadow3D::get_orthographic_scale);
	godot::ClassDB::bind_method(godot::D_METHOD("set_orthographic_scale", "orthographic_scale"), &RealityKitDirectionalLightShadow3D::set_orthographic_scale);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::FLOAT, "orthographic_scale",
						 godot::PROPERTY_HINT_RANGE, "0.01,500.0,0.01,or_greater"),
			"set_orthographic_scale", "get_orthographic_scale");

	godot::ClassDB::bind_method(godot::D_METHOD("get_depth_bias"), &RealityKitDirectionalLightShadow3D::get_depth_bias);
	godot::ClassDB::bind_method(godot::D_METHOD("set_depth_bias", "depth_bias"), &RealityKitDirectionalLightShadow3D::set_depth_bias);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::FLOAT, "depth_bias",
						 godot::PROPERTY_HINT_RANGE, "0.0,10.0,0.001,or_greater"),
			"set_depth_bias", "get_depth_bias");
}

void RealityKitDirectionalLightShadow3D::_notification(int p_what) {
	if (!godot::Engine::get_singleton()->is_editor_hint()) {
		return;
	}
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE:
			set_notify_transform(true);
		case NOTIFICATION_PARENTED:
		case NOTIFICATION_UNPARENTED:
			update_configuration_warnings();
			break;
		case NOTIFICATION_TRANSFORM_CHANGED:
			_apply_transform_to_parent();
			break;
	}
}

void RealityKitDirectionalLightShadow3D::_apply_transform_to_parent() {
	auto *parent = godot::Object::cast_to<godot::DirectionalLight3D>(get_parent());
	if (!parent) {
		update_configuration_warnings();
		return;
	}
	godot::Transform3D local = get_transform();
	if (local == godot::Transform3D()) {
		update_configuration_warnings();
		return;
	}
	set_transform(godot::Transform3D());
	parent->set_transform(parent->get_transform() * local);
}

godot::PackedStringArray RealityKitDirectionalLightShadow3D::_get_configuration_warnings() const {
	godot::PackedStringArray warnings = Node3D::_get_configuration_warnings();
	if (!godot::Object::cast_to<godot::DirectionalLight3D>(get_parent())) {
		warnings.push_back("This node must be a direct child of a DirectionalLight3D node.");
	}
	if (get_transform() != godot::Transform3D()) {
		warnings.push_back("Transform must be Identity. This node's position and orientation are ignored at runtime.");
	}
	return warnings;
}

} // namespace gdrk

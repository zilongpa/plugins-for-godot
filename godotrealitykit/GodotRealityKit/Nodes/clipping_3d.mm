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

#import "clipping_3d.h"

#include <godot_cpp/classes/engine.hpp>

namespace gdrk {

void RealityClipping3D::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("get_size"), &RealityClipping3D::get_size);
	godot::ClassDB::bind_method(godot::D_METHOD("set_size", "size"), &RealityClipping3D::set_size);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "size"), "set_size", "get_size");

	godot::ClassDB::bind_method(godot::D_METHOD("get_feather_enabled"), &RealityClipping3D::get_feather_enabled);
	godot::ClassDB::bind_method(godot::D_METHOD("set_feather_enabled", "feather_enabled"), &RealityClipping3D::set_feather_enabled);

	godot::ClassDB::bind_method(godot::D_METHOD("get_feather_inset"), &RealityClipping3D::get_feather_inset);
	godot::ClassDB::bind_method(godot::D_METHOD("set_feather_inset", "feather_inset"), &RealityClipping3D::set_feather_inset);

	godot::ClassDB::bind_method(godot::D_METHOD("get_feather_falloff"), &RealityClipping3D::get_feather_falloff);
	godot::ClassDB::bind_method(godot::D_METHOD("set_feather_falloff", "feather_falloff"), &RealityClipping3D::set_feather_falloff);

	ADD_GROUP("Feathered Edge", "feather_");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::BOOL, "feather_enabled", godot::PROPERTY_HINT_GROUP_ENABLE), "set_feather_enabled", "get_feather_enabled");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "feather_inset"), "set_feather_inset", "get_feather_inset");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::INT, "feather_falloff", godot::PROPERTY_HINT_ENUM, "Linear,Cubic"), "set_feather_falloff", "get_feather_falloff");

	BIND_ENUM_CONSTANT(FALLOFF_LINEAR);
	BIND_ENUM_CONSTANT(FALLOFF_CUBIC);
}

} // namespace gdrk

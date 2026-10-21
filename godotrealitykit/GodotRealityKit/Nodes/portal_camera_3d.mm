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

#import "portal_camera_3d.h"

namespace gdrk {

void RealityPortalCamera3D::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("get_world_scale"), &RealityPortalCamera3D::get_world_scale);
	godot::ClassDB::bind_method(godot::D_METHOD("set_world_scale", "world_scale"), &RealityPortalCamera3D::set_world_scale);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::FLOAT, "world_scale", godot::PROPERTY_HINT_RANGE, "0,10,0.001,or_greater"), "set_world_scale", "get_world_scale");

	godot::ClassDB::bind_method(godot::D_METHOD("is_clipping_plane_enabled"), &RealityPortalCamera3D::is_clipping_plane_enabled);
	godot::ClassDB::bind_method(godot::D_METHOD("set_clipping_plane_enabled", "enabled"), &RealityPortalCamera3D::set_clipping_plane_enabled);
	godot::ClassDB::bind_method(godot::D_METHOD("get_clipping_plane_position"), &RealityPortalCamera3D::get_clipping_plane_position);
	godot::ClassDB::bind_method(godot::D_METHOD("set_clipping_plane_position", "position"), &RealityPortalCamera3D::set_clipping_plane_position);
	godot::ClassDB::bind_method(godot::D_METHOD("get_clipping_plane_normal"), &RealityPortalCamera3D::get_clipping_plane_normal);
	godot::ClassDB::bind_method(godot::D_METHOD("set_clipping_plane_normal", "normal"), &RealityPortalCamera3D::set_clipping_plane_normal);
	godot::ClassDB::bind_method(godot::D_METHOD("is_crossing_plane_enabled"), &RealityPortalCamera3D::is_crossing_plane_enabled);
	godot::ClassDB::bind_method(godot::D_METHOD("set_crossing_plane_enabled", "enabled"), &RealityPortalCamera3D::set_crossing_plane_enabled);
	godot::ClassDB::bind_method(godot::D_METHOD("get_crossing_plane_position"), &RealityPortalCamera3D::get_crossing_plane_position);
	godot::ClassDB::bind_method(godot::D_METHOD("set_crossing_plane_position", "position"), &RealityPortalCamera3D::set_crossing_plane_position);
	godot::ClassDB::bind_method(godot::D_METHOD("get_crossing_plane_normal"), &RealityPortalCamera3D::get_crossing_plane_normal);
	godot::ClassDB::bind_method(godot::D_METHOD("set_crossing_plane_normal", "normal"), &RealityPortalCamera3D::set_crossing_plane_normal);

	ADD_GROUP("Clipping Plane", "clipping_plane_");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::BOOL, "clipping_plane_enabled"), "set_clipping_plane_enabled", "is_clipping_plane_enabled");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "clipping_plane_position", godot::PROPERTY_HINT_NONE, "suffix:m"), "set_clipping_plane_position", "get_clipping_plane_position");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "clipping_plane_normal"), "set_clipping_plane_normal", "get_clipping_plane_normal");
	ADD_GROUP("Crossing Plane", "crossing_plane_");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::BOOL, "crossing_plane_enabled"), "set_crossing_plane_enabled", "is_crossing_plane_enabled");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "crossing_plane_position", godot::PROPERTY_HINT_NONE, "suffix:m"), "set_crossing_plane_position", "get_crossing_plane_position");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "crossing_plane_normal"), "set_crossing_plane_normal", "get_crossing_plane_normal");
}

} // namespace gdrk

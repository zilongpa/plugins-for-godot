#include "visionos_hover_style_2d.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

using namespace godot;

namespace godotvisionos {

void VisionOSHoverStyle2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &VisionOSHoverStyle2D::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &VisionOSHoverStyle2D::is_enabled);
	ClassDB::bind_method(D_METHOD("set_corner_radius", "radius"), &VisionOSHoverStyle2D::set_corner_radius);
	ClassDB::bind_method(D_METHOD("get_corner_radius"), &VisionOSHoverStyle2D::get_corner_radius);
	ClassDB::bind_method(D_METHOD("set_effect", "effect"), &VisionOSHoverStyle2D::set_effect);
	ClassDB::bind_method(D_METHOD("get_effect"), &VisionOSHoverStyle2D::get_effect);
	ClassDB::bind_method(D_METHOD("set_shape", "shape"), &VisionOSHoverStyle2D::set_shape);
	ClassDB::bind_method(D_METHOD("get_shape"), &VisionOSHoverStyle2D::get_shape);
	BIND_ENUM_CONSTANT(EFFECT_HIGHLIGHT);
	BIND_ENUM_CONSTANT(EFFECT_AUTOMATIC);
	BIND_ENUM_CONSTANT(EFFECT_LIFT);
	BIND_ENUM_CONSTANT(SHAPE_STYLEBOX);
	BIND_ENUM_CONSTANT(SHAPE_RECT);
	BIND_ENUM_CONSTANT(SHAPE_CAPSULE);
	BIND_ENUM_CONSTANT(SHAPE_CIRCLE);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "corner_radius", PROPERTY_HINT_RANGE, "-1,128,0.5,or_greater"), "set_corner_radius", "get_corner_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "effect", PROPERTY_HINT_ENUM, "Highlight,Automatic,Lift"), "set_effect", "get_effect");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "shape", PROPERTY_HINT_ENUM, "StyleBox,Rectangle,Capsule,Circle"), "set_shape", "get_shape");
}

void VisionOSHoverStyle2D::set_corner_radius(float p_radius) {
	if (std::isfinite(p_radius)) {
		corner_radius = p_radius < 0.0f ? -1.0f : p_radius;
	}
}

void VisionOSHoverStyle2D::set_effect(int p_effect) {
	if (p_effect >= EFFECT_HIGHLIGHT && p_effect <= EFFECT_LIFT) {
		effect = p_effect;
	}
}

void VisionOSHoverStyle2D::set_shape(int p_shape) {
	if (p_shape >= SHAPE_STYLEBOX && p_shape <= SHAPE_CIRCLE) {
		shape = p_shape;
	}
}

} // namespace godotvisionos

#include "uikit_hover_effect_2d.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <TargetConditionals.h>

using namespace godot;

namespace godotvisionos {

void UIKitHoverEffect2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &UIKitHoverEffect2D::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &UIKitHoverEffect2D::is_enabled);
	ClassDB::bind_method(D_METHOD("set_style", "style"), &UIKitHoverEffect2D::set_style);
	ClassDB::bind_method(D_METHOD("get_style"), &UIKitHoverEffect2D::get_style);
	ClassDB::bind_method(D_METHOD("is_supported"), &UIKitHoverEffect2D::is_supported);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "style", PROPERTY_HINT_RESOURCE_TYPE, "VisionOSHoverStyle2D"), "set_style", "get_style");
}

bool UIKitHoverEffect2D::is_supported() const {
#if TARGET_OS_VISION
	return !Engine::get_singleton()->is_editor_hint();
#else
	return false;
#endif
}

} // namespace godotvisionos

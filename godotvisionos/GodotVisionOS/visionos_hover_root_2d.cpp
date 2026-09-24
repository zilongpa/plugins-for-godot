#include "visionos_hover_root_2d.h"

#include "uikit_hover_effect_2d.h"

#include <godot_cpp/classes/base_button.hpp>
#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/item_list.hpp>
#include <godot_cpp/classes/line_edit.hpp>
#include <godot_cpp/classes/range.hpp>
#include <godot_cpp/classes/scroll_bar.hpp>
#include <godot_cpp/classes/scroll_container.hpp>
#include <godot_cpp/classes/slider.hpp>
#include <godot_cpp/classes/spin_box.hpp>
#include <godot_cpp/classes/style_box_flat.hpp>
#include <godot_cpp/classes/sub_viewport.hpp>
#include <godot_cpp/classes/tab_bar.hpp>
#include <godot_cpp/classes/text_edit.hpp>
#include <godot_cpp/classes/tree.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <TargetConditionals.h>

#include <cmath>

extern "C" void godotvisionos_hover_update(uint64_t, const void *, double, double, double, double, double, double, double, double, double, int32_t, int32_t);
extern "C" void godotvisionos_hover_remove(uint64_t);

using namespace godot;

namespace godotvisionos {

static bool is_auto_control(Control *p_control) {
	if (Object::cast_to<BaseButton>(p_control) || Object::cast_to<Slider>(p_control) || Object::cast_to<ScrollBar>(p_control) ||
			Object::cast_to<SpinBox>(p_control) || Object::cast_to<LineEdit>(p_control) || Object::cast_to<TextEdit>(p_control) ||
			Object::cast_to<TabBar>(p_control) || Object::cast_to<ScrollContainer>(p_control) ||
			Object::cast_to<ItemList>(p_control) || Object::cast_to<Tree>(p_control)) {
		return true;
	}
	return false;
}

bool VisionOSHoverRoot2D::NativeTarget::operator==(const NativeTarget &p_other) const {
	if (controller != p_other.controller || rect != p_other.rect || opacity != p_other.opacity || effect != p_other.effect || shape != p_other.shape) {
		return false;
	}
	for (int i = 0; i < 4; i++) {
		if (radii[i] != p_other.radii[i]) {
			return false;
		}
	}
	return true;
}

void VisionOSHoverRoot2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &VisionOSHoverRoot2D::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &VisionOSHoverRoot2D::is_enabled);
	ClassDB::bind_method(D_METHOD("is_supported"), &VisionOSHoverRoot2D::is_supported);
	ClassDB::bind_method(D_METHOD("get_active_target_count"), &VisionOSHoverRoot2D::get_active_target_count);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
}

void VisionOSHoverRoot2D::set_enabled(bool p_enabled) {
	enabled = p_enabled;
	if (!enabled) {
		clear_targets();
	}
}

bool VisionOSHoverRoot2D::is_supported() const {
#if TARGET_OS_VISION
	return !Engine::get_singleton()->is_editor_hint();
#else
	return false;
#endif
}

void VisionOSHoverRoot2D::_notification(int p_what) {
	if (p_what == NOTIFICATION_ENTER_TREE) {
		set_process(is_supported());
	} else if (p_what == NOTIFICATION_EXIT_TREE || p_what == NOTIFICATION_PAUSED) {
		clear_targets();
	}
}

void VisionOSHoverRoot2D::clear_targets() {
	for (const auto &entry : active) {
		godotvisionos_hover_remove(entry.first);
	}
	active.clear();
}

static UIKitHoverEffect2D *find_override(Control *p_control) {
	for (int i = 0; i < p_control->get_child_count(); i++) {
		if (auto *effect = Object::cast_to<UIKitHoverEffect2D>(p_control->get_child(i))) {
			return effect;
		}
	}
	return nullptr;
}

bool VisionOSHoverRoot2D::make_target(Control *p_control, Viewport *p_viewport, int64_t p_controller, NativeTarget &r_target) const {
	UIKitHoverEffect2D *override = find_override(p_control);
	if ((!override && !is_auto_control(p_control)) || (override && !override->is_enabled())) {
		return false;
	}
	Ref<VisionOSHoverStyle2D> style = override ? override->get_style() : Ref<VisionOSHoverStyle2D>();
	if (style.is_valid() && !style->is_enabled()) {
		return false;
	}
	if (!p_control->is_visible_in_tree() || p_control->get_mouse_filter_with_override() == Control::MOUSE_FILTER_IGNORE ||
			p_control->get_size().x <= 0 || p_control->get_size().y <= 0) {
		return false;
	}
	if (auto *button = Object::cast_to<BaseButton>(p_control)) {
		if (button->is_disabled()) {
			return false;
		}
	}
	const Transform2D transform = p_viewport->get_final_transform() * p_control->get_global_transform_with_canvas();
	if (!transform.is_finite() || !Math::is_zero_approx(transform[0].y) || !Math::is_zero_approx(transform[1].x) ||
			transform[0].x <= 0.0f || transform[1].y <= 0.0f) {
		return false;
	}
	Rect2 rect = transform.xform(Rect2(Vector2(), p_control->get_size()));
	Rect2 clip = p_viewport->get_final_transform().xform(p_viewport->get_visible_rect());
	float opacity = 1.0f;
	for (Node *ancestor = p_control; ancestor && ancestor != p_viewport; ancestor = ancestor->get_parent()) {
		if (auto *canvas = Object::cast_to<CanvasItem>(ancestor)) {
			opacity *= canvas->get_modulate().a * canvas->get_self_modulate().a;
		}
		if (auto *control = Object::cast_to<Control>(ancestor)) {
			if (control->is_clipping_contents()) {
				const Transform2D ancestor_transform = p_viewport->get_final_transform() * control->get_global_transform_with_canvas();
				if (!ancestor_transform.is_finite() || !Math::is_zero_approx(ancestor_transform[0].y) ||
						!Math::is_zero_approx(ancestor_transform[1].x)) {
					return false;
				}
				clip = clip.intersection(ancestor_transform.xform(Rect2(Vector2(), control->get_size())));
			}
		}
	}
	if (opacity <= 0.01f || !rect.has_area() || !clip.has_area()) {
		return false;
	}
	const Rect2 visible = rect.intersection(clip);
	if (visible != rect || !visible.has_area()) {
		// Partial clipping needs a custom path and exact hit mask. Hide rather than create a false gaze target.
		return false;
	}
	// Godot's own GUI picking order is authoritative for overlap, popups, and mouse filters.
	// The engine exposes this read-only query on the Apple Embedded build.
	if (!p_viewport->has_method("gui_find_control")) {
		return false;
	}
	const Vector2 size = p_control->get_size();
	const Vector2 samples[] = {
		Vector2(size.x * 0.5f, size.y * 0.5f),
		Vector2(size.x * 0.1f, size.y * 0.1f), Vector2(size.x * 0.9f, size.y * 0.1f),
		Vector2(size.x * 0.1f, size.y * 0.9f), Vector2(size.x * 0.9f, size.y * 0.9f),
	};
	for (const Vector2 &sample : samples) {
		Object *hit_object = p_viewport->call("gui_find_control", p_control->get_global_transform_with_canvas().xform(sample));
		Control *hit = Object::cast_to<Control>(hit_object);
		if (!hit || (hit != p_control && !p_control->is_ancestor_of(hit))) {
			return false;
		}
	}
	float radius = style.is_valid() ? style->get_corner_radius() : -1.0f;
	for (int i = 0; i < 4; i++) {
		r_target.radii[i] = radius >= 0.0f ? radius : 0.0f;
	}
	if (radius < 0.0f) {
		Ref<StyleBoxFlat> flat = p_control->get_theme_stylebox("normal");
		if (flat.is_valid()) {
			for (int i = 0; i < 4; i++) {
				r_target.radii[i] = flat->get_corner_radius(static_cast<Corner>(i));
			}
		}
	}
	const float scale = MIN(transform[0].x, transform[1].y);
	for (int i = 0; i < 4; i++) {
		r_target.radii[i] *= scale;
	}
	r_target.controller = p_controller;
	r_target.rect = rect;
	r_target.opacity = opacity;
	r_target.effect = style.is_valid() ? style->get_effect() : VisionOSHoverStyle2D::EFFECT_HIGHLIGHT;
	r_target.shape = style.is_valid() ? style->get_shape() : VisionOSHoverStyle2D::SHAPE_STYLEBOX;
	return true;
}

void VisionOSHoverRoot2D::scan(Node *p_node, Viewport *p_viewport, int64_t p_controller, std::unordered_set<uint64_t> &r_seen) {
	if (p_node != this && Object::cast_to<VisionOSHoverRoot2D>(p_node)) {
		return;
	}
	if (auto *control = Object::cast_to<Control>(p_node)) {
		if (control->get_viewport() != p_viewport) {
			return;
		}
		NativeTarget target;
		const uint64_t id = control->get_instance_id();
		if (make_target(control, p_viewport, p_controller, target)) {
			r_seen.insert(id);
			auto existing = active.find(id);
			if (existing == active.end() || !(existing->second == target)) {
				godotvisionos_hover_update(id, reinterpret_cast<const void *>(p_controller), target.rect.position.x, target.rect.position.y,
						target.rect.size.x, target.rect.size.y, target.radii[0], target.radii[1], target.radii[2], target.radii[3], target.opacity, target.effect, target.shape);
				active[id] = target;
			}
		}
	}
	for (int i = 0; i < p_node->get_child_count(); i++) {
		scan(p_node->get_child(i), p_viewport, p_controller, r_seen);
	}
}

void VisionOSHoverRoot2D::_process(double p_delta) {
	if (!enabled || !is_supported()) {
		clear_targets();
		return;
	}
	Node *root = get_parent();
	Viewport *viewport = root ? root->get_viewport() : nullptr;
	Window *window = root ? root->get_window() : nullptr;
	if (!root || !viewport || !window || Object::cast_to<SubViewport>(viewport)) {
		clear_targets();
		return;
	}
	const int64_t controller = DisplayServer::get_singleton()->window_get_native_handle(DisplayServer::WINDOW_HANDLE, window->get_window_id());
	if (!controller) {
		clear_targets();
		return;
	}
	std::unordered_set<uint64_t> seen;
	scan(root, viewport, controller, seen);
	for (auto it = active.begin(); it != active.end();) {
		if (seen.count(it->first) == 0) {
			godotvisionos_hover_remove(it->first);
			it = active.erase(it);
		} else {
			++it;
		}
	}
}

} // namespace godotvisionos

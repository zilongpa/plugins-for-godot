#include "visionos_hover_root_2d.h"

#include "uikit_hover_effect_2d.h"

#include <godot_cpp/classes/base_button.hpp>
#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/line_edit.hpp>
#include <godot_cpp/classes/scroll_bar.hpp>
#include <godot_cpp/classes/slider.hpp>
#include <godot_cpp/classes/spin_box.hpp>
#include <godot_cpp/classes/style_box_flat.hpp>
#include <godot_cpp/classes/sub_viewport.hpp>
#include <godot_cpp/classes/text_edit.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <TargetConditionals.h>

#include <atomic>
#include <cmath>

extern "C" void godotvisionos_hover_update(uint64_t, const void *, double, double, double, double, double, double, double, double, double, int32_t, int32_t);
extern "C" void godotvisionos_hover_remove(uint64_t);

using namespace godot;

namespace godotvisionos {

static bool is_auto_control(Control *p_control) {
	if (Object::cast_to<LineEdit>(p_control) && Object::cast_to<SpinBox>(p_control->get_parent())) {
		return false;
	}
	return Object::cast_to<BaseButton>(p_control) || Object::cast_to<Slider>(p_control) ||
			Object::cast_to<ScrollBar>(p_control) || Object::cast_to<SpinBox>(p_control) ||
			Object::cast_to<LineEdit>(p_control) || Object::cast_to<TextEdit>(p_control);
}

static bool is_axis_aligned(const Transform2D &p_transform) {
	return p_transform.is_finite() && Math::is_zero_approx(p_transform[0].y) &&
			Math::is_zero_approx(p_transform[1].x) && p_transform[0].x > 0.0f && p_transform[1].y > 0.0f;
}

static Rect2 offset_rect(Rect2 p_rect, const Vector2 &p_offset) {
	p_rect.position += p_offset;
	return p_rect;
}

static bool is_target_hit(Control *p_target, Viewport *p_viewport, const Vector2 &p_pixel) {
	const Vector2 point = p_viewport->get_final_transform().affine_inverse().xform(p_pixel);
	Control *hit = Object::cast_to<Control>(p_viewport->call("gui_find_control", point));
	return hit && (hit == p_target || p_target->is_ancestor_of(hit));
}

static bool has_foreground_overlap(Node *p_node, Control *p_target, Viewport *p_viewport, const Rect2 &p_visible) {
	if (p_node != p_viewport && Object::cast_to<Viewport>(p_node)) {
		return false;
	}
	if (auto *other = Object::cast_to<Control>(p_node)) {
		if (other != p_target && !other->is_ancestor_of(p_target) && !p_target->is_ancestor_of(other) &&
				other->is_visible_in_tree() && other->get_mouse_filter_with_override() != Control::MOUSE_FILTER_IGNORE) {
			const Transform2D transform = p_viewport->get_final_transform() * other->get_global_transform_with_canvas();
			if (transform.is_finite()) {
				const Rect2 overlap = p_visible.intersection(transform.xform(Rect2(Vector2(), other->get_size())));
				if (overlap.has_area() && !is_target_hit(p_target, p_viewport, overlap.get_center())) {
					return true;
				}
			}
		}
	}
	for (int i = 0; i < p_node->get_child_count(); i++) {
		if (has_foreground_overlap(p_node->get_child(i), p_target, p_viewport, p_visible)) {
			return true;
		}
	}
	return false;
}

static std::atomic<uint64_t> next_native_target_id{ 1 };

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
		godotvisionos_hover_remove(entry.second.native_id);
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

bool VisionOSHoverRoot2D::make_target(Control *p_control, Viewport *p_viewport, int64_t p_controller, const Vector2 &p_offset, const Rect2 &p_host_clip, NativeTarget &r_target) const {
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
	const Transform2D viewport_transform = p_viewport->get_final_transform();
	const Transform2D transform = viewport_transform * p_control->get_global_transform_with_canvas();
	if (!is_axis_aligned(viewport_transform) || !is_axis_aligned(transform)) {
		return false;
	}
	Rect2 rect = transform.xform(Rect2(Vector2(), p_control->get_size()));
	rect.position += p_offset;
	Rect2 clip = p_host_clip.intersection(offset_rect(viewport_transform.xform(p_viewport->get_visible_rect()), p_offset));
	float opacity = 1.0f;
	for (Node *ancestor = p_control; ancestor && ancestor != p_viewport; ancestor = ancestor->get_parent()) {
		if (auto *canvas = Object::cast_to<CanvasItem>(ancestor)) {
			opacity *= canvas->get_modulate().a;
		if (ancestor == p_control) {
			opacity *= canvas->get_self_modulate().a;
		}
		}
		if (auto *control = Object::cast_to<Control>(ancestor)) {
			if (control->is_clipping_contents()) {
				const Transform2D ancestor_transform = viewport_transform * control->get_global_transform_with_canvas();
				if (!is_axis_aligned(ancestor_transform)) {
					return false;
				}
				clip = clip.intersection(offset_rect(ancestor_transform.xform(Rect2(Vector2(), control->get_size())), p_offset));
			}
		}
		if (auto *canvas = Object::cast_to<CanvasItem>(ancestor)) {
			if (canvas->is_set_as_top_level()) {
				break;
			}
		}
	}
	if (opacity <= 0.01f || !rect.has_area() || !clip.has_area()) {
		return false;
	}
	const Rect2 visible = rect.intersection(clip);
	if (!visible.has_area() || !p_viewport->has_method("gui_find_control")) {
		return false;
	}
	const int shape = style.is_valid() ? style->get_shape() : VisionOSHoverStyle2D::SHAPE_STYLEBOX;
	if (visible != rect && shape != VisionOSHoverStyle2D::SHAPE_STYLEBOX && shape != VisionOSHoverStyle2D::SHAPE_RECT) {
		// A clipped circle, capsule, or system-defined shape cannot be represented by a smaller primitive.
		return false;
	}
	const Rect2 local_visible(visible.position - p_offset, visible.size);
	const TypedArray<Window> subwindows = p_viewport->get_embedded_subwindows();
	for (int i = 0; i < subwindows.size(); i++) {
		Window *subwindow = Object::cast_to<Window>(static_cast<Object *>(subwindows[i]));
		if (subwindow && subwindow->is_visible() && (Object::cast_to<PopupMenu>(subwindow) || Rect2(subwindow->get_position(), subwindow->get_size()).intersects(local_visible))) {
			return false;
		}
	}
	for (float y : { 0.02f, 0.5f, 0.98f }) {
		for (float x : { 0.02f, 0.5f, 0.98f }) {
			if (!is_target_hit(p_control, p_viewport, local_visible.position + local_visible.size * Vector2(x, y))) {
				return false;
			}
		}
	}
	if (has_foreground_overlap(p_viewport, p_control, p_viewport, local_visible)) {
		return false;
	}
	if (shape == VisionOSHoverStyle2D::SHAPE_STYLEBOX) {
		const float radius = style.is_valid() ? style->get_corner_radius() : -1.0f;
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
		if (visible != rect) {
			const bool left = Math::is_equal_approx(visible.position.x, rect.position.x);
			const bool top = Math::is_equal_approx(visible.position.y, rect.position.y);
			const bool right = Math::is_equal_approx(visible.get_end().x, rect.get_end().x);
			const bool bottom = Math::is_equal_approx(visible.get_end().y, rect.get_end().y);
			if (!left || !top) {
				r_target.radii[0] = 0.0f;
			}
			if (!right || !top) {
				r_target.radii[1] = 0.0f;
			}
			if (!right || !bottom) {
				r_target.radii[2] = 0.0f;
			}
			if (!left || !bottom) {
				r_target.radii[3] = 0.0f;
			}
		}
	}
	r_target.controller = p_controller;
	r_target.rect = visible;
	r_target.opacity = opacity;
	r_target.effect = style.is_valid() ? style->get_effect() : VisionOSHoverStyle2D::EFFECT_HIGHLIGHT;
	r_target.shape = shape;
	return true;
}

void VisionOSHoverRoot2D::track_target(const TargetKey &p_key, NativeTarget p_target, TargetSet &r_seen) {
	r_seen.insert(p_key);
	auto existing = active.find(p_key);
	p_target.native_id = existing == active.end() ? next_native_target_id.fetch_add(1, std::memory_order_relaxed) : existing->second.native_id;
	if (existing == active.end() || !(existing->second == p_target)) {
		godotvisionos_hover_update(p_target.native_id, reinterpret_cast<const void *>(p_target.controller), p_target.rect.position.x, p_target.rect.position.y,
				p_target.rect.size.x, p_target.rect.size.y, p_target.radii[0], p_target.radii[1], p_target.radii[2], p_target.radii[3], p_target.opacity, p_target.effect, p_target.shape);
		active[p_key] = p_target;
	}
}

void VisionOSHoverRoot2D::scan_popup(PopupMenu *p_popup, Viewport *p_host, int64_t p_controller, const Vector2 &p_offset, const Rect2 &p_host_clip, TargetSet &r_seen) {
	if (!p_popup->has_method("get_item_rect") || p_popup->is_native_menu()) {
		return;
	}
	const Transform2D transform = p_popup->get_final_transform();
	if (!is_axis_aligned(transform)) {
		return;
	}
	Ref<StyleBoxFlat> style = p_popup->get_theme_stylebox("hover", "PopupMenu");
	const TypedArray<Window> windows = p_host->get_embedded_subwindows();
	for (int i = 0; i < p_popup->get_item_count(); i++) {
		if (p_popup->is_item_disabled(i) || p_popup->is_item_separator(i)) {
			continue;
		}
		const Rect2 full = offset_rect(transform.xform(Rect2(p_popup->call("get_item_rect", i, false))), p_offset);
		const Rect2 visible = offset_rect(transform.xform(Rect2(p_popup->call("get_item_rect", i, true))), p_offset).intersection(p_host_clip);
		if (!visible.has_area()) {
			continue;
		}
		bool above_popup = false;
		bool occluded = false;
		for (int j = 0; j < windows.size(); j++) {
			Window *other = Object::cast_to<Window>(static_cast<Object *>(windows[j]));
			if (other == p_popup) {
				above_popup = true;
			} else if (above_popup && other && other->is_visible() && Rect2(other->get_position(), other->get_size()).intersects(visible)) {
				occluded = true;
				break;
			}
		}
		if (occluded) {
			continue;
		}
		NativeTarget target;
		target.controller = p_controller;
		target.rect = visible;
		if (style.is_valid() && visible == full) {
			for (int corner = 0; corner < 4; corner++) {
				target.radii[corner] = style->get_corner_radius(static_cast<Corner>(corner)) * MIN(transform[0].x, transform[1].y);
			}
		}
		track_target({ p_popup->get_instance_id(), i }, target, r_seen);
	}
}

void VisionOSHoverRoot2D::scan(Node *p_node, Viewport *p_viewport, int64_t p_controller, const Vector2 &p_offset, const Rect2 &p_host_clip, TargetSet &r_seen) {
	if (p_node != this && Object::cast_to<VisionOSHoverRoot2D>(p_node)) {
		return;
	}
	Vector2 offset = p_offset;
	if (auto *subwindow = Object::cast_to<Window>(p_node)) {
		if (subwindow != p_viewport) {
			if (!subwindow->is_visible() || !subwindow->is_embedded()) {
				return;
			}
			bool belongs_to_viewport = false;
			const TypedArray<Window> embedded = p_viewport->get_embedded_subwindows();
			for (int i = 0; i < embedded.size(); i++) {
				Window *candidate = Object::cast_to<Window>(static_cast<Object *>(embedded[i]));
				if (candidate == subwindow) {
					belongs_to_viewport = true;
					break;
				}
			}
			if (!belongs_to_viewport) {
				return;
			}
			offset += subwindow->get_position();
			if (auto *popup = Object::cast_to<PopupMenu>(subwindow)) {
				scan_popup(popup, p_viewport, p_controller, offset, p_host_clip, r_seen);
			}
			p_viewport = subwindow;
		}
	}
	if (auto *control = Object::cast_to<Control>(p_node)) {
		if (control->get_viewport() != p_viewport) {
			return;
		}
		NativeTarget target;
		if (make_target(control, p_viewport, p_controller, offset, p_host_clip, target)) {
			track_target({ control->get_instance_id(), -1 }, target, r_seen);
		}
	}
	for (int i = 0; i < p_node->get_child_count(); i++) {
		scan(p_node->get_child(i), p_viewport, p_controller, offset, p_host_clip, r_seen);
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
	if (!root || !viewport || !window || !window->is_visible() || Object::cast_to<SubViewport>(viewport)) {
		clear_targets();
		return;
	}
	const int64_t controller = DisplayServer::get_singleton()->window_get_native_handle(DisplayServer::WINDOW_HANDLE, window->get_window_id());
	if (!controller) {
		clear_targets();
		return;
	}
	TargetSet seen;
	const Rect2 host_clip = viewport->get_final_transform().xform(viewport->get_visible_rect());
	scan(root, viewport, controller, Vector2(), host_clip, seen);
	const TypedArray<Window> embedded = viewport->get_embedded_subwindows();
	for (int i = 0; i < embedded.size(); i++) {
		Window *subwindow = Object::cast_to<Window>(static_cast<Object *>(embedded[i]));
		// OptionButton owns an internal PopupMenu, which normal child traversal skips.
		if (subwindow && subwindow->is_visible()) {
			scan(subwindow, viewport, controller, Vector2(), host_clip, seen);
		}
	}
	for (auto it = active.begin(); it != active.end();) {
		if (seen.count(it->first) == 0) {
			godotvisionos_hover_remove(it->second.native_id);
			it = active.erase(it);
		} else {
			++it;
		}
	}
}

} // namespace godotvisionos

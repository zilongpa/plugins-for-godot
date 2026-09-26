#pragma once

#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/popup_menu.hpp>

#include <map>
#include <set>

namespace godotvisionos {

class VisionOSHoverRoot2D : public godot::Node {
	GDCLASS(VisionOSHoverRoot2D, godot::Node);

	struct NativeTarget {
		uint64_t native_id = 0;
		int64_t controller = 0;
		godot::Rect2 rect;
		float radii[4] = {};
		float opacity = 1.0f;
		int effect = 0;
		int shape = 0;
		bool operator==(const NativeTarget &p_other) const;
	};

	using TargetKey = std::pair<uint64_t, int>; // Control: -1; PopupMenu: item index.
	using TargetSet = std::set<TargetKey>;
	bool enabled = true;
	std::map<TargetKey, NativeTarget> active;

	void scan(godot::Node *p_node, godot::Viewport *p_viewport, int64_t p_controller, const godot::Vector2 &p_offset, const godot::Rect2 &p_host_clip, TargetSet &r_seen);
	bool make_target(godot::Control *p_control, godot::Viewport *p_viewport, int64_t p_controller, const godot::Vector2 &p_offset, const godot::Rect2 &p_host_clip, NativeTarget &r_target) const;
	void track_target(const TargetKey &p_key, NativeTarget p_target, TargetSet &r_seen);
	void scan_popup(godot::PopupMenu *p_popup, godot::Viewport *p_host, int64_t p_controller, const godot::Vector2 &p_offset, const godot::Rect2 &p_host_clip, TargetSet &r_seen);
	void clear_targets();

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	void _process(double p_delta) override;
	void set_enabled(bool p_enabled);
	bool is_enabled() const { return enabled; }
	bool is_supported() const;
	int32_t get_active_target_count() const { return static_cast<int32_t>(active.size()); }
};

} // namespace godotvisionos

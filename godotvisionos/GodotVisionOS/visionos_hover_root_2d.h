#pragma once

#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/node.hpp>

#include <unordered_map>
#include <unordered_set>

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

	bool enabled = true;
	std::unordered_map<uint64_t, NativeTarget> active;

	void scan(godot::Node *p_node, godot::Viewport *p_viewport, int64_t p_controller, const godot::Vector2 &p_offset, const godot::Rect2 &p_host_clip, std::unordered_set<uint64_t> &r_seen);
	bool make_target(godot::Control *p_control, godot::Viewport *p_viewport, int64_t p_controller, const godot::Vector2 &p_offset, const godot::Rect2 &p_host_clip, NativeTarget &r_target) const;
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

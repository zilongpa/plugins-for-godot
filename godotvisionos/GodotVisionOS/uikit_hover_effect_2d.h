#pragma once

#include "visionos_hover_style_2d.h"

#include <godot_cpp/classes/node.hpp>

namespace godotvisionos {

class UIKitHoverEffect2D : public godot::Node {
	GDCLASS(UIKitHoverEffect2D, godot::Node);

	bool enabled = true;
	godot::Ref<VisionOSHoverStyle2D> style;

protected:
	static void _bind_methods();

public:
	void set_enabled(bool p_enabled) { enabled = p_enabled; }
	bool is_enabled() const { return enabled; }
	void set_style(const godot::Ref<VisionOSHoverStyle2D> &p_style) { style = p_style; }
	godot::Ref<VisionOSHoverStyle2D> get_style() const { return style; }
	bool is_supported() const;
};

} // namespace godotvisionos

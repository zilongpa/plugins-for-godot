#pragma once

#include <godot_cpp/classes/resource.hpp>

namespace godotvisionos {

class VisionOSHoverStyle2D : public godot::Resource {
	GDCLASS(VisionOSHoverStyle2D, godot::Resource);

public:
	enum Effect {
		EFFECT_HIGHLIGHT,
		EFFECT_AUTOMATIC,
		EFFECT_LIFT,
	};
	enum Shape {
		SHAPE_STYLEBOX,
		SHAPE_RECT,
		SHAPE_CAPSULE,
		SHAPE_CIRCLE,
		SHAPE_SYSTEM,
	};

private:

	bool enabled = true;
	float corner_radius = -1.0f;
	int effect = EFFECT_HIGHLIGHT;
	int shape = SHAPE_STYLEBOX;

protected:
	static void _bind_methods();

public:
	void set_enabled(bool p_enabled) { enabled = p_enabled; }
	bool is_enabled() const { return enabled; }
	void set_corner_radius(float p_radius);
	float get_corner_radius() const { return corner_radius; }
	void set_effect(int p_effect);
	int get_effect() const { return effect; }
	void set_shape(int p_shape);
	int get_shape() const { return shape; }
};

} // namespace godotvisionos

VARIANT_ENUM_CAST(godotvisionos::VisionOSHoverStyle2D::Effect);
VARIANT_ENUM_CAST(godotvisionos::VisionOSHoverStyle2D::Shape);

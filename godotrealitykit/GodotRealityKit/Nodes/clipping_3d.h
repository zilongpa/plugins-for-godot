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

#ifndef CLIPPING_3D_H
#define CLIPPING_3D_H

#include <godot_cpp/classes/node3d.hpp>

namespace gdrk {

class RealityClipping3D : public godot::Node3D {
	GDCLASS(RealityClipping3D, Node3D)

protected:
	static void _bind_methods();

public:
	enum Falloff {
		FALLOFF_LINEAR,
		FALLOFF_CUBIC,
	};

	godot::Vector3 get_size() const { return size; }
	void set_size(const godot::Vector3 &p_size) {
		size = p_size;
		update_gizmos();
	}

	bool get_feather_enabled() const { return feather_enabled; }
	void set_feather_enabled(bool p_feather_enabled) {
		feather_enabled = p_feather_enabled;
		update_gizmos();
	}

	godot::Vector3 get_feather_inset() const { return feather_inset; }
	void set_feather_inset(const godot::Vector3 &p_feather_inset) {
		feather_inset = p_feather_inset;
		update_gizmos();
	}

	Falloff get_feather_falloff() const { return feather_falloff; }
	void set_feather_falloff(Falloff p_feather_falloff) { feather_falloff = p_feather_falloff; }

private:
	godot::Vector3 size = godot::Vector3(1, 1, 1);
	bool feather_enabled = false;
	godot::Vector3 feather_inset = godot::Vector3(0, 0, 0);
	Falloff feather_falloff = FALLOFF_LINEAR;
};

} // namespace gdrk

VARIANT_ENUM_CAST(gdrk::RealityClipping3D::Falloff);

#endif // CLIPPING_3D_H

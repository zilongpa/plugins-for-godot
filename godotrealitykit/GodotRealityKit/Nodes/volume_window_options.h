// Copyright © 2026 Apple Inc. Licensed under the MIT license.
#pragma once
#undef check
#include <godot_cpp/classes/resource.hpp>
namespace gdrk {
class RealityVolumeWindowOptions : public godot::Resource {
	GDCLASS(RealityVolumeWindowOptions, Resource);

public:
	enum ResizeMode { RESIZE_SYSTEM,
		RESIZE_FIXED,
		RESIZE_ENABLED };
	enum BaseplateVisibility { BASEPLATE_SYSTEM,
		BASEPLATE_VISIBLE,
		BASEPLATE_HIDDEN };

private:
	godot::Vector3 initial_size, minimum_size, maximum_size;
	int resize_mode = RESIZE_SYSTEM, baseplate_visibility = BASEPLATE_SYSTEM;

protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("set_initial_size", "value"), &RealityVolumeWindowOptions::set_initial_size);
		godot::ClassDB::bind_method(godot::D_METHOD("get_initial_size"), &RealityVolumeWindowOptions::get_initial_size);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "initial_size"), "set_initial_size", "get_initial_size");
		godot::ClassDB::bind_method(godot::D_METHOD("set_minimum_size", "value"), &RealityVolumeWindowOptions::set_minimum_size);
		godot::ClassDB::bind_method(godot::D_METHOD("get_minimum_size"), &RealityVolumeWindowOptions::get_minimum_size);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "minimum_size"), "set_minimum_size", "get_minimum_size");
		godot::ClassDB::bind_method(godot::D_METHOD("set_maximum_size", "value"), &RealityVolumeWindowOptions::set_maximum_size);
		godot::ClassDB::bind_method(godot::D_METHOD("get_maximum_size"), &RealityVolumeWindowOptions::get_maximum_size);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::VECTOR3, "maximum_size"), "set_maximum_size", "get_maximum_size");
		godot::ClassDB::bind_method(godot::D_METHOD("set_resize_mode", "value"), &RealityVolumeWindowOptions::set_resize_mode);
		godot::ClassDB::bind_method(godot::D_METHOD("get_resize_mode"), &RealityVolumeWindowOptions::get_resize_mode);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::INT, "resize_mode", godot::PROPERTY_HINT_ENUM, "System,Fixed,Enabled"), "set_resize_mode", "get_resize_mode");
		godot::ClassDB::bind_method(godot::D_METHOD("set_baseplate_visibility", "value"), &RealityVolumeWindowOptions::set_baseplate_visibility);
		godot::ClassDB::bind_method(godot::D_METHOD("get_baseplate_visibility"), &RealityVolumeWindowOptions::get_baseplate_visibility);
		ADD_PROPERTY(godot::PropertyInfo(godot::Variant::INT, "baseplate_visibility", godot::PROPERTY_HINT_ENUM, "System,Visible,Hidden"), "set_baseplate_visibility", "get_baseplate_visibility");

		BIND_ENUM_CONSTANT(RESIZE_SYSTEM);
		BIND_ENUM_CONSTANT(RESIZE_FIXED);
		BIND_ENUM_CONSTANT(RESIZE_ENABLED);
		BIND_ENUM_CONSTANT(BASEPLATE_SYSTEM);
		BIND_ENUM_CONSTANT(BASEPLATE_VISIBLE);
		BIND_ENUM_CONSTANT(BASEPLATE_HIDDEN);
	}

public:
	void set_initial_size(const godot::Vector3 &v) {
		ERR_FAIL_COND(!v.is_finite() || v.x < 0 || v.y < 0 || v.z < 0);
		initial_size = v;
	}
	godot::Vector3 get_initial_size() const { return initial_size; }
	void set_minimum_size(const godot::Vector3 &v) {
		ERR_FAIL_COND(!v.is_finite() || v.x < 0 || v.y < 0 || v.z < 0);
		minimum_size = v;
	}
	godot::Vector3 get_minimum_size() const { return minimum_size; }
	void set_maximum_size(const godot::Vector3 &v) {
		ERR_FAIL_COND(!v.is_finite() || v.x < 0 || v.y < 0 || v.z < 0);
		maximum_size = v;
	}
	godot::Vector3 get_maximum_size() const { return maximum_size; }

	void set_resize_mode(int v) {
		ERR_FAIL_COND(v < 0 || v > 2);
		resize_mode = v;
	}
	int get_resize_mode() const { return resize_mode; }
	void set_baseplate_visibility(int v) {
		ERR_FAIL_COND(v < 0 || v > 2);
		baseplate_visibility = v;
	}
	int get_baseplate_visibility() const { return baseplate_visibility; }
	bool is_valid() const {
		for (int i = 0; i < 3; ++i) {
			if (minimum_size[i] && maximum_size[i] && minimum_size[i] > maximum_size[i]) {
				return false;
			}
		}
		return true;
	}
	godot::Ref<RealityVolumeWindowOptions> snapshot() const {
		godot::Ref<RealityVolumeWindowOptions> copy;
		copy.instantiate();
		copy->initial_size = initial_size;
		copy->minimum_size = minimum_size;
		copy->maximum_size = maximum_size;
		copy->resize_mode = resize_mode;
		copy->baseplate_visibility = baseplate_visibility;
		return copy;
	}
};
} //namespace gdrk
VARIANT_ENUM_CAST(gdrk::RealityVolumeWindowOptions::ResizeMode);
VARIANT_ENUM_CAST(gdrk::RealityVolumeWindowOptions::BaseplateVisibility);

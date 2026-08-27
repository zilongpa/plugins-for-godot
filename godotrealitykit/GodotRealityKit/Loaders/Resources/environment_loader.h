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

#include "resource_loader.h"

#include <godot_cpp/classes/environment.hpp>

namespace gdrk {

/// Similar to `gdrk::TextureLoader` but
/// converting `godot::Environment` to `GodotRealityKit::EnvironmentResource`.
class EnvironmentLoader : public ResourceLoader<EnvironmentLoader> {
	GDCLASS(EnvironmentLoader, Object);

protected:
	static void _bind_methods() {}

public:
	void _reserve(uint32_t p_capacity) {
		ResourceLoader<EnvironmentLoader>::_reserve(p_capacity);
		environments.resize(p_capacity);
	}

	uint32_t find_or_add(godot::RID p_env_rid, godot::Ref<godot::Environment>);

	void remove(uint32_t p_idx) {
		environment_rid_to_idx.remove(environments[p_idx].environment->get_rid());
		godot::Environment *env = environments[p_idx].environment.ptr();
		if (env) {
			disconnect_changed(env, p_idx);
		}

		environments[p_idx] = Environment();
		free_idx(p_idx);
	}

	bool update();

	GodotRealityKit::EnvironmentResource find_resource(godot::RID p_env_rid) const {
		if (!p_env_rid.is_valid()) {
			return GodotRealityKit::EnvironmentResource::init();
		}

		ERR_FAIL_COND_V(!environment_rid_to_idx.has(p_env_rid), GodotRealityKit::EnvironmentResource::init());
		const uint32_t idx = environment_rid_to_idx.get(p_env_rid);
		return environments[idx].resource;
	}

	static float get_energy_multiplier(godot::Environment *);

	// RealityKit uses exponents of 2:
	// https://developer.apple.com/documentation/realitykit/imagebasedlightcomponent/intensityexponent
	static inline float get_energy_exponent(godot::Environment *p_env) {
		return log2(get_energy_multiplier(p_env));
	}

private:
	struct Environment {
		godot::Ref<godot::Environment> environment;
		GodotRealityKit::EnvironmentResource resource = GodotRealityKit::EnvironmentResource::init();
	};

	RID_Associated<uint32_t> environment_rid_to_idx;
	godot::LocalVector<Environment> environments;
};

} // namespace gdrk

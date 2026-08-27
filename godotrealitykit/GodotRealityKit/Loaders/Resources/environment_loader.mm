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

#include "environment_loader.h"
#include "constants.h"
#include "signposts.h"

#include <godot_cpp/classes/panorama_sky_material.hpp>
#include <godot_cpp/classes/sky.hpp>
#include <godot_cpp/classes/window.hpp>

#include "../Util/cgimage_util.h"

using namespace gdrk;

uint32_t EnvironmentLoader::find_or_add(godot::RID p_env_rid, godot::Ref<godot::Environment> p_env) {
	if (environment_rid_to_idx.has(p_env_rid)) {
		return environment_rid_to_idx.get(p_env_rid);
	}

	const uint32_t idx = alloc_idx();

	if (p_env.is_valid()) {
		connect_changed(p_env.ptr(), idx);
	}

	environments[idx] = Environment{
		.environment = p_env
	};

	environment_rid_to_idx.insert(p_env_rid, idx);
	mark_dirty(idx);
	return idx;
}

float EnvironmentLoader::get_energy_multiplier(godot::Environment *p_env) {
	if (p_env == nullptr) {
		return 1.0;
	}

	float bg_multiplier = p_env->get_bg_energy_multiplier();
	float sky_multiplier = 1.0;
	if (godot::Sky *sky = *p_env->get_sky()) {
		if (godot::PanoramaSkyMaterial *mat = godot::Object::cast_to<godot::PanoramaSkyMaterial>(*sky->get_material())) {
			sky_multiplier = mat->get_energy_multiplier();
		}
		// TODO: does "environment_bake_panorama" bake the "energy_multiplier" for ProceduralSkyMaterial and PhysicalSkyMaterial?
	}
	return sky_multiplier * bg_multiplier;
}

bool EnvironmentLoader::update() {
	PROFILE_FUNC_SCOPE;

	return for_each_dirty_throttled([&](uint32_t idx) {
		if (!is_used_in_frame(idx)) {
			return LocalBitVector::IterationResult::SKIPPED;
		}
		const godot::RID env_rid = environments[idx].environment->get_rid();
		ERR_FAIL_COND_V((!env_rid.is_valid()), LocalBitVector::IterationResult::SKIPPED);

		godot::Texture2D *panorama = nullptr;

		// Checking for image textures
		if (godot::Sky *sky = *environments[idx].environment->get_sky()) {
			if (godot::PanoramaSkyMaterial *mat = godot::Object::cast_to<godot::PanoramaSkyMaterial>(*sky->get_material())) {
				if (godot::Texture2D *texture = *mat->get_panorama()) {
					panorama = texture;
				}
			}
		}

		if (panorama) {
			const godot::RID texture_rid = panorama->get_rid();
			const godot::RID rd_texture_rid = rendering_server()->texture_get_rd_texture(texture_rid, true);
			const uint64_t mtl_texture_u64 = rendering_device()->get_driver_resource(godot::RenderingDevice::DRIVER_RESOURCE_TEXTURE, rd_texture_rid, 0);
			id<MTLTexture> src_texture = (__bridge id<MTLTexture>)(void *)mtl_texture_u64;

			environments[idx].resource.loadFromEquirectangularMTLTextureSync(src_texture);

		} else {
			// If it's not an image texture, render it
			godot::Vector2i size = godot::Vector2i(256, 128);

			// Force a viewport draw so the sky shader is rendered and the radiance texture
			// is populated before we bake. Without this, environment_bake_panorama reads from
			// an empty radiance texture because EnvironmentLoader::update() runs after the
			// frame's main draw pass (via GDExtensionManager::frame).
			godot::SceneTree *scene_tree = get_scene_tree();
			const godot::RID viewport_rid = scene_tree->get_root()->get_viewport_rid();
			rendering_server()->viewport_set_update_mode(viewport_rid, godot::RenderingServer::VIEWPORT_UPDATE_ONCE);
			rendering_server()->force_draw(false);

			// Note that the render server generates images in linear color space:
			// https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-sky-bake-panorama
			godot::Ref<godot::Image> image = rendering_server()->environment_bake_panorama(env_rid, false, size);

			// "environment_bake_panorama" only includes diffuse lighting in Godot.
			// TODO: also call "sky_bake_panorama" for reflections, and give it to RealityKit once it has an API for it
			

			CGImageRef cgimage = cgimage_from_godot_image(image);

			environments[idx].resource.loadFromEquirectangularCGImageSync(cgimage);

			CGImageRelease(cgimage);
		}
		return LocalBitVector::IterationResult::PROCESSED;
	});
}

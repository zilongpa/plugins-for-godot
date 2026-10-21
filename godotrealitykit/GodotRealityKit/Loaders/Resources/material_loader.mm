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

// clang-format off
#import "GodotRealityKit.h"
#import "GodotRealityKit-Swift.h"
// clang-format on

#include "material_loader.h"
#include "signposts.h"

#include "../resource_loaders.h"

#include "Materials/base_material_builder.h"
#include "Materials/material_bridge.h"

#include "types.h"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/visual_shader.hpp>

#include <godot_cpp/variant/utility_functions.hpp>

using namespace gdrk;

// Not used.
struct SamplerDescriptorTable {
	SamplerDescriptorTable() {
		const bool use_nearest_mipmap_filter =
				godot::ProjectSettings::get_singleton()->get_setting("rendering/textures/default_filters/use_nearest_mipmap_filter");

		const uint32_t anisotropic_filtering_level =
				godot::RenderingServer::ViewportAnisotropicFiltering::VIEWPORT_ANISOTROPY_4X;
		const float max_anisotropy = float(1 << anisotropic_filtering_level);
		MTLSamplerMipFilter mip_filter = use_nearest_mipmap_filter ? MTLSamplerMipFilterNearest : MTLSamplerMipFilterLinear;

		for (uint32_t filter_type_idx = 1; filter_type_idx < BM::TEXTURE_FILTER_MAX; filter_type_idx++) {
			for (bool repeat_enabled : { false, true }) {
				MTLSamplerDescriptor *descriptor = [MTLSamplerDescriptor new];
				switch (filter_type_idx) {
					case BM::TEXTURE_FILTER_NEAREST: {
						descriptor.magFilter = MTLSamplerMinMagFilterNearest;
						descriptor.minFilter = MTLSamplerMinMagFilterNearest;
						descriptor.lodMaxClamp = 0.0f;
					} break;
					case BM::TEXTURE_FILTER_LINEAR: {
						descriptor.magFilter = MTLSamplerMinMagFilterLinear;
						descriptor.minFilter = MTLSamplerMinMagFilterLinear;
						descriptor.lodMaxClamp = 0.0;
					} break;
					case BM::TEXTURE_FILTER_NEAREST_WITH_MIPMAPS: {
						descriptor.magFilter = MTLSamplerMinMagFilterNearest;
						descriptor.minFilter = MTLSamplerMinMagFilterNearest;
						descriptor.mipFilter = mip_filter;
					} break;
					case BM::TEXTURE_FILTER_LINEAR_WITH_MIPMAPS: {
						descriptor.magFilter = MTLSamplerMinMagFilterLinear;
						descriptor.minFilter = MTLSamplerMinMagFilterLinear;
						descriptor.mipFilter = mip_filter;
					} break;
					case BM::TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC: {
						descriptor.magFilter = MTLSamplerMinMagFilterNearest;
						descriptor.minFilter = MTLSamplerMinMagFilterNearest;
						descriptor.mipFilter = mip_filter;
						descriptor.maxAnisotropy = max_anisotropy;
					} break;
					case BM::TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC: {
						descriptor.magFilter = MTLSamplerMinMagFilterLinear;
						descriptor.minFilter = MTLSamplerMinMagFilterLinear;
						descriptor.mipFilter = mip_filter;
						descriptor.maxAnisotropy = max_anisotropy;
					} break;
					default: {
					}
				}

				if (repeat_enabled) {
					descriptor.sAddressMode = MTLSamplerAddressModeRepeat;
					descriptor.tAddressMode = MTLSamplerAddressModeRepeat;
					descriptor.rAddressMode = MTLSamplerAddressModeRepeat;
				} else {
					descriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
					descriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
					descriptor.rAddressMode = MTLSamplerAddressModeClampToEdge;
				}

				descriptors[repeat_enabled][filter_type_idx] = descriptor;
			}
		}
	}

	MTLSamplerDescriptor *get(godot::BaseMaterial3D::TextureFilter texture_filter, bool repeat_enabled) {
		return descriptors[repeat_enabled][texture_filter];
	}

private:
	using BM = godot::BaseMaterial3D;

	MTLSamplerDescriptor *descriptors[2][BM::TEXTURE_FILTER_MAX];
};

constexpr static TextureLoader::TextureUsage get_usage(const godot::BaseMaterial3D::TextureParam param) {
	switch (param) {
		case godot::BaseMaterial3D::TextureParam::TEXTURE_ALBEDO:
		case godot::BaseMaterial3D::TextureParam::TEXTURE_EMISSION:
		case godot::BaseMaterial3D::TextureParam::TEXTURE_DETAIL_ALBEDO:
			return TextureLoader::TextureUsage::Rendering;
		default:
			return TextureLoader::TextureUsage::Compute;
	}
}

#define TEXTURE(i, usage) p_textures.find_resource_and_mark_used(PARAM(i), usage)
#define COLOR(i) to_gdrk_color(PARAM(i))
#define PARAM(i) rs->material_get_param(p_material_rid, param_table[BaseMaterialParameter::i])

#define SET_BOOL(i) p_sgl_material.setBool(i, (bool)PARAM(i))
#define SET_FLOAT(i) p_sgl_material.setFloat(i, (float)PARAM(i))
#define SET_TEXTURE(i) p_sgl_material.setTexture(i, TEXTURE(i, get_usage(godot::BaseMaterial3D::TextureParam::i)))
#define SET_COLOR(i) p_sgl_material.setFloat4(i, to_vector4(((godot::Color)PARAM(i)).srgb_to_linear()))
#define SET_VECTOR2(i) p_sgl_material.setFloat2(i, to_vector2((godot::Vector2)PARAM(i)))
#define SET_VECTOR3(i) p_sgl_material.setFloat3(i, to_vector3((godot::Vector3)PARAM(i)))
#define SET_VECTOR4(i) p_sgl_material.setFloat4(i, to_vector4((godot::Vector3)PARAM(i)))

static uint32_t get_material_flags(const godot::BaseMaterial3D &p_material) {
	using BM = godot::BaseMaterial3D;
	uint32_t res = 0;
	for (uint32_t flag_idx = 0; flag_idx < BM::FLAG_MAX; flag_idx++) {
		res |= p_material.get_flag(BM::Flags(flag_idx)) << flag_idx;
	}

	return res;
}

static uint32_t get_material_features(const godot::BaseMaterial3D &p_material) {
	using BM = godot::BaseMaterial3D;
	uint32_t res = 0;
	for (uint32_t feature_idx = 0; feature_idx < BM::FEATURE_MAX; feature_idx++) {
		res |= p_material.get_feature(BM::Feature(feature_idx)) << feature_idx;
	}

	return res;
}

static void update_base_material3D(TextureLoader &p_textures, const ProgramDescription &p_desc, GodotRealityKit::SGLMaterial p_sgl_material, const godot::RID p_material_rid) {
	static const godot::StringName *param_table = BaseMaterialBuilder::get_godot_parameter_name_table();
	using BM = godot::BaseMaterial3D;

	const BaseMaterial3DDescription &d = p_desc.asBaseMaterial3D();
	godot::RenderingServer *rs = gdrk::rendering_server();

	SET_COLOR(ALBEDO);
	SET_TEXTURE(TEXTURE_ALBEDO);
	SET_FLOAT(METALLIC);
	SET_FLOAT(SPECULAR);
	SET_TEXTURE(TEXTURE_METALLIC);
	SET_FLOAT(ROUGHNESS);
	SET_TEXTURE(TEXTURE_ROUGHNESS);

	if (d.get_flag(BM::FLAG_UV1_USE_TRIPLANAR)) {
		SET_FLOAT(UV1_BLEND_SHARPNESS);
	}

	if (d.get_flag(BM::FLAG_UV2_USE_TRIPLANAR)) {
		SET_FLOAT(UV2_BLEND_SHARPNESS);
	}

	if (d.get_feature(BM::FEATURE_DETAIL)) {
		SET_TEXTURE(TEXTURE_DETAIL_ALBEDO);
		SET_TEXTURE(TEXTURE_DETAIL_NORMAL);
		SET_TEXTURE(TEXTURE_DETAIL_MASK);
	}

	if (d.get_feature(BM::FEATURE_EMISSION)) {
		SET_COLOR(EMISSION);
		SET_TEXTURE(TEXTURE_EMISSION);
		SET_FLOAT(EMISSION_ENERGY);
	}

	if (d.get_feature(BM::FEATURE_NORMAL_MAPPING)) {
		SET_TEXTURE(TEXTURE_NORMAL);
	}

	if (d.get_feature(BM::FEATURE_CLEARCOAT)) {
		SET_FLOAT(CLEARCOAT);
		SET_TEXTURE(TEXTURE_CLEARCOAT);
		SET_FLOAT(CLEARCOAT_ROUGHNESS);
	}

	if (d.get_feature(BM::FEATURE_ANISOTROPY)) {
		SET_FLOAT(ANISOTROPY);
	}

	if (d.get_feature(BM::FEATURE_AMBIENT_OCCLUSION)) {
		SET_TEXTURE(TEXTURE_AMBIENT_OCCLUSION);
	}

	SET_VECTOR3(UV1_SCALE);
	SET_VECTOR3(UV1_OFFSET);
	SET_VECTOR3(UV2_SCALE);
	SET_VECTOR3(UV2_OFFSET);

	if (d.distance_fade != BM::DISTANCE_FADE_DISABLED) {
		SET_FLOAT(DISTANCE_FADE_MIN);
		SET_FLOAT(DISTANCE_FADE_MAX);
	}

	if (d.transparency == BM::TRANSPARENCY_ALPHA_SCISSOR) {
		SET_FLOAT(ALPHA_SCISSOR_THRESHOLD);
	}
}
static void update_custom_material(TextureLoader &p_textures, const ProgramDescription &p_desc, GodotRealityKit::SGLMaterial p_sgl_material, const godot::ShaderMaterial &p_material) {
	const ShaderMaterialDescription &desc = p_desc.asShaderMaterial();
	int uniform_count = desc.uniforms.size();
	for (int i = 0; i < uniform_count; ++i) {
		const UniformDescriptor &uniform = desc.uniforms[i];
		godot::Variant value = p_material.get_shader_parameter(uniform.name);
		gdrk::update_material_parameter(i, uniform, p_sgl_material, value, p_textures);
	}
}

ProgramDescription MaterialLoader::program_description_for_material(const godot::Material &p_material, bool p_use_depth_postpass) {
	MaterialType type = gdrk::type_from_material(&p_material);
	if (type == MATERIAL_TYPE_BASE_MATERIAL3D) {
		godot::Ref<godot::Material> next_pass = p_material.get_next_pass();
		const godot::BaseMaterial3D &bm = (const godot::BaseMaterial3D &)p_material;
		return BaseMaterial3DDescription{
			.next_pass = next_pass.is_valid() ? next_pass->get_rid() : godot::RID(),
			.render_priority = bm.get_render_priority(),
			.shading_mode = bm.get_shading_mode(),
			.transparency = bm.get_transparency(),
			.blend_mode = bm.get_blend_mode(),
			.cull_mode = bm.get_cull_mode(),
			.depth_draw_mode = bm.get_depth_draw_mode(),
			.billboard_mode = bm.get_billboard_mode(),
			.texture_filter = bm.get_texture_filter(),
			.detail_blend_mode = bm.get_detail_blend_mode(),
			.detail_uv_layer = bm.get_detail_uv(),
			.distance_fade = bm.get_distance_fade(),
			.flags = get_material_flags(bm),
			.features = get_material_features(bm),
			.use_depth_postpass = p_use_depth_postpass,
		};
	} else if (type == MATERIAL_TYPE_SHADER_MATERIAL) {
		const godot::ShaderMaterial &sm = (const godot::ShaderMaterial &)p_material;
		const godot::Ref<godot::Shader> &shader = sm.get_shader();

		if (godot::Object::cast_to<godot::VisualShader>(shader.ptr())) {
			ShaderMaterialDescription desc(shader, sm.get_render_priority());
			desc.use_depth_postpass = p_use_depth_postpass;
			return desc;
		}

		const godot::String shader_path = shader.is_valid() ? shader->get_path() : godot::String();
		const godot::String alt_path = shader_path.get_basename() + ".visualshader.tres";

		if (!shader_path.is_empty() &&
				(godot::FileAccess::file_exists(alt_path) || godot::FileAccess::file_exists(alt_path + godot::String(".remap")))) {
			godot::Ref<godot::VisualShader> vs = godot::ResourceLoader::get_singleton()->load(alt_path);
			if (vs.is_valid()) {
				WARN_PRINT(godot::String("ShaderMaterial shader '") + shader_path + "' is not a VisualShader; loading sibling '" + alt_path + "' instead.");
				ShaderMaterialDescription desc(vs, sm.get_render_priority());
				desc.use_depth_postpass = p_use_depth_postpass;
				return desc;
			}
		}

		ERR_PRINT(godot::String("ShaderMaterial shader '") + shader_path + "' is not a VisualShader and no sibling '" + alt_path + "' was found; material will be broken.");
	}
	return ProgramDescription();
}

MaterialLoader::MaterialLoader() :
		program_cache([this](uint32_t p_index) {
			on_program_loaded(p_index);
		}) {
	default_material.instantiate();
	default_material_idx = find_or_add(default_material->get_rid(), default_material);
	reference(default_material_idx);
}

void MaterialLoader::update_description(uint32_t p_index) {
	Material &material = materials[p_index];
	// Description update is done directly by the Node managing the material
	if (material.material.is_null()) {
		return;
	}

	for (bool use_depth_postpass : { false, true }) {
		const uint32_t variant = variant_index(use_depth_postpass);
		if (!material.variants[variant].requested) {
			continue;
		}
		set_variant_description(p_index, variant, program_description_for_material(*material.material.ptr(), use_depth_postpass));
	}
}

void MaterialLoader::update_parameters(TextureLoader &p_textures, uint32_t p_index) {
	Material &material = materials[p_index];

	for (ProgramVariant &variant : material.variants) {
		if (!variant.requested) {
			continue;
		}

		const ProgramDescription &desc = variant.description;
		GodotRealityKit::SGLMaterial resource = variant.resource;

		if (desc.material_type == MATERIAL_TYPE_BASE_MATERIAL3D) {
			update_base_material3D(p_textures, desc, resource, material.material_rid);
		} else if (desc.material_type == MATERIAL_TYPE_SHADER_MATERIAL) {
			if (material.material.is_null()) {
				continue;
			}
			update_custom_material(p_textures, desc, resource, (godot::ShaderMaterial &)*material.material.ptr());
		}
	}
}

uint32_t MaterialLoader::find_or_add(godot::RID p_material_rid, godot::Ref<godot::Material> p_material, bool p_use_depth_postpass) {
	if (!p_material_rid.is_valid()) {
		return default_material_idx;
	}

	if (material_rid_to_idx.has(p_material_rid)) {
		const uint32_t idx = material_rid_to_idx.get(p_material_rid);
		if (get_ref_count(idx) == 0) {
			materials[idx].variants[0] = ProgramVariant();
			materials[idx].variants[1] = ProgramVariant();
			if (p_material.ptr()) {
				materials[idx].material = p_material;
			}
			mark_dirty(idx);
		}
		if (p_material.ptr()) {
			request_variant(idx, p_use_depth_postpass, *p_material.ptr());
		}
		return idx;
	}

	const uint32_t idx = alloc_idx();
	if (p_material.ptr()) {
		connect_changed(p_material.ptr(), idx);
	}

	materials[idx] = Material{
		.material_rid = p_material_rid,
		.material = p_material,
	};

	if (p_material.ptr()) {
		request_variant(idx, p_use_depth_postpass, *p_material.ptr());
	}

	material_rid_to_idx.insert(p_material_rid, idx);
	return idx;
}

void MaterialLoader::on_program_loaded(uint32_t p_program_index) {
	for_each_valid([this, p_program_index](uint32_t idx) {
		Material &mat = materials[idx];
		if (mat.variants[0].program_idx == p_program_index || mat.variants[1].program_idx == p_program_index) {
			mark_dirty(idx);
		}
	});
}

void MaterialLoader::update_deps(TextureLoader *p_textures) {
	PROFILE_FUNC_SCOPE;

	// Make sure that unreferenced materials are not active anymore
	remove_unreferenced();

	ChangedDependencyListSet changed_texture_deps = ChangedDependencyListSet(get_capacity());
	for_each_removed([&](uint32_t idx) {
		changed_texture_deps.mark_changed(idx);
		material_dep_states[idx].texture_hash = 0;
	});

	for_each_valid([&](uint32_t idx) {
		Material &material = materials[idx];

		bool any_variant_just_loaded = false;
		for (ProgramVariant &variant : material.variants) {
			if (!variant.requested) {
				continue;
			}

			// Process variants that just got requested, their program is unknown.
			if (variant.program_idx == UINT32_MAX) {
				const uint32_t program_idx = program_cache.create_program_async(variant.description);
				if (program_idx == UINT32_MAX) {
					ERR_PRINT("Unable to create program from description, using default material as fallback");
					const uint32_t default_idx = find_or_add(godot::RID(), nullptr);
					variant.program_idx = materials[default_idx].variants[0].program_idx;
					material.material = materials[default_idx].material;
				} else {
					variant.program_idx = program_idx;
				}

				mark_dirty(idx);
			}

			// Program is now known, if loaded, we can now create the Material instance
			// for it
			if (variant.program_idx != UINT32_MAX &&
					variant.resource.isLoading() &&
					!program_cache.is_program_loading(variant.program_idx)) {
				variant.resource = program_cache.create_material(variant.program_idx, material.material_rid);
				variant.description = program_cache.get_description(variant.program_idx);
				any_variant_just_loaded = true;
				mark_dirty(idx);
			}
		}

		if (any_variant_just_loaded) {
			if (const ProgramDescription *desc = get_requested_description(idx)) {
				update_default_texture_deps(p_textures, changed_texture_deps, idx, *desc);
			}
		}

		// Register textures set as material parameters.
		update_parameter_texture_deps(p_textures, changed_texture_deps, idx, materials[idx].material.ptr());
	});

	texture_deps.replace_changed(changed_texture_deps, p_textures);
}

void MaterialLoader::update_default_texture_deps(TextureLoader *p_textures, ChangedDependencyListSet &p_changed_texture_deps, uint32_t p_index, const ProgramDescription &p_desc) {
	const Material &material = materials[p_index];
	const godot::RID material_rid = material.material_rid;
	ERR_FAIL_COND(!material_rid.is_valid());
	if (p_desc.material_type == MATERIAL_TYPE_SHADER_MATERIAL) {
		p_desc.asShaderMaterial().for_each_texture_constants(([&](uint8_t handle, const UniformDescriptor &udesc) {
			godot::Texture2D *texture = godot::Object::cast_to<godot::Texture2D>((godot::Object *)udesc.default_value);
			if (!texture) {
				return;
			}
			const uint32_t texture_idx = p_textures->find_or_add(texture->get_rid(), texture, udesc.srgb_texture ? TextureLoader::TextureUsage::Rendering : TextureLoader::TextureUsage::Compute);
			p_changed_texture_deps.add_changed_dep(texture_idx, p_index);
			p_changed_texture_deps.mark_changed(p_index);
		}));
	}
}

void MaterialLoader::update_parameter_texture_deps(TextureLoader *p_textures, ChangedDependencyListSet &p_changed_texture_deps, uint32_t p_index, godot::Material *p_material) {
	static const godot::StringName *param_table = BaseMaterialBuilder::get_godot_parameter_name_table();

	const Material &material = materials[p_index];
	const godot::RID material_rid = material.material_rid;
	ERR_FAIL_COND(!material_rid.is_valid());
	const ProgramDescription *desc = get_requested_description(p_index);
	if (!desc) {
		return;
	}
	if (desc->material_type == MATERIAL_TYPE_BASE_MATERIAL3D) {
		godot::BaseMaterial3D *godot_material = godot::Object::cast_to<godot::BaseMaterial3D>(p_material);
		ERR_FAIL_COND(p_material && !godot_material);

		uint32_t texture_state = HASH_MURMUR3_SEED;
		const uint32_t texture_count = godot::BaseMaterial3D::TextureParam::TEXTURE_MAX;
		for (uint32_t texture_idx = 0; texture_idx < texture_count; texture_idx++) {
			const godot::RID texture_rid = rendering_server()->material_get_param(material_rid, param_table[BaseMaterialParameter::TEXTURE_ALBEDO + texture_idx]);
			if (texture_rid.is_valid()) {
				texture_state = godot::hash_murmur3_one_64(texture_rid.get_id(), texture_state);
			}
		}

		const uint32_t texture_hash = godot::hash_fmix32(texture_state);
		if (texture_hash != material_dep_states[p_index].texture_hash) {
			p_changed_texture_deps.mark_changed(p_index);

			for (uint32_t texture_idx = 0; texture_idx < texture_count; texture_idx++) {
				const godot::RID texture_rid = rendering_server()->material_get_param(material_rid, param_table[BaseMaterialParameter::TEXTURE_ALBEDO + texture_idx]);
				const auto texture_param = godot::BaseMaterial3D::TextureParam(texture_idx);
				godot::Texture2D *texture = p_material ? godot_material->get_texture(texture_param).ptr() : nullptr;
				if (texture_rid.is_valid()) {
					const uint32_t texture_idx = p_textures->find_or_add(texture_rid, texture, get_usage(texture_param));
					p_changed_texture_deps.add_changed_dep(texture_idx, p_index);
				}
			}

			material_dep_states[p_index].texture_hash = texture_hash;
		}
	} else if (desc->material_type == MATERIAL_TYPE_SHADER_MATERIAL) {
		desc->asShaderMaterial().for_each_texture_uniform(([&](uint8_t handle, const UniformDescriptor &udesc) {
			godot::ShaderMaterial *shader_material = (godot::ShaderMaterial *)p_material;
			godot::Variant value = shader_material->get_shader_parameter(udesc.name);
			if (value.get_type() != godot::Variant::OBJECT) {
				return;
			}
			godot::Object *obj = (godot::Object *)value;
			godot::Ref<godot::Texture> texture = godot::Object::cast_to<godot::Texture>(obj);
			if (texture.is_null()) {
				return;
			}

			const uint32_t texture_idx = p_textures->find_or_add((godot::RID)value, texture, udesc.srgb_texture ? TextureLoader::TextureUsage::Rendering : TextureLoader::TextureUsage::Compute);
			p_changed_texture_deps.add_changed_dep(texture_idx, p_index);
			p_changed_texture_deps.mark_changed(p_index);
		}));
	}
}

bool MaterialLoader::update(id<MTLCommandBuffer> p_command_buffer, TextureLoader *p_textures) {
	PROFILE_FUNC_SCOPE;

	for_each_valid([&](uint32_t idx) {
		if (!is_used_in_frame(idx)) {
			return;
		}
		update_parameters(*p_textures, idx);
	});

	return true;
}

void MaterialLoader::set_world_scale(float p_world_scale) {
	if (world_scale != p_world_scale) {
		for_each_valid([&](uint32_t idx) {
			for (ProgramVariant &variant : materials[idx].variants) {
				variant.resource.setWorldScale(p_world_scale);
			}
		});
		world_scale = p_world_scale;
	}
}

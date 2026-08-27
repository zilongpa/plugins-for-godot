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

#include "material_bridge.h"
#include "Loaders/Resources/texture_loader.h"
#import "bridge.h"
#include "snippets.h"
#include "utility.h"

using namespace gdrk;

const char *gdrk::port_type_name(PortType p_type) {
	static const char *names[PortType::PT_COUNT] = { 0 };
	if (!names[0]) {
#define FILL_NAME(name, value) names[PortType::name] = #value
		FILL_NAME(UNDEFINED, undefined);
		FILL_NAME(BOOL, int);
		FILL_NAME(INT, int);
		FILL_NAME(UINT, uint);
		FILL_NAME(FLOAT, float);
		FILL_NAME(VEC2F, float2);
		FILL_NAME(VEC3F, float3);
		FILL_NAME(VEC4F, float4);
		FILL_NAME(TRANSFORM3D, mat4x4);
		FILL_NAME(SAMPLER2D, asset);
		FILL_NAME(SAMPLER3D, asset);
		FILL_NAME(SAMPLER2DARRAY, asset);
	}

	return names[p_type];
}

PortType gdrk::get_swizzle_type(PortType p_type) {
	static PortType result[PortType::PT_COUNT];
	static bool initialized = false;
	if (!initialized) {
		result[PortType::BOOL] = PortType::UNDEFINED;
		result[PortType::INT] = PortType::UNDEFINED;
		result[PortType::UINT] = PortType::UNDEFINED;
		result[PortType::FLOAT] = PortType::UNDEFINED;

		result[PortType::VEC2F] = PortType::FLOAT;
		result[PortType::VEC3F] = PortType::FLOAT;
		result[PortType::VEC4F] = PortType::FLOAT;

		result[PortType::TRANSFORM3D] = PortType::UNDEFINED;
		result[PortType::SAMPLER2D] = PortType::UNDEFINED;
		result[PortType::SAMPLER3D] = PortType::UNDEFINED;
		result[PortType::SAMPLER2DARRAY] = PortType::UNDEFINED;

		initialized = true;
	}

	return result[p_type];
}

const char *gdrk::get_cast_function(PortType p_from, PortType p_to) {
	static const char *type_cast_matrix[PortType::PT_COUNT][PortType::PT_COUNT] = { { 0 } };
	static bool initialized = false;
	if (!initialized) {
		initialized = true;
		type_cast_matrix[PortType::UNDEFINED][PortType::UNDEFINED] = nullptr;
		type_cast_matrix[PortType::UNDEFINED][PortType::BOOL] = nullptr;
		type_cast_matrix[PortType::UNDEFINED][PortType::INT] = nullptr;
		type_cast_matrix[PortType::UNDEFINED][PortType::UINT] = nullptr;
		type_cast_matrix[PortType::UNDEFINED][PortType::FLOAT] = nullptr;
		type_cast_matrix[PortType::UNDEFINED][PortType::VEC2F] = nullptr;
		type_cast_matrix[PortType::UNDEFINED][PortType::VEC3F] = nullptr;
		type_cast_matrix[PortType::UNDEFINED][PortType::VEC4F] = nullptr;
		type_cast_matrix[PortType::UNDEFINED][PortType::TRANSFORM3D] = nullptr;
		type_cast_matrix[PortType::UNDEFINED][PortType::SAMPLER2D] = nullptr;
		type_cast_matrix[PortType::UNDEFINED][PortType::SAMPLER3D] = nullptr;
		type_cast_matrix[PortType::UNDEFINED][PortType::SAMPLER2DARRAY] = nullptr;

		type_cast_matrix[PortType::BOOL][PortType::BOOL] = "identity";
		type_cast_matrix[PortType::BOOL][PortType::INT] = "bool_to_int";
		type_cast_matrix[PortType::BOOL][PortType::UINT] = nullptr;
		type_cast_matrix[PortType::BOOL][PortType::FLOAT] = "bool_to_float";
		type_cast_matrix[PortType::BOOL][PortType::VEC2F] = "bool_to_vec2f";
		type_cast_matrix[PortType::BOOL][PortType::VEC3F] = "bool_to_vec3f";
		type_cast_matrix[PortType::BOOL][PortType::VEC4F] = "bool_to_vec4f";

		type_cast_matrix[PortType::INT][PortType::BOOL] = "int_to_bool";
		type_cast_matrix[PortType::INT][PortType::INT] = "identity";
		type_cast_matrix[PortType::INT][PortType::UINT] = nullptr;
		type_cast_matrix[PortType::INT][PortType::FLOAT] = "int_to_float";
		type_cast_matrix[PortType::INT][PortType::VEC2F] = "int_to_vec2f";
		type_cast_matrix[PortType::INT][PortType::VEC3F] = "int_to_vec3f";
		type_cast_matrix[PortType::INT][PortType::VEC4F] = "int_to_vec4f";

		
		type_cast_matrix[PortType::UINT][PortType::UNDEFINED] = nullptr;
		type_cast_matrix[PortType::UINT][PortType::BOOL] = nullptr;
		type_cast_matrix[PortType::UINT][PortType::INT] = nullptr;
		type_cast_matrix[PortType::UINT][PortType::UINT] = "identity";
		type_cast_matrix[PortType::UINT][PortType::FLOAT] = nullptr;
		type_cast_matrix[PortType::UINT][PortType::VEC2F] = nullptr;
		type_cast_matrix[PortType::UINT][PortType::VEC3F] = nullptr;
		type_cast_matrix[PortType::UINT][PortType::VEC4F] = nullptr;
		type_cast_matrix[PortType::UINT][PortType::TRANSFORM3D] = nullptr;
		type_cast_matrix[PortType::UINT][PortType::SAMPLER2D] = nullptr;
		type_cast_matrix[PortType::UINT][PortType::SAMPLER3D] = nullptr;
		type_cast_matrix[PortType::UINT][PortType::SAMPLER2DARRAY] = nullptr;

		type_cast_matrix[PortType::FLOAT][PortType::UNDEFINED] = nullptr;
		type_cast_matrix[PortType::FLOAT][PortType::BOOL] = "float_to_bool";
		type_cast_matrix[PortType::FLOAT][PortType::INT] = "float_to_int";
		type_cast_matrix[PortType::FLOAT][PortType::UINT] = nullptr;
		type_cast_matrix[PortType::FLOAT][PortType::FLOAT] = "identity";
		type_cast_matrix[PortType::FLOAT][PortType::VEC2F] = "float_to_vec2f";
		type_cast_matrix[PortType::FLOAT][PortType::VEC3F] = "float_to_vec3f";
		type_cast_matrix[PortType::FLOAT][PortType::VEC4F] = "float_to_vec4f";
		type_cast_matrix[PortType::FLOAT][PortType::TRANSFORM3D] = nullptr;
		type_cast_matrix[PortType::FLOAT][PortType::SAMPLER2D] = nullptr;
		type_cast_matrix[PortType::FLOAT][PortType::SAMPLER3D] = nullptr;
		type_cast_matrix[PortType::FLOAT][PortType::SAMPLER2DARRAY] = nullptr;

		type_cast_matrix[PortType::VEC2F][PortType::UNDEFINED] = nullptr;
		type_cast_matrix[PortType::VEC2F][PortType::BOOL] = "vec2f_to_bool";
		type_cast_matrix[PortType::VEC2F][PortType::INT] = "vec2f_to_int";
		type_cast_matrix[PortType::VEC2F][PortType::UINT] = nullptr;
		type_cast_matrix[PortType::VEC2F][PortType::FLOAT] = "vec2f_to_float";
		type_cast_matrix[PortType::VEC2F][PortType::VEC2F] = "identity";
		type_cast_matrix[PortType::VEC2F][PortType::VEC3F] = "vec2f_to_vec3f";
		type_cast_matrix[PortType::VEC2F][PortType::VEC4F] = "vec2f_to_vec4f";
		type_cast_matrix[PortType::VEC2F][PortType::TRANSFORM3D] = nullptr;
		type_cast_matrix[PortType::VEC2F][PortType::SAMPLER2D] = nullptr;
		type_cast_matrix[PortType::VEC2F][PortType::SAMPLER3D] = nullptr;
		type_cast_matrix[PortType::VEC2F][PortType::SAMPLER2DARRAY] = nullptr;

		type_cast_matrix[PortType::VEC3F][PortType::UNDEFINED] = nullptr;
		type_cast_matrix[PortType::VEC3F][PortType::BOOL] = "vec3f_to_bool";
		type_cast_matrix[PortType::VEC3F][PortType::INT] = "vec3f_to_int";
		type_cast_matrix[PortType::VEC3F][PortType::UINT] = nullptr;
		type_cast_matrix[PortType::VEC3F][PortType::FLOAT] = "vec3f_to_float";
		type_cast_matrix[PortType::VEC3F][PortType::VEC2F] = "vec3f_to_vec2f";
		type_cast_matrix[PortType::VEC3F][PortType::VEC3F] = "identity";
		type_cast_matrix[PortType::VEC3F][PortType::VEC4F] = "vec3f_to_vec4f";
		type_cast_matrix[PortType::VEC3F][PortType::TRANSFORM3D] = nullptr;
		type_cast_matrix[PortType::VEC3F][PortType::SAMPLER2D] = nullptr;
		type_cast_matrix[PortType::VEC3F][PortType::SAMPLER3D] = nullptr;
		type_cast_matrix[PortType::VEC3F][PortType::SAMPLER2DARRAY] = nullptr;

		type_cast_matrix[PortType::VEC4F][PortType::UNDEFINED] = nullptr;
		type_cast_matrix[PortType::VEC4F][PortType::BOOL] = "vec4f_to_bool";
		type_cast_matrix[PortType::VEC4F][PortType::INT] = "vec4f_to_int";
		type_cast_matrix[PortType::VEC4F][PortType::UINT] = nullptr;
		type_cast_matrix[PortType::VEC4F][PortType::FLOAT] = "vec4f_to_float";
		type_cast_matrix[PortType::VEC4F][PortType::VEC2F] = "vec4f_to_vec2f";
		type_cast_matrix[PortType::VEC4F][PortType::VEC3F] = "vec4f_to_vec3f";
		type_cast_matrix[PortType::VEC4F][PortType::VEC4F] = "identity";
		type_cast_matrix[PortType::VEC4F][PortType::TRANSFORM3D] = nullptr;
		type_cast_matrix[PortType::VEC4F][PortType::SAMPLER2D] = nullptr;
		type_cast_matrix[PortType::VEC4F][PortType::SAMPLER3D] = nullptr;
		type_cast_matrix[PortType::VEC4F][PortType::SAMPLER2DARRAY] = nullptr;
	}

	return type_cast_matrix[p_from][p_to];
}

std::string unsupported_variant_type(const godot::Variant &v) {
	return std::format("(UnsupportedType:{})", gdrk::to_std_string(v.stringify()));
}

std::string asset(const godot::Variant &) {
	return "@";
}

typedef std::string (*stringify_function)(const godot::Variant &);
static stringify_function functions[PortType::PT_COUNT] = { nullptr };
STATIC_INIT({
	functions[PortType::UNDEFINED] = &unsupported_variant_type;
	functions[PortType::BOOL] = &gdrk::sgl::boolean::value;
	functions[PortType::INT] = &gdrk::sgl::number::value<int>;
	functions[PortType::UINT] = &unsupported_variant_type;
	functions[PortType::FLOAT] = &gdrk::sgl::number::value<float>;
	functions[PortType::VEC2F] = &gdrk::sgl::vec2::value;
	functions[PortType::VEC3F] = &gdrk::sgl::vec3::value;
	functions[PortType::VEC4F] = &gdrk::sgl::vec4::value;
	functions[PortType::TRANSFORM3D] = &unsupported_variant_type;
	functions[PortType::SAMPLER2D] = &asset;
	functions[PortType::SAMPLER3D] = &asset;
	functions[PortType::SAMPLER2DARRAY] = &asset;
})

std::string gdrk::stringify_value(PortType p_port_type, const godot::Variant &p_value) {
	return functions[p_port_type](p_value);
}

template <PortType T>
static godot::Variant to_port_value(const godot::Variant &p_variant) {
	return p_variant;
}

template <>
godot::Variant to_port_value<PortType::BOOL>(const godot::Variant &p_variant) {
	return godot::Variant(p_variant.booleanize());
}

template <>
godot::Variant to_port_value<PortType::INT>(const godot::Variant &p_variant) {
	return (int32_t)p_variant;
}

template <>
godot::Variant to_port_value<PortType::UINT>(const godot::Variant &p_variant) {
	return (uint32_t)p_variant;
}

template <>
godot::Variant to_port_value<PortType::FLOAT>(const godot::Variant &p_variant) {
	return (float)p_variant;
}

template <>
godot::Variant to_port_value<PortType::VEC2F>(const godot::Variant &p_variant) {
	godot::Variant::Type godot_type = p_variant.get_type();
	if (godot_type == godot::Variant::QUATERNION) {
		godot::Quaternion value = (godot::Quaternion)p_variant;
		return godot::Vector2(value.x, value.y);
	}
	if (godot_type == godot::Variant::COLOR) {
		godot::Color value = ((godot::Color)p_variant).srgb_to_linear();
		return godot::Vector2(value.r, value.g);
	}
	return (godot::Vector2)p_variant;
}

template <>
godot::Variant to_port_value<PortType::VEC3F>(const godot::Variant &p_variant) {
	godot::Variant::Type godot_type = p_variant.get_type();
	if (godot_type == godot::Variant::QUATERNION) {
		godot::Quaternion value = (godot::Quaternion)p_variant;
		return godot::Vector3(value.x, value.y, value.z);
	}
	if (godot_type == godot::Variant::COLOR) {
		godot::Color value = ((godot::Color)p_variant).srgb_to_linear();
		return godot::Vector3(value.r, value.g, value.b);
	}
	return (godot::Vector3)p_variant;
}

template <>
godot::Variant to_port_value<PortType::VEC4F>(const godot::Variant &p_variant) {
	godot::Variant::Type godot_type = p_variant.get_type();
	if (godot_type == godot::Variant::QUATERNION) {
		godot::Quaternion value = (godot::Quaternion)p_variant;
		return godot::Vector4(value.x, value.y, value.z, value.w);
	}
	if (godot_type == godot::Variant::COLOR) {
		godot::Color value = ((godot::Color)p_variant).srgb_to_linear();
		return godot::Vector4(value.r, value.g, value.b, value.a);
	}
	return (godot::Vector4)p_variant;
}

DEFINE_ENUM_FUNCTION_TABLE(to_port_value_functions, PortType, PT_COUNT, to_port_value)
godot::Variant gdrk::to_port_value(PortType p_port_type, const godot::Variant &p_value) {
	return to_port_value_functions[p_port_type](p_value);
}

// pragma - update_parameters
template <PortType T>
void update_parameter(int index, const UniformDescriptor &p_uniform, GodotRealityKit::SGLMaterial &p_sgl_material, godot::Variant &value, TextureLoader &) {
	ERR_PRINT(std::format("Unsupported parameter type {} for parameter '{}'", gdrk::port_type_name(T), gdrk::to_std_string(p_uniform.name)).c_str());
	return;
}
template <> void update_parameter<PortType::BOOL>(int p_index, const UniformDescriptor &p_uniform, GodotRealityKit::SGLMaterial &p_sgl_material, godot::Variant &p_value, TextureLoader &) {
	p_sgl_material.setBool(p_index, (bool)p_value);
}
template <> void update_parameter<PortType::INT>(int p_index, const UniformDescriptor &p_uniform, GodotRealityKit::SGLMaterial &p_sgl_material, godot::Variant &p_value, TextureLoader &) {
	p_sgl_material.setInt(p_index, (int)p_value);
}
template <> void update_parameter<PortType::FLOAT>(int p_index, const UniformDescriptor &p_uniform, GodotRealityKit::SGLMaterial &p_sgl_material, godot::Variant &p_value, TextureLoader &) {
	p_sgl_material.setFloat(p_index, (float)p_value);
}
template <> void update_parameter<PortType::VEC2F>(int p_index, const UniformDescriptor &p_uniform, GodotRealityKit::SGLMaterial &p_sgl_material, godot::Variant &p_value, TextureLoader &) {
	godot::Vector2 vec = (godot::Vector2)p_value;
	p_sgl_material.setFloat2(p_index, GodotRealityKit::Vector2::init(vec.x, vec.y));
}
template <> void update_parameter<PortType::VEC3F>(int p_index, const UniformDescriptor &p_uniform, GodotRealityKit::SGLMaterial &p_sgl_material, godot::Variant &p_value, TextureLoader &) {
	godot::Vector3 vec = (godot::Vector3)p_value;
	p_sgl_material.setFloat3(p_index, GodotRealityKit::Vector3::init(vec.x, vec.y, vec.z));
}
template <> void update_parameter<PortType::VEC4F>(int p_index, const UniformDescriptor &p_uniform, GodotRealityKit::SGLMaterial &p_sgl_material, godot::Variant &p_value, TextureLoader &) {
	godot::Vector4 vec = (godot::Vector4)p_value;
	p_sgl_material.setFloat4(p_index, GodotRealityKit::Vector4::init(vec.x, vec.y, vec.z, vec.w));
}
template <> void update_parameter<PortType::SAMPLER2D>(int p_index, const UniformDescriptor &p_uniform, GodotRealityKit::SGLMaterial &p_sgl_material, godot::Variant &p_value, TextureLoader &p_textures) {
	godot::Texture *texture = godot::Object::cast_to<godot::Texture>((godot::Object *)p_value);
	godot::RID rid = texture ? texture->get_rid() : godot::RID();
	GodotRealityKit::TextureResource resource = p_textures.find_resource_and_mark_used(rid, p_uniform.srgb_texture ? TextureLoader::TextureUsage::Rendering : TextureLoader::TextureUsage::Compute);
	p_sgl_material.setTexture(p_index, resource);
}
DEFINE_ENUM_FUNCTION_TABLE(update_parameter_functions, PortType, PT_COUNT, update_parameter)
void update_parameter(PortType p_port_type, int p_index, const UniformDescriptor &p_uniform, GodotRealityKit::SGLMaterial &p_sgl_material, godot::Variant &p_value, TextureLoader &p_textures) {
	update_parameter_functions[p_port_type](p_index, p_uniform, p_sgl_material, p_value, p_textures);
}

void gdrk::update_material_parameter(int p_index, const UniformDescriptor &p_uniform, GodotRealityKit::SGLMaterial &p_sgl_material, godot::Variant &p_value, TextureLoader &p_textures) {
	if (p_value.get_type() == godot::Variant::Type::NIL) {
		p_value = p_uniform.default_value;
	} else {
		p_value = to_port_value(p_uniform.type, p_value);
	}
	update_parameter(p_uniform.type, p_index, p_uniform, p_sgl_material, p_value, p_textures);
}

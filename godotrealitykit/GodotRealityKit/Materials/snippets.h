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

#pragma once

#include <format>

#include "program_description.h"

#undef check
#include <godot_cpp/variant/variant.hpp>

namespace gdrk {
namespace sgl {

namespace statement {
inline std::string let(const std::string &var_name, const std::string &value) {
	return std::format("let {} = {};", var_name, value);
}
} //namespace statement

namespace builtin {
inline const char *constants() {
	return R"""(
		let v2_2 = (2.0f, 2.0f);
		let v2_1 = (1.0f, 1.0f);
		let v2_05 = (0.5f, 0.5f);
	    let M_PI = 3.1415926535f
	)""";
}

inline const char *utility_functions() {
	return R"""(
		let negate_float = { (v)in ND_multiply_float(v, -1.0f) };
		let identity = { (v)in v };
	)""";
}
inline const char *color_functions() {
	return R"""(
		let linear_to_srgb = { (c) in 
			  let clamped = ND_clamp_vector3(c, (0.0f, 0.0f, 0.0f), (1.0f, 1.0f, 1.0f));
			  let c_pow = ND_power_vector3FA(clamped, 0.4166667f);
			  let c_high = ND_subtract_vector3FA(ND_multiply_vector3FA(c_pow, 1.055f), 0.055f);
			  let c_low = ND_multiply_vector3FA(clamped, 12.92f);
			  ND_combine3_vector3(ND_ifgreater_float(v3_x(clamped), 0.0031308f, v3_x(c_high), v3_x(c_low)),
								  ND_ifgreater_float(v3_y(clamped), 0.0031308f, v3_y(c_high), v3_y(c_low)),
								  ND_ifgreater_float(v3_z(clamped), 0.0031308f, v3_z(c_high), v3_z(c_low)))
		};
		let srgb_to_linear = { (c) in
			  let c_scaled = ND_multiply_vector3FA(ND_add_vector3FA(c, 0.055f), 0.9478672985782f);
			  let c_high = ND_power_vector3FA(c_scaled, 2.4f);
			  let c_low = ND_multiply_vector3FA(c, 0.077399380804953f);
			  ND_combine3_vector3(ND_ifgreater_float(v3_x(c), 0.04045f, v3_x(c_high), v3_x(c_low)),
								  ND_ifgreater_float(v3_y(c), 0.04045f, v3_y(c_high), v3_y(c_low)),
								  ND_ifgreater_float(v3_z(c), 0.04045f, v3_z(c_high), v3_z(c_low)))
		};
	
		let srgb_to_linear_v4 = { (c) in
			let converted = srgb_to_linear(ND_swizzle_vector4_vector3(c, "xyz"));
			ND_combine4_vector4(v3_x(converted), v3_y(converted), v3_z(converted), v4_w(c))
		};

		let linear_to_srgb_v4 = { (c) in
			let converted = linear_to_srgb(ND_swizzle_vector4_vector3(c, "xyz"));
			ND_combine4_vector4(v3_x(converted), v3_y(converted), v3_z(converted), v4_w(c))
		};
	)""";
}

inline const char *swizzle() {
	return R"""(
	let v2_x = { (v)in ND_swizzle_vector2_float(v, "x") };
	let v2_y = { (v)in ND_swizzle_vector2_float(v, "y") };
 
	let v3_x = { (v)in ND_swizzle_vector3_float(v, "x") };
	let v3_y = { (v)in ND_swizzle_vector3_float(v, "y") };
	let v3_z = { (v)in ND_swizzle_vector3_float(v, "z") };
 
	let v3_xy = { (v)in ND_swizzle_vector3_vector2(v, "xy") };
	let v3_xz = { (v)in ND_swizzle_vector3_vector2(v, "xz") };
	let v3_zy = { (v)in ND_swizzle_vector3_vector2(v, "zy") };
	let v3_xy = { (v)in ND_swizzle_vector3_vector2(v, "xy") };
	let v3_xz = { (v)in ND_swizzle_vector3_vector2(v, "xz") };
	let v3_zy = { (v)in ND_swizzle_vector3_vector2(v, "zy") };
 
	let v4_x = { (v)in ND_swizzle_vector4_float(v, "x") };
	let v4_y = { (v)in ND_swizzle_vector4_float(v, "y") };
	let v4_z = { (v)in ND_swizzle_vector4_float(v, "z") };
	let v4_w = { (v)in ND_swizzle_vector4_float(v, "w") };
	let v4_xyz = { (v)in ND_swizzle_vector4_vector3(v, "xyz") };
 
	let c3_r = { (v)in ND_swizzle_color3_float(v, "r") };
	let c3_g = { (v)in ND_swizzle_color3_float(v, "g") };
	let c3_b = { (v)in ND_swizzle_color3_float(v, "b") };
 
	let c4_rgb = { (v)in ND_swizzle_color4_color3(v, "rgb") };
	let c4_xyz = { (v)in ND_swizzle_color4_vector3(v, "xyz") };
	let c4_a = { (v)in ND_swizzle_color4_float(v, "a") };

	let c3_r_half = { (v)in ND_swizzle_color3_half(v, "r") };
	let c3_g_half = { (v)in ND_swizzle_color3_half(v, "g") };
	let c3_b_half = { (v)in ND_swizzle_color3_half(v, "b") };
	let c4_r_half = { (v)in ND_swizzle_color4_half(v, "r") };
	let c4_g_half = { (v)in ND_swizzle_color4_half(v, "g") };
	let c4_b_half = { (v)in ND_swizzle_color4_half(v, "b") };
	let c4_a_half = { (v)in ND_swizzle_color4_half(v, "a") };
 )""";
}

#define DEFINE_BUILTIN_EXPRESSIONS(name)            \
	namespace name {                                \
	inline const char *tangent() {                  \
		return "ND_" #name "_vector3(\"tangent\")"; \
	}                                               \
	inline const char *object() {                   \
		return "ND_" #name "_vector3(\"object\")";  \
	}                                               \
	inline const char *model() {                    \
		return "ND_" #name "_vector3(\"model\")";   \
	}                                               \
	inline const char *world() {                    \
		return "ND_" #name "_vector3(\"world\")";   \
	}                                               \
	}

#define DEFINE_BUILTIN_DIRECTION_EXPRESSIONS(name)                                                                                                                                                                                                                  \
	DEFINE_BUILTIN_EXPRESSIONS(name)                                                                                                                                                                                                                                \
	namespace name {                                                                                                                                                                                                                                                \
	inline const char *view() {                                                                                                                                                                                                                                     \
		return "ND_normalize_vector3(v4_xyz(ND_multiply_matrix44_vector4(ND_realitykit_surface_world_to_view(), ND_combine4_vector4(v3_x(ND_" #name "_vector3(\"world\")), v3_y(ND_" #name "_vector3(\"world\")), v3_z(ND_" #name "_vector3(\"world\")), 0.0f))))"; \
	}                                                                                                                                                                                                                                                               \
	}

#define DEFINE_BUILTIN_POINT_EXPRESSIONS(name)                                                                                                                                                                                                \
	DEFINE_BUILTIN_EXPRESSIONS(name)                                                                                                                                                                                                          \
	namespace name {                                                                                                                                                                                                                          \
	inline const char *view() {                                                                                                                                                                                                               \
		return "v4_xyz(ND_multiply_matrix44_vector4(ND_realitykit_surface_world_to_view(), ND_combine4_vector4(v3_x(ND_" #name "_vector3(\"world\")), v3_y(ND_" #name "_vector3(\"world\")), v3_z(ND_" #name "_vector3(\"world\")), 1.0f)))"; \
	}                                                                                                                                                                                                                                         \
	}

DEFINE_BUILTIN_DIRECTION_EXPRESSIONS(normal)
DEFINE_BUILTIN_DIRECTION_EXPRESSIONS(tangent)
DEFINE_BUILTIN_DIRECTION_EXPRESSIONS(bitangent)
DEFINE_BUILTIN_POINT_EXPRESSIONS(position)

inline const char *time() {
	return "ND_time_float()";
}

inline const char *cast_declarations() {
	return R"""(
			let vec2f_to_vec2h = { (v) in ND_convert_vector2_half2(v) };
			let vec3f_to_vec3h = { (v) in ND_convert_vector3_half3(v) };
			let vec4f_to_vec4h = { (v) in ND_convert_vector4_half4(v) };

			let bool_to_float = { (v) in ND_convert_integer_float(v) };
			let bool_to_half = { (v)in ND_convert_integer_half(v) };
			let bool_to_int = { (v)in v };
			let bool_to_rgb = { (v)in let h = bool_to_half(v); ND_convert_half_color3(h) };
			let bool_to_rgba = { (v)in let h = bool_to_half(v); ND_convert_half_color3(h) };
			let bool_to_vec2h = { (v)in let h = bool_to_half(f); ND_combine2_half2(h, h) };
			let bool_to_vec3h = { (v)in let h = bool_to_half(f); ND_combine3_half3(h, h, h) };
			let bool_to_vec4h = { (v)in let h = bool_to_half(f); ND_combine4_half4(h, h, h, h) };
			let bool_to_vec2f = { (v)in let f = bool_to_float(v); ND_convert_float_vector2(f) };
			let bool_to_vec3f = { (v)in let f = bool_to_float(v); ND_convert_float_vector3(f) };
			let bool_to_vec4f = { (v)in let f = bool_to_float(v); ND_convert_float_vector4(f) };

			let int_to_float = { (v)in ND_convert_integer_float(v) };
			let int_to_half = { (v)in ND_convert_integer_half(v) };
			let int_to_bool = { (v)in half_to_int(ND_ifgreater_halfI(v, 0, 1.0h, 0.0h)) };
			let int_to_rgb = { (v)in let h = int_to_half(v); ND_combine3_color3H(h, h, h) };
			let int_to_rgba = { (v)in let h = int_to_half(v); ND_combine4_color4H(h, h, h, 1.0h) };
			let int_to_vec2h = { (v)in let h = int_to_half(v); ND_combine2_half2(h, h) };
			let int_to_vec3h = { (v)in let h = int_to_half(v); ND_combine3_half3(h, h, h) };
			let int_to_vec4h = { (v)in let h = int_to_half(v); ND_combine4_half4(h, h, h, h) };
			let int_to_vec2f = { (v)in let f = int_to_float(v); ND_convert_float_vector2(f) };
			let int_to_vec3f = { (v)in let f = int_to_float(v); ND_convert_float_vector3(f) };
			let int_to_vec4f = { (v)in let f = int_to_float(v); ND_convert_float_vector4(f) };

			let half_to_int = { (v)in ND_convert_half_integer(v) };
			let half_to_bool = { (v) in half_to_int(ND_ifgreater_half(v, 0.0h, 1.0h, 0.0h)) };
			let half_to_float = { (v)in ND_convert_half_float(v) };
			let half_to_rgb = { (v)in ND_convert_half_color3(v) };
			let half_to_rgba = { (v)in ND_convert_half_color4(v) };
			let half_to_vec2h = { (v) in ND_combine2_half2(v, v) };
			let half_to_vec3h = { (v) in ND_combine3_half3(v, v, v) };
			let half_to_vec4h = { (v) in ND_combine4_half4(v, v, v, v) };
			let half_to_vec2f = { (v) in ND_convert_half_vector2(v) };
			let half_to_vec3f = { (v) in ND_convert_half_vector3(v) };
			let half_to_vec4f = { (v) in ND_convert_half_vector4(v) };

			let float_to_int = { (v)in ND_convert_float_integer(v) };
			let float_to_half = { (v)in ND_convert_float_half(v) };
			let float_to_bool = { (v) in half_to_bool(float_to_half(v)) };
			let float_to_rgb = { (v)in ND_convert_float_color3(v) };
			let float_to_rgba = { (v)in ND_convert_float_color4(v) };
			let float_to_vec2h = { (v) in let h = float_to_half(v); ND_combine2_half2(h) };
			let float_to_vec3h = { (v) in let h = float_to_half(v); ND_combine3_half3(h) };
			let float_to_vec4h = { (v) in let h = float_to_half(v); ND_combine4_half4(h) };
			let float_to_vec2f = { (v) in ND_convert_float_vector2(v) };
			let float_to_vec3f = { (v) in ND_convert_float_vector3(v) };
			let float_to_vec4f = { (v) in ND_convert_float_vector4(v) };

			let vec3f_to_vec4f_0 = { (v)in ND_combine4_vector4(v3_x(v), v3_y(v), v3_z(v), 0.0f) };
			let vec3f_to_vec4f_1 = { (v)in ND_combine4_vector4(v3_x(v), v3_y(v), v3_z(v), 1.0f) };
			let vec3f_to_vec4f_w = { (v, w)in ND_combine4_vector4(v3_x(v), v3_y(v), v3_z(v), w) };

			let rgba_to_vec4f = { (v) in ND_convert_color4_vector4(v) }
			let vec4f_to_rgba = { (v) in ND_swizzle_vector4_color4(v, "xyzw") };

			let vec2f_to_bool = { (v) in float_to_bool(ND_ifequal_float(ND_multiply_float(v2_x(v), v2_y(v)), 0.0f, 0.0f, 1.0f)) };
			let vec3f_to_bool = { (v) in float_to_bool(ND_ifequal_float(ND_multiply_float(v3_x(v), ND_multiply_float(v3_y(v), v3_z(v))), 0.0f, 0.0f, 1.0f)) };
			let vec4f_to_bool = { (v) in float_to_bool(ND_ifequal_float(ND_multiply_float(ND_multiply_float(v4_x(v), ND_multiply_float(v4_y(v), ND_multiply_float(v4_z(v), v4_w(v))))), 0.0f, 0.0f, 1.0f)) };
			let rgba_to_bool = { (v) in half_to_bool(ND_ifequal_half(ND_multiply_half(ND_multiply_half(c4_r_half(v), ND_multiply_half(c4_g_half(v), ND_multiply_half(c4_b_half(v), c4_a_half(v))))), 0.0h, 0.0h, 1.0h)) };
			let rgb_to_vec3f = { (v) in ND_swizzle_color3_vector3(v, "rgb") };

			let rgb_to_bool = { (v) in half_to_bool(ND_ifequal_half(ND_multiply_half(ND_multiply_half(c3_r_half(v), ND_multiply_half(c3_g_half(v), c3_b_half(v)))), 0.0h, 0.0h, 1.0h)) };
			let rgb_to_float = { (v) in ND_swizzle_color3_float(v, "r") };
			let rgb_to_int = { (v) in float_to_int(rgb_to_float(v)) };
			let rgb_to_vec2f = { (v) in  ND_swizzle_color3_vector2(v, "rg") };
			let rgb_to_vec4f = { (v) in  vec3f_to_vec4f_1(rgb_to_vec3f(v)) };
			let rgb_to_rgba = { (v) in vec4f_to_rgba(rgb_to_vec4f(v)) };

			let rgba_to_float = { (v) in ND_swizzle_color4_float(v, "r") };
			let rgba_to_int = { (v) in float_to_int(rgba_to_float(v)) };
			let rgba_to_vec2f = { (v) in  ND_swizzle_color4_vector2(v, "rg") };
			let rgba_to_vec3f = { (v) in  ND_swizzle_color4_vector3(v, "rgb") };
			let rgba_to_rgb = { (v) in ND_swizzle_color4_color3(v, "rgb") };

			let vec2f_to_float = { (v) in ND_swizzle_vector2_float(v, "x") };
			let vec2f_to_int = { (v) in float_to_int(vec2f_to_float(v)) };
			let vec2f_to_vec3f = { (v) in ND_convert_vector2_vector3(v) };
			let vec2f_to_vec4f = { (v) in ND_combine2_vector4VV(v, (0.0f, 0.0f)) };
			let vec2f_to_rgb = { (v) in vec3f_to_rgb(vec2f_to_vec3f(v)) };
			let vec2f_to_rgba = { (v) in vec4f_to_rgba(ND_combine2_vector4VV(v, (0.0f, 1.0f))) };

			let vec3f_to_float = { (v) in ND_swizzle_vector3_float(v, "x") };
			let vec3f_to_int = { (v) in float_to_int(vec3f_to_float(v)) };
			let vec3f_to_vec2f = { (v) in ND_convert_vector3_vector2(v) };
			let vec3f_to_vec4f = { (v) in vec3f_to_vec4f_0(v) };
			let vec3f_to_rgb = { (v) in ND_convert_vector3_color3(v) };
			let vec3f_to_rgba = { (v) in vec4f_to_rgba(vec3f_to_vec4f(v)) };

			let vec4f_to_float = { (v) in ND_swizzle_vector4_float(v, "x") };
			let vec4f_to_int = { (v) in float_to_int(vec4f_to_float(v)) };
			let vec4f_to_vec2f = { (v) in ND_swizzle_vector4_vector2(v, "xy") };
			let vec4f_to_vec3f = { (v) in ND_convert_vector4_vector3(v) };
			let vec4f_to_rgb = { (v) in ND_swizzle_vector4_color3(v, "xyz") };
	)""";
}

namespace vertex {
inline const char *attributes_common() {
	return R"""(
		uniform _has_compressed_uvs : bool = false;
		uniform _uv_scale: float4 = (0.0f, 0.0f, 0.0f, 0.0f);

		let oct_to_vec3 = { (e) in
			let v_z = ND_subtract_float(ND_subtract_float(1.0f, ND_absval_float(v2_x(e))), ND_absval_float(v2_y(e)));
			let v_xy = ND_combine2_vector2(v2_x(e), v2_y(e));
			let t = ND_max_float(negate_float(v_z), 0.0f);
			let res_xy = ND_subtract_vector2(v_xy, ND_multiply_vector2(ND_sign_vector2(v_xy), ND_combine2_vector2(t, t)));
			ND_normalize_vector3(ND_combine3_vector3(v2_x(res_xy), v2_y(res_xy), v_z))
		};

		let decode_normal = { (encoded) in
			oct_to_vec3(ND_subtract_vector2(ND_multiply_vector2(encoded, v2_2), v2_1))
		};

	    let uv1_in = ND_texcoord_vector2(0);
	    let uv2_in = ND_texcoord_vector2(1);
		let normal_in = ND_texcoord_vector2(2);
	    let tangent_in = ND_texcoord_vector2(3);
		let color_in = ND_geomcolor_color4(0);
	)"""

		   // TBN attribute decoding (always uncompressed UNORM oct format)
		   R"""(
		let decoded_normal = decode_normal(normal_in);
		let signed_tangent_attrib = ND_subtract_vector2(ND_multiply_vector2(tangent_in, v2_2), v2_1);
		let decoded_tangent = oct_to_vec3(ND_combine2_vector2(v2_x(signed_tangent_attrib),
											ND_subtract_float(ND_multiply_float(ND_absval_float(v2_y(signed_tangent_attrib)), 2.0f), 1.0f)));
		let bitangent_sign = ND_sign_float(v2_y(signed_tangent_attrib));
		let decoded_bitangent = ND_normalize_vector3(ND_multiply_vector3(ND_crossproduct_vector3(decoded_normal, decoded_tangent),
												   ND_combine3_vector3(bitangent_sign, bitangent_sign, bitangent_sign)));
	)"""

		   // UV
		   R"""(
		let uncompressed_uv1 = uv1_in;
		let uncompressed_uv2 = uv2_in;
		let compressed_uv1 = ND_multiply_vector2(ND_subtract_vector2(uv1_in, v2_05), ND_swizzle_vector4_vector2(_uv_scale, "xy"));
		let compressed_uv2 = ND_multiply_vector2(ND_subtract_vector2(uv2_in, v2_05), ND_swizzle_vector4_vector2(_uv_scale, "zw"));
		let uv1_attribute = ND_ifequal_vector2B(_has_compressed_uvs, true, compressed_uv1, uncompressed_uv1);
		let uv2_attribute = ND_ifequal_vector2B(_has_compressed_uvs, true, compressed_uv2, uncompressed_uv2);
	)"""

		   // Vertex attributes — positions and TBN are always in uncompressed format
		   R"""(
		let color_attribute = color_in;
		let normal_attribute = decoded_normal;
		let tangent_attribute = decoded_tangent;
		let bitangent_attribute = decoded_bitangent;

		let position_attribute = ND_position_vector3("object");
		let position_origin = position_attribute;
	)""";
}

// `compute_position_offset`, `compute_normal`, and `compute_bitangent` bring the user's vertex-stage
// outputs into the coordinate space the RealityKit geometry modifier expects (model space for
// normal/bitangent; object-space offset relative to the original vertex for position). When
// `skip_vertex_transform` is set the user writes these in view space, so we invert the modelview
// (and use its transpose for the normal) to get back to model space. Otherwise they pass through.
// The returned static std::string is safe because the program cache key includes the render flags,
// so a render-mode change produces a different cache entry rather than reusing this string.
inline const char *attributes(const gdrk::RenderModeDescription *render_mode_description = nullptr) {
	const bool skip_vertex_transform = render_mode_description != nullptr &&
			render_mode_description->get_flag(RenderModeDescription::FLAG_SKIP_VERTEX_TRANSFORM);

	if (skip_vertex_transform) {
		static const std::string s = std::string(attributes_common()) + R"""(
		let model_to_view = ND_realitykit_geometry_modifier_model_to_view();
		let view_to_model = ND_invertmatrix_matrix44(model_to_view);
		let view_to_model_normal = ND_transpose_matrix44(model_to_view);

		let compute_position_offset = { (position) in
			let view_position_h = ND_combine4_vector4(v3_x(position), v3_y(position), v3_z(position), 1.0f);
			let object_position = v4_xyz(ND_multiply_matrix44_vector4(view_to_model, view_position_h));
			ND_subtract_vector3(object_position, position_attribute)
		};

		let compute_normal = { (normal) in
			let normal_f4 = ND_combine4_vector4(v3_x(normal), v3_y(normal), v3_z(normal), 0.0f);
			ND_normalize_vector3(v4_xyz(ND_multiply_matrix44_vector4(view_to_model_normal, normal_f4)))
		};

		let compute_bitangent = { (bitangent) in
			let bitangent_f4 = ND_combine4_vector4(v3_x(bitangent), v3_y(bitangent), v3_z(bitangent), 0.0f);
			ND_normalize_vector3(v4_xyz(ND_multiply_matrix44_vector4(view_to_model, bitangent_f4)))
		};
	)""";
		return s.c_str();
	}

	static const std::string s = std::string(attributes_common()) + R"""(
		let compute_position_offset = { (position) in
			ND_subtract_vector3(position, position_attribute)
		};

		let compute_normal = { (normal) in normal };
		let compute_bitangent = { (bitangent) in bitangent };
	)""";
	return s.c_str();
}

// These should eventually change behavior based on the render options:


inline const char *position() { return "position_attribute"; }
inline const char *normal() { return "normal_attribute"; }
inline const char *tangent() { return "tangent_attribute"; }
inline const char *bitangent() { return "bitangent_attribute"; }

inline const char *color() {
	return "rgba_to_vec4f(ND_geomcolor_color4(0))";
}
inline const char *color_rgb() {
	return "rgb_to_vec3f(ND_geomcolor_color3(0))";
}
inline const char *alpha() {
	return "c4_a(ND_geomcolor_color4(0))";
}
inline const char *uv0() {
	return "uv1_attribute";
}
inline const char *uv1() {
	return "uv2_attribute";
}
} //namespace vertex

namespace fragment {
inline const char *position() { return position::view(); }
inline const char *normal() { return normal::view(); }
inline const char *tangent() { return tangent::view(); }
inline const char *bitangent() { return bitangent::view(); }

inline const char *color() {
	return "rgba_to_vec4f(ND_geomcolor_color4(0))";
}
inline const char *color_rgb() {
	return "rgba_to_vec3f(ND_geomcolor_color4(0))";
}
inline const char *alpha() {
	return "v4_w(rgba_to_vec4f(ND_geomcolor_color4(0)))";
}
inline const char *uv0() {
	return "ND_geompropvalue_vector2(\"UV0\", (0.0f, 0.0f))";
}
inline const char *uv1() {
	return "ND_geompropvalue_vector2(\"UV1\", (0.0f, 0.0f))";
}
inline const char *view_vector() {
	return R"""(ND_normalize_vector3(v4_xyz(ND_multiply_matrix44_vector4(ND_realitykit_surface_world_to_view(), ND_combine4_vector4(v3_x(ND_realitykit_viewdirection_vector3("world")), v3_y(ND_realitykit_viewdirection_vector3("world")), v3_z(ND_realitykit_viewdirection_vector3("world")), 0.0f)))))""";
}
} //namespace fragment

} //namespace builtin

namespace boolean {
inline std::string value(bool v) {
	return v ? "1" : "0";
}
inline std::string value(const godot::Variant &p_value) {
	return value(p_value.booleanize());
}
} //namespace boolean

namespace color {

namespace rgba {
inline std::string value(const godot::Color &color) {
	return std::format("({:.6f}f, {:.6f}f, {:.6f}f, {:.6f}f)", color.r, color.g, color.b, color.a);
}
inline std::string value(const godot::Variant &v) {
	return value((const godot::Color &)v);
}

inline std::string null_texture() {
	return std::format("(0.0f, 0.0f, 0.0f, 0.0f)");
}

inline const std::string &black() {
	static std::string b = value(godot::Color(0.0, 0.0, 0.0));
	return b;
}

inline const std::string &white() {
	static std::string w = value(godot::Color(1.0, 1.0, 1.0));
	return w;
}
} //namespace rgba

namespace rgb {
inline std::string value(const godot::Color &color) {
	return std::format("({:.6f}f, {:.6f}f, {:.6f}f)", color.r, color.g, color.b);
}
inline std::string value(const godot::Variant &v) {
	return value((const godot::Color &)v);
}

inline const std::string &black() {
	static std::string b = value(godot::Color(0.0, 0.0, 0.0));
	return b;
}

inline const std::string &white() {
	static std::string w = value(godot::Color(1.0, 1.0, 1.0));
	return w;
}
} //namespace rgb

} //namespace color

namespace number {
inline std::string value(float v) {
	return std::format("{:.6f}f", v);
}
inline std::string value(int v) {
	return std::to_string(v);
}
template <typename T>
inline std::string value(const godot::Variant &v) {
	return value((T)v);
}

template <typename T>
inline std::string zero() {
	static std::string z = value((T)0);
	return z;
}

template <typename T>
inline std::string one() {
	static std::string z = value((T)1);
	return z;
}
} //namespace number

namespace vec2 {
inline std::string value(float x, float y) {
	return std::format("({:.6f}f, {:.6f}f)", x, y);
}
inline std::string value(const godot::Vector2 &vec) {
	return value(vec.x, vec.y);
}
inline std::string value(const godot::Variant &v) {
	return value((const godot::Vector2 &)v);
}
inline std::string zeros() {
	static std::string z = value(0, 0);
	return z;
}
inline std::string ones() {
	static std::string o = value(1, 1);
	return o;
}
} //namespace vec2

namespace vec3 {
inline std::string value(float x, float y, float z) {
	return std::format("({:.6f}f, {:.6f}f, {:.6f}f)", x, y, z);
}
inline std::string value(const godot::Vector3 &vec) {
	return value(vec.x, vec.y, vec.z);
}
inline std::string value(const godot::Variant &v) {
	return value((const godot::Vector3 &)v);
}
inline std::string zeros() {
	static std::string z = value(0, 0, 0);
	return z;
}
inline std::string ones() {
	static std::string o = value(1, 1, 1);
	return o;
}
} //namespace vec3

namespace vec4 {
inline std::string value(float x, float y, float z, float w) {
	return std::format("({:.6f}f, {:.6f}f, {:.6f}f, {:.6f}f)", x, y, z, w);
}
inline std::string value(const godot::Quaternion &vec) {
	return value(vec.x, vec.y, vec.z, vec.w);
}
inline std::string value(const godot::Vector4 &vec) {
	return value(vec.x, vec.y, vec.z, vec.w);
}
inline std::string value(const godot::Variant &v) {
	return value((godot::Vector4)v);
}
inline std::string quaternion(const godot::Variant &v) {
	return value((const godot::Quaternion &)v);
}
inline std::string zeros() {
	static std::string z = value(0, 0, 0, 0);
	return z;
}
inline std::string ones() {
	static std::string o = value(1, 1, 1, 1);
	return o;
}
} //namespace vec4

} //namespace sgl
} //namespace gdrk

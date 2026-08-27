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

#include "Supported.h"
#include <godot_cpp/classes/visual_shader_node_transform_vec_mult.hpp>

#include <format>

// clang-format off
DEFINE_SUPPORTED_NODE(VisualShaderNodeTransformVecMult)
	using Operator = godot::VisualShaderNodeTransformVecMult::Operator;

	INLET_COUNT(2)
	INPUT_TYPE_F(p_node_wrapper, p_index_param) {
		return p_index_param == 0 ? PortType::TRANSFORM3D : PortType::VEC3F;
	}
	OUTPUT_TYPE(PortType::VEC3F)

	ANALYZE(p_context, p_node_wrapper) {
		Operator op = UNWRAP()->get_operator();
		if (op >= Operator::OP_MAX) {
			p_context.errors.push_back(std::format(
				"VisualShaderNodeTransformVecMult: Unknown operator with identifier {}", (uint32_t) op));
		}
	}

	EXPRESSION(p_context, p_node_wrapper) {
		Operator op = UNWRAP()->get_operator();
		std::string transform = INPUT_EXPRESSION(0);
		std::string vector = INPUT_EXPRESSION(1);

		// Promote vec3 -> vec4 with w=1 (point) or w=0 (direction; zeroes the translation column).
		const char *w = (op == Operator::OP_3x3_AxB || op == Operator::OP_3x3_BxA) ? "0.0f" : "1.0f";
		std::string vec4 = std::format(
			"ND_combine4_vector4(v3_x({0}), v3_y({0}), v3_z({0}), {1})", vector, w);

		// BxA forms (vec * M) are reframed as transpose(M) * vec so we can use a single
		// matrix-vector primitive whose convention is unambiguously M * V.
		bool transpose = (op == Operator::OP_BxA || op == Operator::OP_3x3_BxA);
		std::string matrix = transpose
			? std::format("ND_transpose_matrix44({})", transform)
			: transform;

		OUTPUT_EXPRESSION(0, std::format(
			"v4_xyz(ND_multiply_matrix44_vector4({}, {}))", matrix, vec4));
	}
END(VisualShaderNodeTransformVecMult)

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
#include <godot_cpp/classes/visual_shader_node_transform_constant.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include <format>

// clang-format off
DEFINE_SUPPORTED_NODE(VisualShaderNodeTransformConstant)
	INLET_COUNT(0)
	OUTPUT_TYPE(PortType::TRANSFORM3D)

	EXPRESSION(p_context, p_node_wrapper) {
		godot::Transform3D t = UNWRAP()->get_constant();
		const godot::Basis &b = t.basis;
		// Godot's Basis is row-major (rows[i][j] = element at row i, column j).
		// ShaderGraph matrix44 is column-major; ND_realitykit_combine4_matrix44
		// takes the four column vec4s. Origin becomes the 4th column with w=1.
		OUTPUT_EXPRESSION(0, std::format(
			"ND_realitykit_combine4_matrix44("
			"({:.6f}f, {:.6f}f, {:.6f}f, 0.0f), "
			"({:.6f}f, {:.6f}f, {:.6f}f, 0.0f), "
			"({:.6f}f, {:.6f}f, {:.6f}f, 0.0f), "
			"({:.6f}f, {:.6f}f, {:.6f}f, 1.0f))",
			(float)b.rows[0].x, (float)b.rows[1].x, (float)b.rows[2].x,
			(float)b.rows[0].y, (float)b.rows[1].y, (float)b.rows[2].y,
			(float)b.rows[0].z, (float)b.rows[1].z, (float)b.rows[2].z,
			(float)t.origin.x,  (float)t.origin.y,  (float)t.origin.z));
	}
END(VisualShaderNodeTransformConstant)

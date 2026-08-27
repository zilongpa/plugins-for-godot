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

#include "visual_shader_node_wrapper.h"
#include "snippets.h"
#include "visual_program_builder.h"
#include <format>

using namespace gdrk;
using namespace godot;

VisualShaderNodeProcTable VisualShaderNodeProcTable::all_tables[VisualShaderNodeType::Count];

#pragma mark - VisualShaderNodeWrapper

bool VisualShaderNodeWrapper::unused_default;

void VisualShaderNodeWrapper::initialize(VisualProgramBuilderContext &p_context,
		ShaderType p_shader_type,
		VisualShaderNodeType p_node_type,
		godot::VisualShaderNode *p_node,
		uint32_t p_index) {
	index = p_index;
	node_type = p_node_type;
	vtable = &VisualShaderNodeProcTable::all_tables[p_node_type];
	var_name = std::format("_{}_{}_{}", vtable->type_name(), is_fragment_shader() ? "frag" : "vert", p_index);

	size_t count = inlet_count();
	upstream_connections.resize(inlet_count());
	for (uint8_t i = 0; i < count; i++) {
		upstream_connections[i] = 0;
	}

	vtable->_initialize(p_context, *this);
	return;
}

void VisualShaderNodeWrapper::initialize(VisualProgramBuilderContext &p_context,
		ShaderType p_type,
		godot::VisualShaderNode *p_node,
		uint32_t p_index) {
	node = p_node;
	shader_type = p_type;

	for (int i = VisualShaderNodeType::Unknown + 1; i < VisualShaderNodeType::Count; i++) {
		VisualShaderNodeProcTable &table_candidate = VisualShaderNodeProcTable::all_tables[i];
		ERR_FAIL_COND_MSG(!table_candidate.castable, std::format("Node implementation undefined for  type {}", (uint32_t)i).c_str());
		if (table_candidate.castable(p_node)) {
			initialize(p_context, p_type, (VisualShaderNodeType)i, p_node, p_index);
			return;
		}
	}
}

uint32_t VisualShaderNodeWrapper::sg_declare(VisualProgramBuilderContext &p_context) const {
	uint32_t res = (uint32_t)p_context.code_parts.size();
	vtable->sg_declare(shader_type, p_context);
	return res;
}

uint32_t VisualShaderNodeWrapper::sg_expression(VisualProgramBuilderContext &p_context) const {
	uint32_t res = (uint32_t)p_context.code_parts.size();
	vtable->sg_expression(p_context, *(this));
	return res;
}

std::string VisualShaderNodeWrapper::get_output_var_name(VisualProgramBuilderContext &p_context,
		uint32_t p_output_port) const {
	return std::format("{}_{}", var_name, p_output_port);
}

std::optional<InputExpression> VisualShaderNodeWrapper::get_input_var_name(VisualProgramBuilderContext &p_context,
		uint32_t p_input_index) const {
	uint32_t c_index = upstream_connections[p_input_index];
	if (c_index == 0) {
		return std::nullopt;
	}
	Connection &c = p_context.all_connections[shader_type][c_index];
	VisualShaderNodeWrapper &src_node = p_context.all_nodes[shader_type][c.src_index];

	std::string var_name = src_node.get_output_var_name(p_context, c.src_port);
	PortType output_type = src_node.output_type();
	if (c.src_port != 0) {
		PortType swizzle_type = get_swizzle_type(output_type);
		// Only VisualShaderNodeVectorDecompose outputs more than one value. This is a unique
		// case that we handle here: when the swizzle type is not defined, we default the output type
		// to its principal type
		if (swizzle_type != PortType::UNDEFINED) {
			output_type = swizzle_type;
		}
	}
	return InputExpression({
			.type = output_type,
			.expression = src_node.get_output_var_name(p_context, c.src_port),
	});
}

std::string VisualShaderNodeWrapper::get_tmp_var_name(uint32_t p_custom_id) const {
	return std::format("{}_tmp_{}", var_name, p_custom_id);
}

std::string VisualShaderNodeWrapper::get_default_input_value_override(uint32_t p_port_index) const {
	PortType type = input_type(p_port_index);
	godot::Variant value = node->get_input_port_default_value(p_port_index);
	godot::Variant port_value = to_port_value(type, value);

	std::string res = gdrk::stringify_value(type, port_value);
	return res;
}

const VisualShaderNodeWrapper *VisualShaderNodeWrapper::get_input_node(const VisualProgramBuilderContext &p_context, uint32_t p_input_index) const {
	uint32_t c_index = upstream_connections[p_input_index];
	if (c_index == 0) {
		return nullptr;
	}
	const Connection &c = p_context.all_connections[shader_type][c_index];
	return &(p_context.all_nodes[shader_type][c.src_index]);
}

std::string VisualShaderNodeWrapper::cast_expression(VisualProgramBuilderContext &p_context, InputExpression &p_expression, uint32_t p_input_index) const {
	std::string typed_expression;
	bool success = p_expression.to_type(input_type(p_input_index), typed_expression);

	if (!success) {
		std::string error = std::format("Failed to convert expression '{}' of type {} to type {}, no conversion method found",
				p_expression.expression,
				port_type_name(p_expression.type),
				port_type_name(input_type(p_input_index)));
		p_context.errors.push_back(error);
		typed_expression = p_expression.expression + " /!!!\\ TYPE_CONVERSION_ERROR: " + error;
	}
	return typed_expression;
}

std::string VisualShaderNodeWrapper::get_input_expression(VisualProgramBuilderContext &p_context,
		uint32_t p_input_index,
		bool &p_was_default) const {
	std::optional<InputExpression> expression = get_input_var_name(p_context, p_input_index);

	if (expression == std::nullopt) {
		p_was_default = true;
		return default_input_value(p_input_index);
	};

	p_was_default = false;
	return cast_expression(p_context, expression.value(), p_input_index);
}

std::string VisualShaderNodeWrapper::get_input_expression(VisualProgramBuilderContext &p_context,
		uint32_t p_input_index,
		const char *default_value,
		bool &p_was_default) const {
	std::optional<InputExpression> expression = get_input_var_name(p_context, p_input_index);

	if (expression == std::nullopt) {
		p_was_default = true;
		return default_value;
	};

	p_was_default = false;
	return cast_expression(p_context, expression.value(), p_input_index);
}

void VisualShaderNodeWrapper::fill_swizzle_outputs(VisualProgramBuilderContext &p_context, const char *p_var_name) const {
	std::string var_name = p_var_name ? p_var_name : get_output_var_name(p_context, 0);
	PortType output_port_type = output_type();
	if (output_port_type == PortType::VEC2F) {
		p_context.code_parts.push_back(sgl::statement::let(get_output_var_name(p_context, 1), std::format("v2_x({})", var_name)));
		p_context.code_parts.push_back(sgl::statement::let(get_output_var_name(p_context, 2), std::format("v2_y({})", var_name)));
	} else if (output_port_type == PortType::VEC3F) {
		p_context.code_parts.push_back(sgl::statement::let(get_output_var_name(p_context, 1), std::format("v3_x({})", var_name)));
		p_context.code_parts.push_back(sgl::statement::let(get_output_var_name(p_context, 2), std::format("v3_y({})", var_name)));
		p_context.code_parts.push_back(sgl::statement::let(get_output_var_name(p_context, 3), std::format("v3_z({})", var_name)));
	} else if (output_port_type == PortType::VEC4F) {
		p_context.code_parts.push_back(sgl::statement::let(get_output_var_name(p_context, 1), std::format("v4_x({})", var_name)));
		p_context.code_parts.push_back(sgl::statement::let(get_output_var_name(p_context, 2), std::format("v4_y({})", var_name)));
		p_context.code_parts.push_back(sgl::statement::let(get_output_var_name(p_context, 3), std::format("v4_z({})", var_name)));
		p_context.code_parts.push_back(sgl::statement::let(get_output_var_name(p_context, 4), std::format("v4_w({})", var_name)));
	}
}

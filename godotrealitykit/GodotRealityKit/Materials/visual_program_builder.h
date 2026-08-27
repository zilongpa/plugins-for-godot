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

// clang-format off
#import "GodotRealityKit.h"
#import "GodotRealityKit-Swift.h"
// clang-format on

#include "varying_allocator.h"
#include "visual_shader_node_wrapper.h"

#undef check

#include <godot_cpp/classes/visual_shader.hpp>
#include <godot_cpp/templates/local_vector.hpp>

#include <vector>

namespace godot {
class VisualShader;
}

namespace gdrk {

struct ShaderMaterialDescription;

struct VisualProgramMetadata {
	static int version;
	godot::LocalVector<UniformDescriptor> uniforms;
	bool is_transparent;

	godot::String serialize(int p_version = VisualProgramMetadata::version);
	static bool unserialize(godot::String p_json, const godot::Ref<godot::VisualShader> &p_shader, VisualProgramMetadata &p_out);
};

struct VisualProgramBuilderContext {
	std::string get_input_expression(uint32_t p_connection_index, ShaderType p_shader_type);

	godot::LocalVector<VisualShaderNodeWrapper> all_nodes[ShaderType::ST_COUNT];
	godot::LocalVector<Connection> all_connections[ShaderType::ST_COUNT];
	std::vector<uint32_t> traversal_buffers[ShaderType::ST_COUNT];
	godot::LocalVector<uint32_t> uniform_declarators[ShaderType::ST_COUNT];
	uint32_t max_node_indices[ShaderType::ST_COUNT];
	unsigned int node_count[ShaderType::ST_COUNT];

	std::vector<uint32_t> output_nodes[ShaderType::ST_COUNT];
	std::vector<std::string> code_parts;
	std::vector<std::string> errors;
	std::vector<std::string> warnings;

	bool is_transparent = false;
	bool uv_is_default = false;
	bool uv2_is_default = false;
	bool uv_used = false;
	bool uv2_used = false;

	VaryingAllocator varying_allocator;

	godot::HashMap<godot::StringName, UniformDescriptor> uniforms;
	uint32_t warning_index = 0;

	const ShaderMaterialDescription *material_description = nullptr;
};

class VisualProgramBuilder {
public:
	VisualProgramBuilder(swift::Optional<GodotRealityKit::Compiler> p_compiler,
			const ShaderMaterialDescription &p_description);

	static void finalize(ShaderMaterialDescription &p_desc, GodotRealityKit::SGLProgram &p_program);

	bool build(swift::Array<GodotRealityKit::ProgramPart> &p_program_parts);
	VisualProgramMetadata get_metadata() {
		VisualProgramMetadata res;
		res.is_transparent = context.is_transparent;
		res.uniforms.reserve(context.uniforms.size());
		for (auto [_, descriptor] : context.uniforms) {
			res.uniforms.push_back(descriptor);
		}
		return res;
	}

private:
	void comment(std::string p_str, uint8_t p_lines_after);
	void section(const char *p_str, std::function<void()> p_callback);
	void fill_nodes(ShaderType p_type);
	void fill_connections(ShaderType p_type);
	void traverse_graph(ShaderType p_type, std::function<void(VisualShaderNodeWrapper &)> p_callback);
	void traverse_graph(ShaderType p_type, std::function<void(const Connection &)> p_callback);
	void build_stage(ShaderType p_type);
	void fill_node_declarations(ShaderType p_type);
	void fill_node_expressions(ShaderType p_type);
	void build_traversal_buffer(ShaderType p_type);
	void fill_uniform_declarations();

	void build_graph();
	void allocate_varyings();
	void analyze_graph();
	void analyze_graph(ShaderType p_shader_type);
	void generate_sgl();

	bool check_for_errors(const char *step);

private:
	VisualProgramBuilderContext context;
	godot::Ref<godot::VisualShader> shader;
	swift::Optional<GodotRealityKit::Compiler> compiler;
};

} //namespace gdrk

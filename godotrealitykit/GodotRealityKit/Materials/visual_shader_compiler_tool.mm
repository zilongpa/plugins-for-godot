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


#include "visual_shader_compiler_tool.h"

#include "node_defs.h"
#include "program_description.h"
#include "visual_program_builder.h"

#undef check
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/visual_shader.hpp>

#include <string>

using namespace gdrk;

void VisualShaderCompilerTool::_bind_methods() {
	godot::ClassDB::bind_method(
			godot::D_METHOD("compile_shader", "shader_path", "output_path", "shader_project_root"),
			&VisualShaderCompilerTool::compile_shader);
}

godot::Dictionary VisualShaderCompilerTool::compile_shader(
		const godot::String &p_shader_path, const godot::String &p_output_path,
		const godot::String &p_shader_project_root) {
	godot::Dictionary result;
	result["success"] = false;

	// Rewrite res:// paths to absolute so sub-resources resolve without needing
	// Godot's resource root set to the shader's project.
	godot::String load_path = p_shader_path;
	godot::String temp_path;
	if (!p_shader_project_root.is_empty()) {
		godot::Ref<godot::FileAccess> src = godot::FileAccess::open(p_shader_path, godot::FileAccess::READ);
		if (src.is_valid()) {
			godot::String content = src->get_as_text().replace("res://", p_shader_project_root + godot::String("/"));
			src.unref();
			temp_path = godot::OS::get_singleton()->get_temp_dir().path_join("gdrk_compile.tres");
			godot::Ref<godot::FileAccess> tmp = godot::FileAccess::open(temp_path, godot::FileAccess::WRITE);
			if (tmp.is_valid()) {
				tmp->store_string(content);
				tmp.unref();
				load_path = temp_path;
			}
		}
	}

	godot::Ref<godot::VisualShader> shader =
			godot::ResourceLoader::get_singleton()->load(load_path, "VisualShader");

	if (!temp_path.is_empty()) {
		godot::DirAccess::remove_absolute(temp_path);
	}

	if (!shader.is_valid()) {
		ERR_PRINT("VisualShaderCompilerTool: Failed to load VisualShader: " + p_shader_path);
		return result;
	}

	swift::Optional<GodotRealityKit::Compiler> compiler =
			GodotRealityKit::Compiler::init(get_node_def_files());
	if (compiler.isNone()) {
		ERR_PRINT("VisualShaderCompilerTool: Failed to initialize SGL compiler");
		return result;
	}

	VisualProgramBuilder builder(compiler, shader);
	swift::Array<GodotRealityKit::ProgramPart> program_parts =
			swift::Array<GodotRealityKit::ProgramPart>::init();

	if (!builder.build(program_parts)) {
		return result;
	}

	swift::Optional<swift::String> usda = compiler.get().compile(program_parts);
	if (usda.isNone()) {
		ERR_PRINT("VisualShaderCompilerTool: SGL compiler failed to produce USDA");
		return result;
	}

	godot::Error dir_err = godot::DirAccess::make_dir_recursive_absolute(p_output_path.get_base_dir());
	if (dir_err != godot::Error::OK) {
		ERR_PRINT("VisualShaderCompilerTool: Failed to create output directory: " + p_output_path.get_base_dir());
		return result;
	}

	std::string usda_str = (std::string)usda.get();
	godot::PackedByteArray usda_bytes;
	usda_bytes.resize(usda_str.size());
	uint8_t *write_ptr = usda_bytes.ptrw();
	memcpy(write_ptr, usda_str.c_str(), usda_str.size());

	godot::Ref<godot::FileAccess> file =
			godot::FileAccess::open(p_output_path, godot::FileAccess::WRITE);
	if (!file.is_valid()) {
		ERR_PRINT("VisualShaderCompilerTool: Failed to open output file: " + p_output_path);
		return result;
	}

	file->store_buffer(usda_bytes);
	file.unref();

	result["success"] = true;
	return result;
}

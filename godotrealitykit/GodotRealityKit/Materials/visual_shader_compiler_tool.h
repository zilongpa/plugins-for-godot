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

#undef check
#include <godot_cpp/classes/object.hpp>

namespace gdrk {

class VisualShaderCompilerTool : public godot::Object {
	GDCLASS(VisualShaderCompilerTool, godot::Object);

	static void _bind_methods();

public:
	// p_shader_project_root: absolute path to the project.godot directory containing the shader.
	// Temporarily used to remap res:// so sub-resources (textures etc.) resolve correctly
	// without needing to run Godot with --path pointing at that project.
	godot::Dictionary compile_shader(const godot::String &p_shader_path, const godot::String &p_output_path, const godot::String &p_shader_project_root);
};

} // namespace gdrk

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

#ifndef BASE_MATERIAL_GEN_H
#define BASE_MATERIAL_GEN_H

// clang-format off
#import "GodotRealityKit.h"
#import "GodotRealityKit-Swift.h"
// clang-format on

#include "material_bridge.h"
#include "program_description.h"
#include "utility.h"

#undef check
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/templates/local_vector.hpp>

#define MATERIAL_EXPORT_DIRECTORY "res://.godot/gdrk/materials"

namespace gdrk {

class TextureLoader;

class ProgramCache {
public:
	enum LoadingMode : uint8_t {
		DEFAULT = 0,
		FORCE_CACHE,
		DISABLE_CACHE,
	};

	using ProgramLoadedCallback = std::function<void(uint32_t)>;
	ProgramCache(ProgramLoadedCallback &&callback, const char *p_export_directory = MATERIAL_EXPORT_DIRECTORY);

	uint32_t create_program_async(const ProgramDescription &p_material_description);

	bool is_program_loading(uint32_t p_idx) const { return program_loading_idxs.has(p_idx); }
	bool has_loading() const { return program_loading_idxs.count() > 0; }

	GodotRealityKit::SGLMaterial create_material(uint32_t p_program_idx, godot::RID p_material_rid);

	void update();
	inline const ProgramDescription &get_description(uint32_t idx) const {
		return program_descriptions[idx];
	}

	void set_loading_mode(LoadingMode p_mode) { loading_mode = p_mode; }
	uint32_t create_broken_program_async();

private:
	struct Program {
		GodotRealityKit::SGLProgram value = GodotRealityKit::SGLProgram::init();
	};

	godot::String read_file(godot::String p_path) const;
	godot::String read_from_cache(godot::String p_path) const;

	uint32_t create_program_async(const BaseMaterial3DDescription &p_program_description);
	uint32_t create_program_async(const ShaderMaterialDescription &p_program_description);

	uint32_t load_usda(ProgramDescription &&p_desc, swift::String &content, ProgramLoadedCallback &&p_finalize_callback);
	uint32_t make_usda(ProgramDescription &&p_desc, const swift::Array<GodotRealityKit::ProgramPart> &p_program_parts, ProgramLoadedCallback &&p_finalize_callback);
	uint32_t load_usda_from_file(ProgramDescription &&p_desc, godot::String p_resource_path, ProgramLoadedCallback &&p_finalize_callback);

	friend typename ::GDRKMaterialLoadDelegate;

	std::optional<GodotRealityKit::ProgramPart> parse_snippet(const swift::String &p_source);

	godot::HashMap<uint32_t, uint32_t> program_description_to_idx;
	godot::LocalVector<Program> programs;
	godot::LocalVector<ProgramDescription> program_descriptions;
	LocalBitVector program_loading_idxs;
	godot::LocalVector<uint32_t> finished_loaded_idxs;

	godot::HashMap<uint64_t, GodotRealityKit::ProgramPart> snippet_cache;
	swift::Optional<GodotRealityKit::Compiler> compiler;
	ProgramLoadedCallback notify_program_loaded;

	uint32_t broken_material_index = UINT32_MAX;
	godot::String export_directory;
	LoadingMode loading_mode = LoadingMode::DEFAULT;
};

} // namespace gdrk

#endif // BASE_MATERIAL_GEN_H

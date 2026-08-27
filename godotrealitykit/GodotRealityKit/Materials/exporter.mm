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

#include "exporter.h"
#include "node_defs.h"
#include "program_cache.h"
#include "types.h"
#include "visual_program_builder.h"

#import "node_def_embeds.h"

#undef check

#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/editor_file_system.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/visual_shader.hpp>

#include <chrono>
#include <filesystem>
#include <godot_cpp/core/error_macros.hpp>

using namespace gdrk;

static void touch_project_file(godot::String &p_path) {
	godot::String absolute_path = godot::ProjectSettings::get_singleton()->globalize_path(p_path);

	auto now = std::filesystem::file_time_type::clock::now();
	std::filesystem::last_write_time(absolute_path.utf8().get_data(), now);
}

static godot::String read_from_project(godot::String p_path) {
	// Open the file in READ mode
	godot::String file_path = godot::ProjectSettings::get_singleton()->globalize_path(p_path);
	godot::Ref<godot::FileAccess> file = godot::FileAccess::open(file_path, godot::FileAccess::READ);

	if (!file.is_valid()) {
		return "";
	}

	return file->get_as_text();
}

static void write_to_project(godot::String p_path, godot::PackedByteArray &p_data) {
	godot::String file_path = godot::ProjectSettings::get_singleton()->globalize_path(p_path);
	godot::String directory = file_path.get_base_dir();
	godot::Error err = godot::DirAccess::make_dir_recursive_absolute(directory);
	if (err != godot::Error::OK) {
		return;
	}
	godot::Ref<godot::FileAccess> file = godot::FileAccess::open(p_path, godot::FileAccess::WRITE);
	if (!file.is_valid()) {
		return;
	}

	file->store_buffer(p_data);
}

#pragma mark - MaterialEditorExportPlugin::MaterialExporter

MaterialExporter::MaterialExporter(MaterialEditorExportPlugin *p_plugin,
		const char *p_export_directory) :
		compiler(GodotRealityKit::Compiler::init(get_node_def_files())), export_directory(p_export_directory), plugin(p_plugin), export_version(gdrk::VisualProgramMetadata::version) {
}

#define STR_HELPER(x) #x
#define STR(x) STR_HELPER(x)

void MaterialExporter::export_visual_shader(const godot::String &p_path) {
	godot::Ref<godot::VisualShader> shader = godot::ResourceLoader::get_singleton()->load(p_path, "VisualShader");

	if (!shader.is_valid()) {
		ERR_PRINT("Failed to load VisualShader: " + p_path);
		return;
	}

	godot::String hash = godot::FileAccess::get_md5(p_path) + " - " + godot::String(STR(MATERIALS_CODE_HASH)) + " - " + godot::String::num_int64(export_version);
	godot::String base_path = p_path.replace("res://", export_directory + "/");
	godot::String precompiled_file_name = base_path + ".usda";
	godot::String metadata_path = base_path + ".meta.json";
	godot::String hash_path = base_path + ".hash";
	godot::String existing_hash = read_from_project(hash_path);
	godot::PackedByteArray hash_data = hash.to_ascii_buffer();
	godot::PackedByteArray usda_data;
	godot::PackedByteArray metadata_data;

	if (existing_hash == hash) {
		godot::String usda_content = read_from_project(precompiled_file_name);
		if (usda_content != "") {
			usda_data = usda_content.to_utf8_buffer();
		}

		godot::String metadata_content = read_from_project(metadata_path);
		if (metadata_content != "") {
			metadata_data = metadata_content.to_utf8_buffer();
		}
	}

	if (usda_data.size() == 0 || metadata_data.size() == 0) {
		print_line("MaterialExporter: Exporting resource (existing " + existing_hash + " != current " + hash + ") : " + p_path);
		VisualProgramBuilder builder(compiler, ShaderMaterialDescription(shader));
		swift::Array<GodotRealityKit::ProgramPart> program_parts = swift::Array<GodotRealityKit::ProgramPart>::init();

		bool success = builder.build(program_parts);
		if (!success) {
			ERR_PRINT("MaterialExporter: Failed to build USDA");
			return;
		}

		swift::Optional<swift::String> program_usda = compiler.get().compile(program_parts);

		VisualProgramMetadata meta = builder.get_metadata();
		godot::String metadata_str = meta.serialize(export_version);

		if (program_usda.isNone()) {
			ERR_PRINT("MaterialExporter: Failed to create USDA");
			return;
		}

		metadata_data = metadata_str.to_utf8_buffer();
		std::string program_str = (std::string)program_usda.get();
		usda_data.resize(program_str.length());
		uint8_t *write_ptr = usda_data.ptrw();
		memcpy(write_ptr, program_str.c_str(), program_str.length());

		write_to_project(precompiled_file_name, usda_data);
		write_to_project(hash_path, hash_data);
		write_to_project(metadata_path, metadata_data);
	} else {
		print_line("MaterialExporter: Resource up to date: " + p_path);
	}

	exported_resources.set(godot::ProjectSettings::get_singleton()->globalize_path(precompiled_file_name), true);
	exported_resources.set(godot::ProjectSettings::get_singleton()->globalize_path(hash_path), true);
	exported_resources.set(godot::ProjectSettings::get_singleton()->globalize_path(metadata_path), true);

	if (plugin) {
		plugin->add_file(precompiled_file_name, usda_data, false);
		plugin->add_file(hash_path, hash_data, false);
		plugin->add_file(metadata_path, metadata_data, false);
	}
}

void MaterialExporter::list_exported_files(godot::String p_dir, godot::Vector<godot::String> &p_files_list) {
	godot::Ref<godot::DirAccess> dir_access = godot::DirAccess::open(p_dir);
	if (!dir_access.is_valid()) {
		ERR_PRINT("Failed to open directory: " + p_dir);
		return;
	}
	dir_access->list_dir_begin();
	godot::String file_name = dir_access->get_next();
	while (!file_name.is_empty()) {
		if (file_name != "." && file_name != "..") {
			godot::String full_path = p_dir.path_join(file_name);
			if (dir_access->current_is_dir()) {
				list_exported_files(full_path, p_files_list);
			} else {
				p_files_list.push_back(full_path);
			}
		}
		file_name = dir_access->get_next();
	}
}

void MaterialExporter::export_begin() {
	godot::PackedByteArray ignore_data;
	godot::String ignore_path = export_directory + "/.gdignore";
	write_to_project(ignore_path, ignore_data);

	exported_resources.clear();
}

void MaterialExporter::export_end() {
	godot::Vector<godot::String> files;
	godot::String material_export_dir = godot::ProjectSettings::get_singleton()->globalize_path(export_directory);
	list_exported_files(material_export_dir, files);

	for (const godot::String &file : files) {
		if (!exported_resources.has(file)) {
			godot::DirAccess::remove_absolute(file);
			print_line("Removing outdated file: " + file);
		}
	}
}

#pragma mark - MaterialEditorExportPlugin

MaterialEditorExportPlugin::MaterialEditorExportPlugin() :
		exporter(this) {
}

void MaterialEditorExportPlugin::_export_file(const godot::String &p_path, const godot::String &p_type, const godot::PackedStringArray &p_features) {
	if (p_type != "VisualShader") {
		return;
	}
	exporter.export_visual_shader(p_path);
}

void MaterialEditorExportPlugin::_export_begin(const godot::PackedStringArray &p_features, bool p_is_debug, const godot::String &p_path, uint32_t p_flags) {
	exporter.export_begin();
}

void MaterialEditorExportPlugin::_export_end() {
	exporter.export_end();
}

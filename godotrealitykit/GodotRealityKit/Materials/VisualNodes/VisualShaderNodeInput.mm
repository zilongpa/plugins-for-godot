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

#include <algorithm>
#include <cctype>
#include <godot_cpp/classes/visual_shader_node_input.hpp>
#include <godot_cpp/templates/hash_map.hpp>

// clang-format off
DEFINE_SUPPORTED_NODE(VisualShaderNodeInput)
	enum Input: uint8_t {
		BINORMAL = 0, // Vertex, Fragment
		CAMERA_DIRECTION_WORLD, // Vertex, Fragment
		CAMERA_POSITION_WORLD, // Vertex, Fragment,
		CAMERA_VISIBLE_LAYERS, // Vertex, Fragment,
		CLIP_SPACE_FAR, // Vertex
		COLOR, // Vertex, Fragment,
		CUSTOM0, // Vertex
		CUSTOM1, // Vertex
		CUSTOM2, // Vertex
		CUSTOM3, // Vertex
		EXPOSURE, // Vertex, Fragment
		EYE_OFFSET, // Vertex, Fragment
		FRAGCOORD, // Fragment
		CAMERA_FRONT_FACING, // Fragment
		INSTANCE_CUSTOM, // Vertex
		INSTANCE_ID, // Vertex
		INV_PROJECTION_MATRIX, // Vertex, Fragment,
		INV_MODELVIEW_MATRIX, // Vertex, Fragment,
		MODEL_MATRIX, // Vertex, Fragment,
		MODELVIEW_MATRIX, // Vertex,
		NODE_POSITION_VIEW, // Vertex, Fragment,
		NODE_POSITION_WORLD, // Vertex, Fragment
		NORMAL, // Vertex, Fragment,
		OUTPUT_IS_SRGB, // Vertex, Fragment
		POINT_COORD, // Fragment
		POINT_SIZE, // Vertex,
		PROJECTION_MATRIX, // Vertex, Fragment,
		ROUGHNESS, // Vertex
		SCREEN_UV, // Fragment
		TANGENT, // Vertex, Fragment,
		TIME, // Vertex, Fragment,
		UV, // Vertex, Fragment,
		UV2, // Vertex, Fragment,
		VERTEX, // Vertex, Fragment,
		VERTEX_ID, // Vertex
		VIEW, // Fragment
		VIEW_INDEX, // Vertex, Fragment
		VIEW_MATRIX, // Vertex, Fragment
		VIEW_MONO_LEFT, // Vertex, Fragment
		VIEW_RIGHT, // Vertex, Fragment
		VIEWPORT_SIZE, // Vertex, Fragment

		COUNT,
	};

	struct InputInfo {
		Input input;

		inline static std::string declarations[ShaderType::ST_COUNT][Input::COUNT] = {};
		inline static std::string expressions[ShaderType::ST_COUNT][Input::COUNT] = {};
		inline static PortType types[ShaderType::ST_COUNT][Input::COUNT] = {};

        inline static std::string (&get_declarations(ShaderType type))[Input::COUNT] {
			return declarations[type];
        }
        inline static std::string &get_expression(ShaderType p_type, Input p_input) {
			return expressions[p_type][p_input];
        }
		inline static PortType get_type(ShaderType p_type, Input p_input, uint32_t p_port) {
			PortType base_port_type = types[p_type][p_input];
			return p_port == 0 ? base_port_type : get_swizzle_type(base_port_type);
		}
		
		inline static std::string to_lower(std::string&& p_in) {
			std::string res = std::move(p_in);
			std::transform(res.begin(), res.end(), res.begin(), [](unsigned char c){ return std::tolower(c); });
			return res;
		}
	};


STATIC_INIT({
#define DEFINE_INPUT_EXPRESSION(EnumName) \
			  InputInfo::expressions[ShaderType::ST_VERTEX][Input::EnumName] = InputInfo::to_lower("VisualShaderNodeInput_vertex_get_" #EnumName); \
			  InputInfo::expressions[ShaderType::ST_FRAGMENT][Input::EnumName] = InputInfo::to_lower("VisualShaderNodeInput_fragment_get_" #EnumName)

		  DEFINE_INPUT_EXPRESSION(BINORMAL);
		  DEFINE_INPUT_EXPRESSION(CAMERA_DIRECTION_WORLD);
		  DEFINE_INPUT_EXPRESSION(CAMERA_POSITION_WORLD);
		  DEFINE_INPUT_EXPRESSION(CAMERA_VISIBLE_LAYERS);
		  DEFINE_INPUT_EXPRESSION(CLIP_SPACE_FAR);
		  DEFINE_INPUT_EXPRESSION(COLOR);
		  DEFINE_INPUT_EXPRESSION(CUSTOM0);
		  DEFINE_INPUT_EXPRESSION(CUSTOM1);
		  DEFINE_INPUT_EXPRESSION(CUSTOM2);
		  DEFINE_INPUT_EXPRESSION(CUSTOM3);
		  DEFINE_INPUT_EXPRESSION(EXPOSURE);
		  DEFINE_INPUT_EXPRESSION(EYE_OFFSET);
		  DEFINE_INPUT_EXPRESSION(FRAGCOORD);
		  DEFINE_INPUT_EXPRESSION(CAMERA_FRONT_FACING);
		  DEFINE_INPUT_EXPRESSION(INSTANCE_CUSTOM);
		  DEFINE_INPUT_EXPRESSION(INSTANCE_ID);
		  DEFINE_INPUT_EXPRESSION(INV_PROJECTION_MATRIX);
		  DEFINE_INPUT_EXPRESSION(INV_MODELVIEW_MATRIX);
		  DEFINE_INPUT_EXPRESSION(MODEL_MATRIX);
		  DEFINE_INPUT_EXPRESSION(MODELVIEW_MATRIX);
		  DEFINE_INPUT_EXPRESSION(NODE_POSITION_VIEW);
		  DEFINE_INPUT_EXPRESSION(NODE_POSITION_WORLD);
		  DEFINE_INPUT_EXPRESSION(NORMAL);
		  DEFINE_INPUT_EXPRESSION(OUTPUT_IS_SRGB);
		  DEFINE_INPUT_EXPRESSION(POINT_COORD);
		  DEFINE_INPUT_EXPRESSION(POINT_SIZE);
		  DEFINE_INPUT_EXPRESSION(PROJECTION_MATRIX);
		  DEFINE_INPUT_EXPRESSION(ROUGHNESS);
		  DEFINE_INPUT_EXPRESSION(SCREEN_UV);
		  DEFINE_INPUT_EXPRESSION(TANGENT);
		  DEFINE_INPUT_EXPRESSION(TIME);
		  DEFINE_INPUT_EXPRESSION(UV);
		  DEFINE_INPUT_EXPRESSION(UV2);
		  DEFINE_INPUT_EXPRESSION(VERTEX);
		  DEFINE_INPUT_EXPRESSION(VERTEX_ID);
		  DEFINE_INPUT_EXPRESSION(VIEW);
		  DEFINE_INPUT_EXPRESSION(VIEW_INDEX);
		  DEFINE_INPUT_EXPRESSION(VIEW_MATRIX);
		  DEFINE_INPUT_EXPRESSION(VIEW_MONO_LEFT);
		  DEFINE_INPUT_EXPRESSION(VIEW_RIGHT);
		  DEFINE_INPUT_EXPRESSION(VIEWPORT_SIZE);

#define VERTEX_DECLARATION(EnumName, type, value) \
			  InputInfo::types[ShaderType::ST_VERTEX][Input::EnumName] = type; \
			  InputInfo::declarations[ShaderType::ST_VERTEX][Input::EnumName] = std::format(R"""(let {} = {{ ()in {} }}; )""", InputInfo::get_expression(ShaderType::ST_VERTEX, Input::EnumName), value); \

		  {

			  // Supported
			  VERTEX_DECLARATION(VERTEX, PortType::VEC3F, sgl::builtin::vertex::position());
			  VERTEX_DECLARATION(NORMAL, PortType::VEC3F, sgl::builtin::vertex::normal());
			  VERTEX_DECLARATION(TANGENT, PortType::VEC3F, sgl::builtin::vertex::tangent());
			  VERTEX_DECLARATION(BINORMAL, PortType::VEC3F, sgl::builtin::vertex::bitangent());
			  VERTEX_DECLARATION(COLOR, PortType::VEC4F, sgl::builtin::vertex::color());
			  VERTEX_DECLARATION(TIME, PortType::FLOAT, sgl::builtin::time());
			  VERTEX_DECLARATION(UV, PortType::VEC2F, sgl::builtin::vertex::uv0());
			  VERTEX_DECLARATION(UV2, PortType::VEC2F, sgl::builtin::vertex::uv1());

			  // Transform builtins
			  VERTEX_DECLARATION(MODEL_MATRIX, PortType::TRANSFORM3D, "ND_realitykit_geometry_modifier_model_to_world()");
			  VERTEX_DECLARATION(MODELVIEW_MATRIX, PortType::TRANSFORM3D, "ND_realitykit_geometry_modifier_model_to_view()");
			  VERTEX_DECLARATION(INV_MODELVIEW_MATRIX, PortType::TRANSFORM3D, "ND_invertmatrix_matrix44(ND_realitykit_geometry_modifier_model_to_view())");
			  VERTEX_DECLARATION(VIEW_MATRIX, PortType::TRANSFORM3D, "ND_multiply_matrix44(ND_realitykit_geometry_modifier_model_to_view(), ND_realitykit_geometry_modifier_world_to_model())");
			  VERTEX_DECLARATION(PROJECTION_MATRIX, PortType::TRANSFORM3D, "ND_realitykit_geometry_modifier_view_to_projection()");
			  VERTEX_DECLARATION(INV_PROJECTION_MATRIX, PortType::TRANSFORM3D, "ND_realitykit_geometry_modifier_projection_to_view()");

			  // TODO
			  VERTEX_DECLARATION(CAMERA_DIRECTION_WORLD, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(CAMERA_POSITION_WORLD, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(CAMERA_VISIBLE_LAYERS, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(CLIP_SPACE_FAR, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(CUSTOM0, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(CUSTOM1, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(CUSTOM2, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(CUSTOM3, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(EXPOSURE, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(EYE_OFFSET, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(INSTANCE_CUSTOM, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(INSTANCE_ID, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(NODE_POSITION_VIEW, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(NODE_POSITION_WORLD, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(OUTPUT_IS_SRGB, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(POINT_SIZE, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(ROUGHNESS, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(VERTEX_ID, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(VIEW_INDEX, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(VIEW_MONO_LEFT, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(VIEW_RIGHT, PortType::UNDEFINED, "1.0f");
			  VERTEX_DECLARATION(VIEWPORT_SIZE, PortType::UNDEFINED, "1.0f");
		  }

		  {
#define FRAGMENT_DECLARATION(EnumName, type, value) \
			  InputInfo::types[ShaderType::ST_FRAGMENT][Input::EnumName] = type; \
			  InputInfo::declarations[ShaderType::ST_FRAGMENT][Input::EnumName] = std::format(R"""(let {} = {{ ()in {} }}; )""", InputInfo::get_expression(ShaderType::ST_FRAGMENT, Input::EnumName), value);
				  
			  // Supported
			  FRAGMENT_DECLARATION(VERTEX, PortType::VEC3F, sgl::builtin::fragment::position());
			  FRAGMENT_DECLARATION(NORMAL, PortType::VEC3F, sgl::builtin::fragment::normal());
			  FRAGMENT_DECLARATION(TANGENT, PortType::VEC3F, sgl::builtin::fragment::tangent());
			  FRAGMENT_DECLARATION(BINORMAL, PortType::VEC3F, sgl::builtin::fragment::bitangent());
			  FRAGMENT_DECLARATION(COLOR, PortType::VEC4F, sgl::builtin::fragment::color());
			  FRAGMENT_DECLARATION(TIME, PortType::FLOAT, sgl::builtin::time());
			  FRAGMENT_DECLARATION(UV, PortType::VEC2F, sgl::builtin::fragment::uv0())
			  FRAGMENT_DECLARATION(UV2, PortType::VEC2F, sgl::builtin::fragment::uv1())
			  FRAGMENT_DECLARATION(VIEW, PortType::VEC3F, sgl::builtin::fragment::view_vector());

			  // Transform builtins
			  FRAGMENT_DECLARATION(MODEL_MATRIX, PortType::TRANSFORM3D, "ND_realitykit_surface_model_to_world()");
			  FRAGMENT_DECLARATION(INV_MODELVIEW_MATRIX, PortType::TRANSFORM3D, "ND_invertmatrix_matrix44(ND_realitykit_surface_model_to_view())");
			  FRAGMENT_DECLARATION(VIEW_MATRIX, PortType::TRANSFORM3D, "ND_realitykit_surface_world_to_view()");
			  FRAGMENT_DECLARATION(PROJECTION_MATRIX, PortType::TRANSFORM3D, "ND_realitykit_surface_view_to_projection()");
			  FRAGMENT_DECLARATION(INV_PROJECTION_MATRIX, PortType::TRANSFORM3D, "ND_realitykit_surface_projection_to_view()");

			  FRAGMENT_DECLARATION(CAMERA_FRONT_FACING, PortType::BOOL, "ND_realitykit_is_front_facing()");

			  // TODO
			  FRAGMENT_DECLARATION(CAMERA_DIRECTION_WORLD, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(CAMERA_POSITION_WORLD, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(CAMERA_VISIBLE_LAYERS, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(EXPOSURE, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(EYE_OFFSET, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(FRAGCOORD, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(NODE_POSITION_VIEW, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(NODE_POSITION_WORLD, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(OUTPUT_IS_SRGB, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(POINT_COORD, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(SCREEN_UV, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(VIEW_INDEX, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(VIEW_MONO_LEFT, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(VIEW_RIGHT, PortType::UNDEFINED, "1.0f");
			  FRAGMENT_DECLARATION(VIEWPORT_SIZE, PortType::UNDEFINED, "1.0f");
		  }
	  })

	INLET_COUNT(0)

	INITIALIZE(p_context, p_node_wrapper) {
		static godot::HashMap<godot::String, Input> input_map = {
			{ "vertex", Input::VERTEX },
			{ "normal", Input::NORMAL },
			{ "color", Input::COLOR },

			{ "binormal", Input::BINORMAL },
			{ "camera_direction_world", Input::CAMERA_DIRECTION_WORLD },
			{ "camera_position_world", Input::CAMERA_POSITION_WORLD },
			{ "camera_visible_layers", Input::CAMERA_VISIBLE_LAYERS },
			{ "clip_space_far", Input::CLIP_SPACE_FAR },

			{ "custom0", Input::CUSTOM0 },
			{ "custom1", Input::CUSTOM1 },
			{ "custom2", Input::CUSTOM2 },
			{ "custom3", Input::CUSTOM3 },
			{ "exposure", Input::EXPOSURE },
			{ "eye_offset", Input::EYE_OFFSET },
			{ "fragcoord", Input::FRAGCOORD },
			{ "camera_fron_facing", Input::CAMERA_FRONT_FACING },
			{ "instance_custom", Input::INSTANCE_CUSTOM },
			{ "instance_id", Input::INSTANCE_ID },
			{ "inv_projection_matrix", Input::INV_PROJECTION_MATRIX },
			{ "inv_modelview_matrix", Input::INV_MODELVIEW_MATRIX },
			{ "model_matrix", Input::MODEL_MATRIX },
			{ "modelview_matrix", Input::MODELVIEW_MATRIX },
			{ "node_position_view", Input::NODE_POSITION_VIEW },
			{ "node_position_world", Input::NODE_POSITION_WORLD },
			{ "output_is_srgb", Input::OUTPUT_IS_SRGB },
			{ "point_coord", Input::POINT_COORD },
			{ "point_size", Input::POINT_SIZE },
			{ "projection_matrix", Input::PROJECTION_MATRIX },
			{ "roughness", Input::ROUGHNESS },
			{ "screen_uv", Input::SCREEN_UV },
			{ "tangent", Input::TANGENT },
			{ "time", Input::TIME },
			{ "uv", Input::UV },
			{ "uv2", Input::UV2 },
			{ "view", Input::VIEW },
			{ "view_index", Input::VIEW_INDEX },
			{ "view_matrix", Input::VIEW_MATRIX },
			{ "view_mono_left", Input::VIEW_MONO_LEFT },
			{ "view_right", Input::VIEW_RIGHT },
			{ "viewport_size", Input::VIEWPORT_SIZE },
		};
		
		godot::VisualShaderNodeInput *node = (godot::VisualShaderNodeInput *)p_node_wrapper.node;
		Input input = input_map[node->get_input_name()];
		p_node_wrapper.custom_data.set(InputInfo {
			.input = input,
		});
	}

	OUTPUT_TYPE_F(p_node_wrapper) {
		InputInfo &input_info = p_node_wrapper.custom_data.get<InputInfo>();
		return InputInfo::get_type(p_node_wrapper.shader_type, input_info.input, 0);
	}

	DECLARATION(p_type, p_context) {
		for (uint8_t i = 0; i < Input::COUNT; i++) {
			p_context.code_parts.push_back(InputInfo::declarations[p_type][i]);
		}
	}

	ANALYZE(p_context, p_node_wrapper) {
		InputInfo &input_info = p_node_wrapper.custom_data.get<InputInfo>();
		p_context.uv_used |= input_info.input == Input::UV;
		p_context.uv2_used |= input_info.input == Input::UV2;
	}

	EXPRESSION(p_context, p_node_wrapper) {
		std::string var_name = p_node_wrapper.get_output_var_name(p_context, 0);
		InputInfo &input_info = p_node_wrapper.custom_data.get<InputInfo>();
		
		OUTPUT_EXPRESSION(0, std::format("{}()", InputInfo::get_expression(p_node_wrapper.shader_type, input_info.input)));
	}
END(VisualShaderNodeInput)

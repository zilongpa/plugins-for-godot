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

#include "material_bridge.h"

#undef check
#include <godot_cpp/classes/visual_shader.hpp>
#include <godot_cpp/classes/visual_shader_node.hpp>
#include <godot_cpp/templates/list.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/templates/pair.hpp>

#include <format>

// clang-format off
#define DEFINE_NODE_COMMON_PREFIX(NodeType, NameSuffix)                      \
	namespace godot {                                                        \
	class NodeType;                                                          \
	}                                                                        \
	template <>                                                              \
	inline const char *gdrk::type_name<::godot::NodeType>() {                  \
		return #NodeType NameSuffix;                                         \
	}                                                                        \
	template <>                                                              \
	bool ::gdrk::castable<::godot::NodeType>(::godot::VisualShaderNode * p_node) { \
		return godot::Object::cast_to<::godot::NodeType>(p_node) != nullptr;   \
	}

#define DEFINE_UNSUPPORTED_NODE(NodeType, reason)                                                                                      \
	DEFINE_NODE_COMMON_PREFIX(NodeType, "(" reason ")")                                                                       \
	template <>                                                                                                                \
	inline bool gdrk::supported<godot::NodeType>() {                                                                           \
		return false;                                                                                                          \
	}                                                                                                                          \
	template <>                                                                                                                \
	void gdrk::sg_expression<godot::NodeType>(VisualProgramBuilderContext & p_context,                                         \
			const VisualShaderNodeWrapper &p_node) {                                                                           \
		p_context.code_parts.push_back(std::string("let __UNSUPPORTED__" #NodeType) + " = " + std::to_string(NodeType) + ";"); \
	}                                                                                                                          \
	template <>                                                                                                                \
	gdrk::VisualShaderNodeProcTableInitializer<NodeType, godot::NodeType> gdrk::VisualShaderNodeProcTableInitializer<NodeType, godot::NodeType>::instance = gdrk::VisualShaderNodeProcTableInitializer<NodeType, godot::NodeType>();

#define DEFINE_UNIMPLEMENTED_NODE(NodeType) DEFINE_UNSUPPORTED_NODE(NodeType, "Unimplemented")


#define DEFINE_SUPPORTED_NODE(NodeType)                                                     		\
	\
	DEFINE_NODE_COMMON_PREFIX(NodeType, "")  \
	\
	namespace impl ## NodeType {	\
		class __default {}; 																		\
		template<typename T> inline void _initialize(gdrk::VisualProgramBuilderContext &p_context, gdrk::VisualShaderNodeWrapper &p_node) { return gdrk::_initialize<__default>(p_context, p_node); } \
		template<typename T> inline bool declares_uniforms() { return gdrk::declares_uniforms<__default>(); } \
		template<typename T> inline uint32_t inlet_count(gdrk::ShaderType p_type) { return gdrk::inlet_count<__default>(p_type); } \
		template<typename T> inline void sg_declare(gdrk::ShaderType p_type, gdrk::VisualProgramBuilderContext &p_context) { gdrk::sg_declare<__default>(p_type, p_context); } \
		template<typename T> inline void sg_expression(gdrk::VisualProgramBuilderContext &p_context, const gdrk::VisualShaderNodeWrapper &p_node) {  gdrk::sg_expression<__default>(p_context, p_node); } \
		template<typename T> inline std::string default_input_value(const gdrk::VisualShaderNodeWrapper &p_node_wrapper, uint32_t p_port_index) { return gdrk::default_input_value<__default>(p_node_wrapper, p_port_index); } \
		template<typename T> inline gdrk::PortType input_type(const gdrk::VisualShaderNodeWrapper &p_node, uint32_t p_index) { return gdrk::input_type<__default>(p_node, p_index); } \
		template<typename T> inline gdrk::PortType output_type(const gdrk::VisualShaderNodeWrapper &p_node) { return gdrk::output_type<__default>(p_node); }\
		template<typename T> inline void analyze(gdrk::VisualProgramBuilderContext &p_context, const gdrk::VisualShaderNodeWrapper &p_node) { return gdrk::analyze<__default>(p_context, p_node); } \
		template<typename T> inline gdrk::OptionalUniformDescriptor get_uniform_descriptor(godot::VisualShaderNode *p_node, gdrk::ShaderType p_shader_type, uint32_t p_node_index) { return gdrk::get_uniform_descriptor<__default>(p_node, p_shader_type, p_node_index); } \
		using CURRENT_GODOT_NODE_TYPE = ::godot::NodeType; \
		const char* CURRENT_GODOT_NODE_NAME = #NodeType; \
		using INITIALIZER_TYPE = gdrk::VisualShaderNodeProcTableInitializer<gdrk::NodeType, godot::NodeType>; \
		inline bool supported() { return true; }             \
		using namespace gdrk;

#define INLET_COUNT_F(type_param) \
	template <>                   \
	inline uint32_t inlet_count<CURRENT_GODOT_NODE_TYPE>(gdrk::ShaderType type_param)

#define INLET_COUNT(v) \
	INLET_COUNT_F(_) { \
		return v;      \
	}

#define DEFAULT_INPUT_VALUE_F(node_param, index_param) \
	template <>                                        \
	inline std::string default_input_value<CURRENT_GODOT_NODE_TYPE>(const gdrk::VisualShaderNodeWrapper &node_param, uint32_t index_param)

#define DEFAULT_INPUT_VALUE(str)           \
	DEFAULT_INPUT_VALUE_F(_node, _index) { \
		return str;                        \
	}

#define INPUT_TYPE_F(node_param, index_param) \
	template <>                                        \
	inline gdrk::PortType input_type<CURRENT_GODOT_NODE_TYPE>(const gdrk::VisualShaderNodeWrapper &node_param, uint32_t index_param)

#define INPUT_TYPE(t)           \
	INPUT_TYPE_F(_node, _index) { \
		return t;                        \
	}

#define OUTPUT_TYPE_F(node_param) \
	template <>                   \
	inline gdrk::PortType output_type<CURRENT_GODOT_NODE_TYPE>(const gdrk::VisualShaderNodeWrapper &node_param)

#define OUTPUT_TYPE(t)           \
	OUTPUT_TYPE_F(_node) { 		 \
		return t;                \
	}

#define INITIALIZE(context_param, node_param) \
	template<> inline void _initialize<CURRENT_GODOT_NODE_TYPE>(VisualProgramBuilderContext &context_param, gdrk::VisualShaderNodeWrapper &node_param)

#define DECLARATION(type_param, context_param)                                                  \
	template <>                                                                                 \
	inline void sg_declare<CURRENT_GODOT_NODE_TYPE>(gdrk::ShaderType type_param, \
													gdrk::VisualProgramBuilderContext & context_param)

#define EXPRESSION(context_param, node_param)                                                             \
	template <>                                                                                           \
	inline void sg_expression<CURRENT_GODOT_NODE_TYPE>(gdrk::VisualProgramBuilderContext & context_param, \
													   const gdrk::VisualShaderNodeWrapper &node_param)

#define ANALYZE(context_param, node_param) \
	template <>                                                                                                               \
	inline bool declares_uniforms<CURRENT_GODOT_NODE_TYPE>() {                                                                \
		   return true;                                                                                                       \
	} \
	template<> \
	inline void analyze<CURRENT_GODOT_NODE_TYPE>(VisualProgramBuilderContext & context_param, \
														   const VisualShaderNodeWrapper &node_param)

#define DECLARE_UNIFORM(node_param, shader_type_param, node_index_param) \
	template <> \
	inline OptionalUniformDescriptor get_uniform_descriptor<CURRENT_GODOT_NODE_TYPE>(godot::VisualShaderNode *node_param, gdrk::ShaderType shader_type_param, uint32_t node_index_param)

// assumes EXPRESSION called with p_context, p_node_wrapper params
#define UNWRAP() ((CURRENT_GODOT_NODE_TYPE *) p_node_wrapper.node)
#define	NODE() ((CURRENT_GODOT_NODE_TYPE *) p_node)
#define OUTPUT_EXPRESSION(index, val) p_context.code_parts.push_back(sgl::statement::let(p_node_wrapper.get_output_var_name(p_context, index), val))
#define INPUT_EXPRESSION(index) p_node_wrapper.get_input_expression(p_context, index)

#define END(NodeType)  \
	static INITIALIZER_TYPE initializer_instance = INITIALIZER_TYPE(); \
} \
namespace gdrk { \
	template<> inline void _initialize<::godot::NodeType>(gdrk::VisualProgramBuilderContext &p_context, gdrk::VisualShaderNodeWrapper &p_node) { impl ## NodeType::_initialize<::godot::NodeType>(p_context, p_node); } \
	template<> inline bool supported<::godot::NodeType>() { return true; } \
	template<> inline bool declares_uniforms<::godot::NodeType>() { return impl ## NodeType::declares_uniforms<::godot::NodeType>(); } \
	template<> inline uint32_t inlet_count<::godot::NodeType>(ShaderType p_type) { return impl ## NodeType::inlet_count<::godot::NodeType>(p_type); } \
	template<> inline void sg_declare<::godot::NodeType>(ShaderType p_type, VisualProgramBuilderContext & p_context) { impl ## NodeType::sg_declare<::godot::NodeType>(p_type, p_context); } \
	template<> inline void sg_expression<::godot::NodeType>(VisualProgramBuilderContext &p_context, const VisualShaderNodeWrapper &p_node) {  impl ## NodeType::sg_expression<::godot::NodeType>(p_context, p_node); } \
	template<> inline std::string default_input_value<::godot::NodeType>(const VisualShaderNodeWrapper &p_node, uint32_t p_index) { return impl ## NodeType::default_input_value<::godot::NodeType>(p_node, p_index); } \
	template<> inline PortType input_type<::godot::NodeType>(const VisualShaderNodeWrapper &p_node, uint32_t p_index) { return impl ## NodeType::input_type<::godot::NodeType>(p_node, p_index); } \
	template<> inline PortType output_type<::godot::NodeType>(const VisualShaderNodeWrapper &p_node) { return impl ## NodeType::output_type<::godot::NodeType>(p_node); }\
	template<> inline void analyze<::godot::NodeType>(VisualProgramBuilderContext &p_context, const VisualShaderNodeWrapper &p_node) { return impl ## NodeType::analyze<::godot::NodeType>(p_context, p_node); } \
	template<> inline OptionalUniformDescriptor get_uniform_descriptor<::godot::NodeType>(godot::VisualShaderNode *p_node, gdrk::ShaderType p_shader_type, uint32_t p_node_index) { return impl ## NodeType::get_uniform_descriptor<::godot::NodeType>(p_node, p_shader_type, p_node_index); } \
	\
} \
	// clang-format on

namespace gdrk {
class VisualShaderNodeWrapper;
class VisualProgramBuilderContext;

class VisualShaderNodeProcTable {
public:
	static VisualShaderNodeProcTable all_tables[VisualShaderNodeType::Count];
	bool (*castable)(godot::VisualShaderNode *p_node) = nullptr;
	bool (*supported)() = nullptr;
	bool (*declares_uniforms)() = nullptr;
	const char *(*type_name)() = nullptr;
	void (*_initialize)(VisualProgramBuilderContext &, VisualShaderNodeWrapper &) = nullptr;
	uint32_t (*inlet_count)(ShaderType) = nullptr;

	void (*sg_declare)(ShaderType,
			VisualProgramBuilderContext &) = nullptr;
	void (*sg_expression)(VisualProgramBuilderContext &,
			const VisualShaderNodeWrapper &) = nullptr;
	std::string (*default_input_value)(const VisualShaderNodeWrapper &, uint32_t index) = nullptr;
	PortType (*input_type)(const VisualShaderNodeWrapper &, uint32_t index) = nullptr;
	PortType (*output_type)(const VisualShaderNodeWrapper &) = nullptr;
	void (*analyze)(VisualProgramBuilderContext &, const VisualShaderNodeWrapper &) = nullptr;
	OptionalUniformDescriptor (*get_uniform_descriptor)(godot::VisualShaderNode *, gdrk::ShaderType, uint32_t) = nullptr;
};

// clang-format off
template <typename NodeType> bool castable(godot::VisualShaderNode *p_node);
template <typename NodeType> bool supported() { return false; }
template <typename NodeType> bool declares_uniforms() { return false; }
template <typename NodeType> const char *type_name();
template <typename NodeType> void _initialize(VisualProgramBuilderContext &, VisualShaderNodeWrapper &) {};
template <typename NodeType> uint32_t inlet_count(ShaderType) { return 0; }
template <typename NodeType> void sg_declare(ShaderType, VisualProgramBuilderContext &) {}
template <typename NodeType> void sg_expression(VisualProgramBuilderContext &, const VisualShaderNodeWrapper &);
template <typename NodeType> std::string default_input_value(const VisualShaderNodeWrapper &p_node_wrapper, uint32_t p_port_index);
template <typename NodeType> PortType input_type(const VisualShaderNodeWrapper &, uint32_t) { return PortType::UNDEFINED; }
template <typename NodeType> PortType output_type(const VisualShaderNodeWrapper &) { return PortType::UNDEFINED; }
template <typename NodeType> void analyze(VisualProgramBuilderContext &, const VisualShaderNodeWrapper &) {}
template <typename NodeType> OptionalUniformDescriptor get_uniform_descriptor(godot::VisualShaderNode *, gdrk::ShaderType, uint32_t) { return std::nullopt; }
// clang-format on

template <uint32_t I, typename NodeType>
struct VisualShaderNodeProcTableInitializer {
	using ThisClass = VisualShaderNodeProcTableInitializer<I, NodeType>;
	static ThisClass instance;

	VisualShaderNodeProcTableInitializer() {
		if (VisualShaderNodeProcTable::all_tables[I].type_name) {
			ERR_FAIL_MSG(std::format("Redefinition of proc table for VisualShaderNode: {}", *(VisualShaderNodeProcTable::all_tables[I].type_name)()).c_str());
		}
		VisualShaderNodeProcTable &table = VisualShaderNodeProcTable::all_tables[I];
		table.castable = &castable<NodeType>;
		table._initialize = &::gdrk::_initialize<NodeType>;
		table.supported = &supported<NodeType>;
		table.declares_uniforms = &declares_uniforms<NodeType>;
		table.type_name = &type_name<NodeType>;
		table.inlet_count = &inlet_count<NodeType>;
		table.sg_declare = &sg_declare<NodeType>;
		table.sg_expression = &sg_expression<NodeType>;
		table.default_input_value = &default_input_value<NodeType>;
		table.input_type = &input_type<NodeType>;
		table.output_type = &output_type<NodeType>;
		table.analyze = &analyze<NodeType>;
		table.get_uniform_descriptor = &get_uniform_descriptor<NodeType>;
	}
};

// Utilitty class that wraps a godot::VisualShader node with knowledge of its actual type
// allowing the creation a "vtable" to extend the behavior of the godot node. We can then use the
// abstract graph representation uses to visit the graph, but deferred the processing to the vtable
// methods paying the cost of recasting the object every single time: The vtable is resolved once at
// the creation of the wrapper.

class VisualShaderNodeWrapper {
	static bool unused_default;

	// Attach data to the wrapper to provide basic per instance storage
	struct CustomData {
		static constexpr uint8_t custom_data_byte_size = 4;

		template <typename T>
		void set(T &&p_data) {
			static_assert(sizeof(T) <= custom_data_byte_size, "Custom data type is too big");
			memcpy(&data, &p_data, sizeof(T));
		}

		template <typename T>
		T &get() const {
			return *((T *)data);
		}

		uint8_t data[custom_data_byte_size];
	};

public:
	VisualShaderNodeWrapper() {}
	void initialize(VisualProgramBuilderContext &p_context,
			ShaderType p_shader_type,
			VisualShaderNodeType p_node_type,
			godot::VisualShaderNode *p_node,
			uint32_t p_index);
	void initialize(VisualProgramBuilderContext &p_context,
			ShaderType p_type,
			godot::VisualShaderNode *p_node,
			uint32_t p_index);

	inline const char *type_name() const { return vtable->type_name(); }
	inline bool supported() const { return vtable->supported(); }
	inline bool declares_uniforms() const { return vtable->declares_uniforms(); }
	inline uint32_t inlet_count() const { return vtable->inlet_count(shader_type); }
	std::string default_input_value(uint32_t p_port_index) const { return vtable->default_input_value(*this, p_port_index); }
	OptionalUniformDescriptor get_uniform_descriptor() const { return vtable->get_uniform_descriptor(this->node, this->shader_type, this->index); }

	PortType input_type(uint32_t p_port_index) const { return vtable->input_type(*this, p_port_index); }
	PortType output_type() const { return vtable->output_type(*this); }

	void analyze(VisualProgramBuilderContext &p_context) {
		vtable->analyze(p_context, *this);
	}
	std::string get_default_input_value_override(uint32_t p_port_index) const;
	uint32_t sg_declare(VisualProgramBuilderContext &p_context) const;
	uint32_t sg_expression(VisualProgramBuilderContext &p_context) const;
	std::string get_output_var_name(VisualProgramBuilderContext &p_context, uint32_t p_output_port) const;
	std::optional<InputExpression> get_input_var_name(VisualProgramBuilderContext &p_context, uint32_t p_input_index) const;
	std::string get_tmp_var_name(uint32_t p_custom_id = 0) const;
	const VisualShaderNodeWrapper *get_input_node(const VisualProgramBuilderContext &p_context, uint32_t p_input_index) const;

	std::string cast_expression(VisualProgramBuilderContext &p_context, InputExpression &p_expression, uint32_t p_input_index) const;
	std::string get_input_expression(VisualProgramBuilderContext &p_context,
			uint32_t p_input_index,
			bool &p_was_default = VisualShaderNodeWrapper::unused_default) const;
	std::string get_input_expression(VisualProgramBuilderContext &p_context,
			uint32_t p_input_index,
			const char *default_value,
			bool &p_was_default = VisualShaderNodeWrapper::unused_default) const;

	void fill_swizzle_outputs(VisualProgramBuilderContext &p_context, const char *p_var_name = nullptr) const;

	bool is_fragment_shader() const { return shader_type == ShaderType::ST_FRAGMENT; }
	bool is_vertex_shader() const { return shader_type == ShaderType::ST_VERTEX; }

	VisualShaderNodeType node_type;
	ShaderType shader_type;
	VisualShaderNodeProcTable *vtable = nullptr;
	godot::VisualShaderNode *node = nullptr;

	uint32_t index;
	std::string var_name;
	godot::LocalVector<uint32_t> upstream_connections;
	godot::LocalVector<uint32_t> downstream_connections;

	CustomData custom_data;
};

template <typename NodeType>
std::string default_input_value(const VisualShaderNodeWrapper &p_node_wrapper, uint32_t p_port_index) {
	return p_node_wrapper.get_default_input_value_override(p_port_index);
}

} //namespace gdrk

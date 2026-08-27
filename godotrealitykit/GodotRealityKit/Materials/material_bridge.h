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

#undef check
#include <godot_cpp/classes/base_material3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>

#include <cstdint>
#include <format>
#include <optional>

namespace GodotRealityKit {
class SGLMaterial;
}

namespace gdrk {

class TextureLoader;

enum ShaderType {
	ST_VERTEX = 0,
	ST_FRAGMENT,
	ST_COUNT
};

enum MaterialType {
	MATERIAL_TYPE_BASE_MATERIAL3D = 0,
	MATERIAL_TYPE_SHADER_MATERIAL,
	MATERIAL_TYPE_UNKNOWN,
	MATERIAL_TYPE_MAX,
};

inline MaterialType type_from_material(const godot::Material *mat) {
	if (godot::Object::cast_to<const godot::BaseMaterial3D>(mat)) {
		return MATERIAL_TYPE_BASE_MATERIAL3D;
	} else if (godot::Object::cast_to<const godot::ShaderMaterial>(mat)) {
		return MATERIAL_TYPE_SHADER_MATERIAL;
	}
	return MATERIAL_TYPE_UNKNOWN;
}

enum PortType : uint8_t {
	UNDEFINED = 0,
	BOOL,
	INT,
	UINT,
	FLOAT,
	VEC2F,
	VEC3F,
	VEC4F,
	TRANSFORM3D,
	SAMPLER2D,
	SAMPLER3D,
	SAMPLER2DARRAY,

	PT_COUNT,
};

const char *port_type_name(PortType p_type);
PortType get_swizzle_type(PortType p_type);
const char *get_cast_function(PortType p_from, PortType p_to);
std::string stringify_value(PortType p_port_type, const godot::Variant &p_value);
godot::Variant to_port_value(PortType p_port_type, const godot::Variant &p_value);

struct InputExpression {
	PortType type;
	std::string expression;

	// Returns true when the expression can be converted to something
	inline bool to_type(PortType p_expected_type, std::string &p_out) {
		if (type == p_expected_type) {
			p_out = expression;
			return true;
		}

		const char *cast_string = get_cast_function(type, p_expected_type);
		if (!cast_string) {
			return false;
		}

		p_out = std::format("{}({})", cast_string, expression);
		return true;
	}
};

struct Connection {
	uint32_t src_index;
	uint32_t dst_index;
	uint32_t src_port;
	uint32_t dst_port;

	bool is_valid() const {
		return dst_index != UINT32_MAX;
	}

	static Connection Invalid() {
		return {
			.src_index = UINT32_MAX,
			.src_port = UINT32_MAX,
			.dst_index = UINT32_MAX,
			.dst_port = UINT32_MAX,
		};
	}
};

enum VisualShaderNodeType : uint8_t {
	Unknown = 0,

	// Effects
	VisualShaderNodeBillboard,
	VisualShaderNodeDistanceFade,
	VisualShaderNodeProximityFade,

	// Constants
	VisualShaderNodeBooleanConstant,
	VisualShaderNodeColorConstant,
	VisualShaderNodeFloatConstant,
	VisualShaderNodeIntConstant,
	VisualShaderNodeUIntConstant,
	VisualShaderNodeTransformConstant,
	VisualShaderNodeVec2Constant,
	VisualShaderNodeVec3Constant,
	VisualShaderNodeVec4Constant,

	// Parameters
	VisualShaderNodeBooleanParameter,
	VisualShaderNodeColorParameter,
	VisualShaderNodeCubemapParameter,
	VisualShaderNodeFloatParameter,
	VisualShaderNodeIntParameter,
	VisualShaderNodeTexture2DArrayParameter,
	VisualShaderNodeTexture2DParameter,
	VisualShaderNodeTexture3DParameter,
	VisualShaderNodeTextureParameter,
	VisualShaderNodeTextureParameterTriplanar,
	VisualShaderNodeTransformParameter,
	VisualShaderNodeUIntParameter,
	VisualShaderNodeVec2Parameter,
	VisualShaderNodeVec3Parameter,
	VisualShaderNodeVec4Parameter,
	VisualShaderNodeParameterRef,

	// Math Operations
	VisualShaderNodeClamp,
	VisualShaderNodeColorFunc,
	VisualShaderNodeColorOp,
	VisualShaderNodeDerivativeFunc,
	VisualShaderNodeDeterminant,
	VisualShaderNodeDotProduct,
	VisualShaderNodeFaceForward,
	VisualShaderNodeFloatFunc,
	VisualShaderNodeFloatOp,
	VisualShaderNodeFresnel,
	VisualShaderNodeIntFunc,
	VisualShaderNodeIntOp,
	VisualShaderNodeMix,
	VisualShaderNodeMultiplyAdd,
	VisualShaderNodeOuterProduct,
	VisualShaderNodeRandomRange,
	VisualShaderNodeRemap,
	VisualShaderNodeRotationByAxis,
	VisualShaderNodeSmoothStep,
	VisualShaderNodeStep,
	VisualShaderNodeTransformFunc,
	VisualShaderNodeTransformOp,
	VisualShaderNodeUIntFunc,
	VisualShaderNodeUIntOp,
	VisualShaderNodeUVFunc,
	VisualShaderNodeUVPolarCoord,
	VisualShaderNodeVectorDistance,
	VisualShaderNodeVectorFunc,
	VisualShaderNodeVectorLen,
	VisualShaderNodeVectorOp,
	VisualShaderNodeVectorRefract,

	// Utility
	VisualShaderNodeComment,
	VisualShaderNodeCompare,
	VisualShaderNodeExpression,
	VisualShaderNodeGlobalExpression,
	VisualShaderNodeIf,
	VisualShaderNodeIs,
	VisualShaderNodeReroute,
	VisualShaderNodeSwitch,

	// Variant Operations
	VisualShaderNodeTransformCompose,
	VisualShaderNodeTransformDecompose,
	VisualShaderNodeTransformVecMult,
	VisualShaderNodeVectorCompose,
	VisualShaderNodeVectorDecompose,

	// Textures and Sampling
	VisualShaderNodeCubemap,
	VisualShaderNodeCurveTexture,
	VisualShaderNodeCurveXYZTexture,
	VisualShaderNodeSample3D,
	VisualShaderNodeTexture,
	VisualShaderNodeTexture2DArray,
	VisualShaderNodeTexture3D,
	VisualShaderNodeTextureSDF,
	VisualShaderNodeTextureSDFNormal,

	// Screen and depth function
	VisualShaderNodeLinearSceneDepth,
	VisualShaderNodeScreenNormalWorldSpace,
	VisualShaderNodeScreenUVToSDF,
	VisualShaderNodeSDFRaymarch,
	VisualShaderNodeSDFToScreenUV,
	VisualShaderNodeWorldPositionFromDepth,

	// Particle System Nodes
	VisualShaderNodeParticleAccelerator,
	VisualShaderNodeParticleBoxEmitter,
	VisualShaderNodeParticleConeVelocity,
	VisualShaderNodeParticleEmit,
	VisualShaderNodeParticleMeshEmitter,
	VisualShaderNodeParticleMultiplyByAxisAngle,
	VisualShaderNodeParticleOutput,
	VisualShaderNodeParticleRandomness,
	VisualShaderNodeParticleRingEmitter,
	VisualShaderNodeParticleSphereEmitter,

	// Varyings
	VisualShaderNodeVaryingGetter,
	VisualShaderNodeVaryingSetter,

	// Input / Output Nodes
	VisualShaderNodeInput,
	VisualShaderNodeOutput,
	VisualShaderNodeCustom,
	VisualShaderNodeFrame,
	VisualShaderNodeGroupBase,
	VisualShaderNodeParticleEmitter,
	VisualShaderNodeResizableBase,
	VisualShaderNodeVarying,
	VisualShaderNodeVectorBase,
	VisualShaderNodeConstant,
	VisualShaderNodeParameter,

	Count,
};

struct UniformDescriptor {
	PortType type;
	godot::StringName name;
	godot::Variant default_value;
	bool srgb_texture = false;

	// Filled up by the builder, could be a separate structure inside the context
	// but that's complicates things
	uint32_t node_index;
	gdrk::ShaderType shader_type;
	VisualShaderNodeType node_type;
};

using OptionalUniformDescriptor = std::optional<UniformDescriptor>;

void update_material_parameter(int p_index, const UniformDescriptor &p_uniform, GodotRealityKit::SGLMaterial &p_sgl_material, godot::Variant &p_value, TextureLoader &p_textures);

} //namespace gdrk

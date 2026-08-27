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

#include "../visual_program_builder.h"
#include "../visual_shader_node_wrapper.h"

#include <godot_cpp/classes/visual_shader_node_billboard.hpp>
#include <godot_cpp/classes/visual_shader_node_boolean_constant.hpp>
#include <godot_cpp/classes/visual_shader_node_boolean_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_clamp.hpp>
#include <godot_cpp/classes/visual_shader_node_color_constant.hpp>
#include <godot_cpp/classes/visual_shader_node_color_func.hpp>
#include <godot_cpp/classes/visual_shader_node_color_op.hpp>
#include <godot_cpp/classes/visual_shader_node_color_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_comment.hpp>
#include <godot_cpp/classes/visual_shader_node_compare.hpp>
#include <godot_cpp/classes/visual_shader_node_constant.hpp>
#include <godot_cpp/classes/visual_shader_node_cubemap.hpp>
#include <godot_cpp/classes/visual_shader_node_cubemap_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_curve_texture.hpp>
#include <godot_cpp/classes/visual_shader_node_curve_xyz_texture.hpp>
#include <godot_cpp/classes/visual_shader_node_custom.hpp>
#include <godot_cpp/classes/visual_shader_node_derivative_func.hpp>
#include <godot_cpp/classes/visual_shader_node_determinant.hpp>
#include <godot_cpp/classes/visual_shader_node_distance_fade.hpp>
#include <godot_cpp/classes/visual_shader_node_dot_product.hpp>
#include <godot_cpp/classes/visual_shader_node_expression.hpp>
#include <godot_cpp/classes/visual_shader_node_face_forward.hpp>
#include <godot_cpp/classes/visual_shader_node_float_constant.hpp>
#include <godot_cpp/classes/visual_shader_node_float_func.hpp>
#include <godot_cpp/classes/visual_shader_node_float_op.hpp>
#include <godot_cpp/classes/visual_shader_node_float_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_frame.hpp>
#include <godot_cpp/classes/visual_shader_node_fresnel.hpp>
#include <godot_cpp/classes/visual_shader_node_global_expression.hpp>
#include <godot_cpp/classes/visual_shader_node_group_base.hpp>
#include <godot_cpp/classes/visual_shader_node_if.hpp>
#include <godot_cpp/classes/visual_shader_node_input.hpp>
#include <godot_cpp/classes/visual_shader_node_int_constant.hpp>
#include <godot_cpp/classes/visual_shader_node_int_func.hpp>
#include <godot_cpp/classes/visual_shader_node_int_op.hpp>
#include <godot_cpp/classes/visual_shader_node_int_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_is.hpp>
#include <godot_cpp/classes/visual_shader_node_linear_scene_depth.hpp>
#include <godot_cpp/classes/visual_shader_node_mix.hpp>
#include <godot_cpp/classes/visual_shader_node_multiply_add.hpp>
#include <godot_cpp/classes/visual_shader_node_outer_product.hpp>
#include <godot_cpp/classes/visual_shader_node_output.hpp>
#include <godot_cpp/classes/visual_shader_node_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_parameter_ref.hpp>
#include <godot_cpp/classes/visual_shader_node_particle_accelerator.hpp>
#include <godot_cpp/classes/visual_shader_node_particle_box_emitter.hpp>
#include <godot_cpp/classes/visual_shader_node_particle_cone_velocity.hpp>
#include <godot_cpp/classes/visual_shader_node_particle_emit.hpp>
#include <godot_cpp/classes/visual_shader_node_particle_emitter.hpp>
#include <godot_cpp/classes/visual_shader_node_particle_mesh_emitter.hpp>
#include <godot_cpp/classes/visual_shader_node_particle_multiply_by_axis_angle.hpp>
#include <godot_cpp/classes/visual_shader_node_particle_output.hpp>
#include <godot_cpp/classes/visual_shader_node_particle_randomness.hpp>
#include <godot_cpp/classes/visual_shader_node_particle_ring_emitter.hpp>
#include <godot_cpp/classes/visual_shader_node_particle_sphere_emitter.hpp>
#include <godot_cpp/classes/visual_shader_node_proximity_fade.hpp>
#include <godot_cpp/classes/visual_shader_node_random_range.hpp>
#include <godot_cpp/classes/visual_shader_node_remap.hpp>
#include <godot_cpp/classes/visual_shader_node_reroute.hpp>
#include <godot_cpp/classes/visual_shader_node_resizable_base.hpp>
#include <godot_cpp/classes/visual_shader_node_rotation_by_axis.hpp>
#include <godot_cpp/classes/visual_shader_node_sample3d.hpp>
#include <godot_cpp/classes/visual_shader_node_screen_normal_world_space.hpp>
#include <godot_cpp/classes/visual_shader_node_screen_uv_to_sdf.hpp>
#include <godot_cpp/classes/visual_shader_node_sdf_raymarch.hpp>
#include <godot_cpp/classes/visual_shader_node_sdf_to_screen_uv.hpp>
#include <godot_cpp/classes/visual_shader_node_smooth_step.hpp>
#include <godot_cpp/classes/visual_shader_node_step.hpp>
#include <godot_cpp/classes/visual_shader_node_switch.hpp>
#include <godot_cpp/classes/visual_shader_node_texture.hpp>
#include <godot_cpp/classes/visual_shader_node_texture2d_array.hpp>
#include <godot_cpp/classes/visual_shader_node_texture2d_array_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_texture2d_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_texture3d.hpp>
#include <godot_cpp/classes/visual_shader_node_texture3d_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_texture_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_texture_parameter_triplanar.hpp>
#include <godot_cpp/classes/visual_shader_node_texture_sdf.hpp>
#include <godot_cpp/classes/visual_shader_node_texture_sdf_normal.hpp>
#include <godot_cpp/classes/visual_shader_node_transform_compose.hpp>
#include <godot_cpp/classes/visual_shader_node_transform_constant.hpp>
#include <godot_cpp/classes/visual_shader_node_transform_decompose.hpp>
#include <godot_cpp/classes/visual_shader_node_transform_func.hpp>
#include <godot_cpp/classes/visual_shader_node_transform_op.hpp>
#include <godot_cpp/classes/visual_shader_node_transform_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_transform_vec_mult.hpp>
#include <godot_cpp/classes/visual_shader_node_u_int_constant.hpp>
#include <godot_cpp/classes/visual_shader_node_u_int_func.hpp>
#include <godot_cpp/classes/visual_shader_node_u_int_op.hpp>
#include <godot_cpp/classes/visual_shader_node_u_int_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_uv_func.hpp>
#include <godot_cpp/classes/visual_shader_node_uv_polar_coord.hpp>
#include <godot_cpp/classes/visual_shader_node_varying.hpp>
#include <godot_cpp/classes/visual_shader_node_varying_getter.hpp>
#include <godot_cpp/classes/visual_shader_node_varying_setter.hpp>
#include <godot_cpp/classes/visual_shader_node_vec2_constant.hpp>
#include <godot_cpp/classes/visual_shader_node_vec2_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_vec3_constant.hpp>
#include <godot_cpp/classes/visual_shader_node_vec3_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_vec4_constant.hpp>
#include <godot_cpp/classes/visual_shader_node_vec4_parameter.hpp>
#include <godot_cpp/classes/visual_shader_node_vector_base.hpp>
#include <godot_cpp/classes/visual_shader_node_vector_compose.hpp>
#include <godot_cpp/classes/visual_shader_node_vector_decompose.hpp>
#include <godot_cpp/classes/visual_shader_node_vector_distance.hpp>
#include <godot_cpp/classes/visual_shader_node_vector_func.hpp>
#include <godot_cpp/classes/visual_shader_node_vector_len.hpp>
#include <godot_cpp/classes/visual_shader_node_vector_op.hpp>
#include <godot_cpp/classes/visual_shader_node_vector_refract.hpp>
#include <godot_cpp/classes/visual_shader_node_world_position_from_depth.hpp>

#include <format>

using namespace gdrk;

// Doc hub: https://docs.godotengine.org/en/stable/classes/class_visualshadernode.html

// Effects
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeBillboard); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeDistanceFade); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeProximityFade); 

// Constants
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeBooleanConstant);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeColorConstant);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeFloatConstant);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeIntConstant);
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeUIntConstant, "uint not supported");
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTransformConstant);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVec2Constant);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVec3Constant);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVec4Constant);

// Parameters
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeBooleanParameter);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeColorParameter);
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeCubemapParameter); 
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeFloatParameter);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeIntParameter);
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTexture2DArrayParameter); 
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTexture2DParameter);
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTexture3DParameter); 
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeTextureParameter, "Intermediate Class");
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTextureParameterTriplanar); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTransformParameter); 
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeUIntParameter, "uint not supported");
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVec2Parameter);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVec3Parameter);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVec4Parameter);
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeParameterRef); 

// Math Operations
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeClamp);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeColorFunc);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeColorOp);
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeDerivativeFunc); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeDeterminant); 
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeDotProduct);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeFaceForward);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeFloatFunc);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeFloatOp);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeFresnel);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeIntFunc);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeIntOp);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeMix);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeMultiplyAdd);
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeOuterProduct); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeRandomRange); 
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeRemap);
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeRotationByAxis); 
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeSmoothStep);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeStep);
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTransformFunc); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTransformOp); 
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeUIntFunc, "uint not supported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeUIntOp, "uint not supported");
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeUVFunc); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeUVPolarCoord); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVectorDistance); 
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVectorFunc);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVectorLen);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVectorOp);
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVectorRefract); 

// Utility
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeComment, "Editor use only");
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeCompare);
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeExpression, "Arbitrary code not supported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeGlobalExpression, "Arbitrary code not supported");
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeIf);
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeIs); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeReroute); 
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeSwitch);

// Variant Operations
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTransformCompose); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTransformDecompose); 
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTransformVecMult);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVectorCompose);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVectorDecompose);

// Textures and Sampling
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeCubemap); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeCurveTexture); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeCurveXYZTexture); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeSample3D); 
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTexture);
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTexture2DArray); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTexture3D); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTextureSDF); 
DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeTextureSDFNormal); 

// Screen and depth function
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeLinearSceneDepth, "Unsupported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeScreenNormalWorldSpace, "Unsupported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeScreenUVToSDF, "Unsupported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeSDFRaymarch, "Unsupported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeSDFToScreenUV, "Unsupported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeWorldPositionFromDepth, "Unsupported");

// Particle System Nodes
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeParticleAccelerator, "Particle shader not supported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeParticleBoxEmitter, "Particle shader not supported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeParticleConeVelocity, "Particle shader not supported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeParticleEmit, "Particle shader not supported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeParticleMeshEmitter, "Particle shader not supported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeParticleMultiplyByAxisAngle, "Particle shader not supported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeParticleOutput, "Particle shader not supported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeParticleRandomness, "Particle shader not supported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeParticleRingEmitter, "Particle shader not supported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeParticleSphereEmitter, "Particle shader not supported");

// Varyings
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVaryingGetter);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeVaryingSetter);

// Input Nodes
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeInput);
//DEFINE_UNIMPLEMENTED_NODE(VisualShaderNodeOutput);
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeCustom, "Arbitrary code not supported");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeFrame, "Editor us only");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeParticleEmitter, "Intermediate Class");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeVarying, "Intermediate Class"); // Intermediate Class
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeConstant, "Intermediate Class"); // Intermediate Class
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeParameter, "Intermediate Class"); // Intermediate Class

// Base classes, should not be implemented
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeGroupBase, "Intermediate Class");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeResizableBase, "Intermediate Class");
DEFINE_UNSUPPORTED_NODE(VisualShaderNodeVectorBase, "Intermediate Class");

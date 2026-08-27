//
//  PHASEUtils.h
//
//  Copyright © 2026 Apple Inc.
//

#ifndef PHASE_UTILS_H
#define PHASE_UTILS_H

#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <simd/simd.h>
#import <Foundation/Foundation.h>
#import "PHASEWrapper.h"

namespace PHASEUtils {
    inline simd_float4x4 transform_to_simd_float4x4(const godot::Transform3D& transform) {
        const godot::Basis& basis = transform.basis;
        const godot::Vector3& origin = transform.origin;

        // simd_float4x4 is column-major, so we construct columns
        return simd_matrix(
            simd_make_float4(basis[0][0], basis[0][1], basis[0][2], 0.0f),  // column 0
            simd_make_float4(basis[1][0], basis[1][1], basis[1][2], 0.0f),  // column 1
            simd_make_float4(basis[2][0], basis[2][1], basis[2][2], 0.0f),  // column 2
            simd_make_float4(origin.x, origin.y, origin.z, 1.0f)            // column 3 (translation)
        );
    }

    inline godot::Ref<godot::Mesh> get_mesh_from_node_path(godot::Node* context_node, const godot::NodePath& node_path) {
        if (node_path.is_empty()) {
            return godot::Ref<godot::Mesh>();
        }

        godot::Node* node = context_node->get_node_or_null(node_path);
        if (!node) {
            return godot::Ref<godot::Mesh>();
        }

        godot::MeshInstance3D* mesh_instance = godot::Object::cast_to<godot::MeshInstance3D>(node);
        if (mesh_instance) {
            return mesh_instance->get_mesh();
        }

        return godot::Ref<godot::Mesh>();
    }

    inline void extract_mesh_surface_data(const godot::Ref<godot::Mesh>& p_mesh,
                                          godot::PackedFloat32Array& positions,
                                          godot::PackedFloat32Array& normals,
                                          godot::PackedInt32Array& indices) {
        if (p_mesh.is_null()) {
            return;
        }

        for (int surface_idx = 0; surface_idx < p_mesh->get_surface_count(); surface_idx++) {
            godot::Array mesh_arrays = p_mesh->surface_get_arrays(surface_idx);

            if (mesh_arrays.size() <= godot::Mesh::ARRAY_VERTEX) {
                continue;
            }

            godot::PackedVector3Array vertices = mesh_arrays[godot::Mesh::ARRAY_VERTEX];

            godot::PackedVector3Array surface_normals;
            if (mesh_arrays.size() > godot::Mesh::ARRAY_NORMAL &&
                mesh_arrays[godot::Mesh::ARRAY_NORMAL].get_type() != godot::Variant::NIL) {
                surface_normals = mesh_arrays[godot::Mesh::ARRAY_NORMAL];
            } else {
                surface_normals.resize(vertices.size());
                for (int i = 0; i < vertices.size(); i++) {
                    surface_normals[i] = godot::Vector3(0, 1, 0);
                }
            }

            godot::PackedInt32Array surface_indices;
            if (mesh_arrays.size() > godot::Mesh::ARRAY_INDEX &&
                mesh_arrays[godot::Mesh::ARRAY_INDEX].get_type() != godot::Variant::NIL) {
                surface_indices = mesh_arrays[godot::Mesh::ARRAY_INDEX];
            } else {
                surface_indices.resize(vertices.size());
                for (int i = 0; i < vertices.size(); i++) {
                    surface_indices[i] = i;
                }
            }

            int vertex_offset = positions.size() / 3;

            for (int i = 0; i < vertices.size(); i++) {
                const godot::Vector3& vertex = vertices[i];
                positions.append(vertex.x);
                positions.append(vertex.y);
                positions.append(vertex.z);
            }

            for (int i = 0; i < surface_normals.size(); i++) {
                const godot::Vector3& normal = surface_normals[i];
                normals.append(normal.x);
                normals.append(normal.y);
                normals.append(normal.z);
            }

            for (int i = 0; i < surface_indices.size(); i++) {
                indices.append(surface_indices[i] + vertex_offset);
            }
        }
    }

    inline const char* material_preset_to_string(int preset) {
        switch (preset) {
            case 0: return "Cardboard";
            case 1: return "Glass";
            case 2: return "Brick";
            case 3: return "Concrete";
            case 4: return "Drywall";
            case 5: return "Wood";
            default: return "Cardboard";
        }
    }

    inline void create_and_set_material(PHASEEngineWrapper* engine, int64_t occluderId, int materialPreset) {
        const char* materialString = material_preset_to_string(materialPreset);
        [engine createMaterialWithName:[NSString stringWithUTF8String:materialString]
                                preset:(MaterialPreset)materialPreset];
        [engine setOccluderMaterialWithId:occluderId
                             materialName:[NSString stringWithUTF8String:materialString]];
    }
}

#endif // PHASE_UTILS_H
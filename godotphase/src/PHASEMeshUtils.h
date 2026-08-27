//
//  PHASEMeshUtils.h
//
//  Copyright © 2026 Apple Inc.
//

#ifndef PHASE_MESH_UTILS_H
#define PHASE_MESH_UTILS_H

#import <Foundation/Foundation.h>
#import <ModelIO/ModelIO.h>
#import "PHASEWrapper.h"
#include "PHASEUtils.h"
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/node.hpp>

namespace PHASEMeshUtils {
    inline MDLMesh* CreateMDLMesh(int inVertCount, const float* inPositions, const float* inNormals, int inIndexCount, const uint32_t* inIndices) {
        if (inVertCount == 0 || inPositions == nullptr || inNormals == nullptr || inIndexCount == 0 || inIndices == nullptr) {
            return nullptr;
        }

        MDLMesh* mdlMesh = [[MDLMesh alloc] init];

        mdlMesh.vertexCount = inVertCount;

        [mdlMesh addAttributeWithName:MDLVertexAttributePosition format:MDLVertexFormatFloat3];
        NSData* positionNsData = [NSData dataWithBytes:inPositions length:inVertCount * 3 * sizeof(float)];
        [mdlMesh.vertexBuffers[0] fillData:positionNsData offset:0];

        [mdlMesh addAttributeWithName:MDLVertexAttributeNormal format:MDLVertexFormatFloat3];
        NSData* normalNsData = [NSData dataWithBytes:inNormals length:inVertCount * 3 * sizeof(float)];
        [mdlMesh.vertexBuffers[1] fillData:normalNsData offset:0];

        size_t numSubmeshes = 1;
        NSMutableArray<MDLSubmesh*>* arrayOfSubmeshes = [[NSMutableArray alloc] initWithCapacity:numSubmeshes];

        const auto indexSize = inIndexCount * sizeof(uint32_t);
        NSData* nsDataIdx = [NSData dataWithBytes:inIndices length:indexSize];
        MDLMeshBufferData* idxBuffer = [[MDLMeshBufferData alloc] initWithType:MDLMeshBufferTypeIndex length:indexSize];
        [idxBuffer fillData:nsDataIdx offset:0];

        MDLScatteringFunction* scatteringFunction = [MDLPhysicallyPlausibleScatteringFunction new];
        MDLMaterial* material = [[MDLMaterial alloc] initWithName:@"plausibleMaterial" scatteringFunction:scatteringFunction];

        MDLSubmesh* submesh = [[MDLSubmesh alloc] initWithIndexBuffer:idxBuffer
                                                           indexCount:inIndexCount
                                                            indexType:MDLIndexBitDepthUInt32
                                                         geometryType:MDLGeometryTypeTriangles
                                                             material:material];

        [arrayOfSubmeshes addObject:submesh];
        mdlMesh.submeshes = arrayOfSubmeshes;

        return mdlMesh;
    }

    inline int64_t CreatePHASESourceWithMesh(godot::Node* context_node, const godot::NodePath& mesh_node_path, PHASEEngineWrapper* engine) {
        using namespace godot;

        Ref<Mesh> mesh = PHASEUtils::get_mesh_from_node_path(context_node, mesh_node_path);
        if (mesh.is_null()) {
            return PHASEInvalidInstanceHandle;
        }

        PackedFloat32Array positions;
        PackedFloat32Array normals;
        PackedInt32Array indices;
        PHASEUtils::extract_mesh_surface_data(mesh, positions, normals, indices);

        if (positions.size() == 0 || indices.size() == 0) {
            return PHASEInvalidInstanceHandle;
        }

        int vertCount = positions.size() / 3;
        int indexCount = indices.size();
        const uint32_t* indicesPtr = reinterpret_cast<const uint32_t*>(indices.ptr());

        MDLMesh* mdlMesh = CreateMDLMesh(vertCount, positions.ptr(), normals.ptr(), indexCount, indicesPtr);
        if (mdlMesh == nullptr) {
            return PHASEInvalidInstanceHandle;
        }

        return [engine createSourceWithMesh:mdlMesh];
    }

    inline int64_t CreatePHASEOccluderWithMesh(godot::Node* context_node, const godot::NodePath& mesh_node_path, PHASEEngineWrapper* engine) {
        using namespace godot;

        Ref<Mesh> mesh = PHASEUtils::get_mesh_from_node_path(context_node, mesh_node_path);
        if (mesh.is_null()) {
            return PHASEInvalidInstanceHandle;
        }

        PackedFloat32Array positions;
        PackedFloat32Array normals;
        PackedInt32Array indices;
        PHASEUtils::extract_mesh_surface_data(mesh, positions, normals, indices);

        if (positions.size() == 0 || indices.size() == 0) {
            return PHASEInvalidInstanceHandle;
        }

        int vertCount = positions.size() / 3;
        int indexCount = indices.size();
        const uint32_t* indicesPtr = reinterpret_cast<const uint32_t*>(indices.ptr());

        MDLMesh* mdlMesh = CreateMDLMesh(vertCount, positions.ptr(), normals.ptr(), indexCount, indicesPtr);
        if (mdlMesh == nullptr) {
            return PHASEInvalidInstanceHandle;
        }

        return [engine createOccluderWithMesh:mdlMesh];
    }
}

#endif // PHASE_MESH_UTILS_H

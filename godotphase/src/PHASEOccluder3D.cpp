//
//  PHASEOccluder3D.cpp
//
//  Copyright © 2026 Apple Inc.
//

#include "PHASEOccluder3D.h"
#import "PHASEWrapper.h"
#include "PHASEUtils.h"
#include "PHASEMeshUtils.h"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void PHASEOccluder3D::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_material", "material"), &PHASEOccluder3D::set_material);
    ClassDB::bind_method(D_METHOD("get_material"), &PHASEOccluder3D::get_material);

    ClassDB::bind_method(D_METHOD("set_mesh_node_path", "path"), &PHASEOccluder3D::set_mesh_node_path);
    ClassDB::bind_method(D_METHOD("get_mesh_node_path"), &PHASEOccluder3D::get_mesh_node_path);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "material", PROPERTY_HINT_ENUM, "Cardboard,Glass,Brick,Concrete,Drywall,Wood"), "set_material", "get_material");
    ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "mesh_node_path", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "MeshInstance3D"), "set_mesh_node_path", "get_mesh_node_path");

    BIND_ENUM_CONSTANT(MaterialPresetCardboard);
    BIND_ENUM_CONSTANT(MaterialPresetGlass);
    BIND_ENUM_CONSTANT(MaterialPresetBrick);
    BIND_ENUM_CONSTANT(MaterialPresetConcrete);
    BIND_ENUM_CONSTANT(MaterialPresetDrywall);
    BIND_ENUM_CONSTANT(MaterialPresetWood);
}

PHASEOccluder3D::PHASEOccluder3D() {
    material = MaterialPresetCardboard;
    occluderId = PHASEInvalidInstanceHandle;
    mesh_node_path = NodePath();
}

PHASEOccluder3D::~PHASEOccluder3D() {
    if (occluderId != PHASEInvalidInstanceHandle) {
        PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
        [engine destroyOccluderWithId:occluderId];
    }
}

void PHASEOccluder3D::_notification(int p_what) {
    switch (p_what) {
        case NOTIFICATION_READY: phase_ready(); break;
        case NOTIFICATION_PHYSICS_PROCESS: phase_physics_process(); break;
    }
}

void PHASEOccluder3D::phase_ready() {
    set_physics_process(true);
    _create_occluder_from_mesh();
}

void PHASEOccluder3D::phase_physics_process() {
    if (occluderId == PHASEInvalidInstanceHandle) return;
    Transform3D transform = get_global_transform();
    simd_float4x4 matrix = PHASEUtils::transform_to_simd_float4x4(transform);
    PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
    [engine setOccluderTransformWithId:occluderId transform:matrix];
}

void PHASEOccluder3D::set_material(godot::PHASEMaterialPreset p_material) {
    material = p_material;
    if (occluderId != PHASEInvalidInstanceHandle) {
        const char* materialString = PHASEUtils::material_preset_to_string(material);
        PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
        [engine setOccluderMaterialWithId:occluderId
                             materialName:[NSString stringWithUTF8String:materialString]];
    }
}

godot::PHASEMaterialPreset PHASEOccluder3D::get_material() const {
    return material;
}

void PHASEOccluder3D::set_mesh_node_path(const NodePath &p_path) {
    mesh_node_path = p_path;
    if (is_inside_tree()) {
        if (occluderId != PHASEInvalidInstanceHandle) {
            PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
            [engine destroyOccluderWithId:occluderId];
            occluderId = PHASEInvalidInstanceHandle;
        }
        _create_occluder_from_mesh();
    }
}

NodePath PHASEOccluder3D::get_mesh_node_path() const {
    return mesh_node_path;
}

void PHASEOccluder3D::_create_occluder_from_mesh() {
    PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];

    @try {
        occluderId = PHASEMeshUtils::CreatePHASEOccluderWithMesh(this, mesh_node_path, engine);

        if (occluderId != PHASEInvalidInstanceHandle) {
            PHASEUtils::create_and_set_material(engine, occluderId, material);
        } else {
            ERR_PRINT("PHASEOccluder3D: Failed to create PHASE occluder");
        }
    }
    @catch (NSException* exception) {
        ERR_PRINT("PHASEOccluder3D: Exception creating occluder: " + String([exception.reason UTF8String]));
        occluderId = PHASEInvalidInstanceHandle;
    }
}

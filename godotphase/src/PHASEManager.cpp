//
//  PHASEManager.cpp
//
//  Copyright © 2026 Apple Inc.
//

#include "PHASEManager.h"
#import "PHASEWrapper.h"
#include "PHASEUtils.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/main_loop.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/timer.hpp>

using namespace godot;

void PHASEManager::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize_engine"), &PHASEManager::initialize_engine);
    ClassDB::bind_method(D_METHOD("shutdown_engine"), &PHASEManager::shutdown_engine);
    ClassDB::bind_method(D_METHOD("is_engine_initialized"), &PHASEManager::is_engine_initialized);

    ClassDB::bind_method(D_METHOD("set_scene_reverb_preset", "preset"), &PHASEManager::set_scene_reverb_preset);
    ClassDB::bind_method(D_METHOD("get_scene_reverb_preset"), &PHASEManager::get_scene_reverb_preset);

#if TARGET_OS_VISION
    ClassDB::bind_method(D_METHOD("set_world_transform", "transform"), &PHASEManager::set_world_transform);
#endif
    ClassDB::bind_method(D_METHOD("is_client_rendering_active"), &PHASEManager::is_client_rendering_active);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "scene_reverb_preset", PROPERTY_HINT_ENUM,
        "None,Small Room,Medium Room,Large Room,Large Room 2,Medium Chamber,Large Chamber,Medium Hall,Medium Hall 2,Medium Hall 3,Large Hall,Cathedral"),
        "set_scene_reverb_preset", "get_scene_reverb_preset");

    BIND_ENUM_CONSTANT(REVERB_PRESET_NONE);
    BIND_ENUM_CONSTANT(REVERB_PRESET_SMALL_ROOM);
    BIND_ENUM_CONSTANT(REVERB_PRESET_MEDIUM_ROOM);
    BIND_ENUM_CONSTANT(REVERB_PRESET_LARGE_ROOM);
    BIND_ENUM_CONSTANT(REVERB_PRESET_LARGE_ROOM_2);
    BIND_ENUM_CONSTANT(REVERB_PRESET_MEDIUM_CHAMBER);
    BIND_ENUM_CONSTANT(REVERB_PRESET_LARGE_CHAMBER);
    BIND_ENUM_CONSTANT(REVERB_PRESET_MEDIUM_HALL);
    BIND_ENUM_CONSTANT(REVERB_PRESET_MEDIUM_HALL_2);
    BIND_ENUM_CONSTANT(REVERB_PRESET_MEDIUM_HALL_3);
    BIND_ENUM_CONSTANT(REVERB_PRESET_LARGE_HALL);
    BIND_ENUM_CONSTANT(REVERB_PRESET_CATHEDRAL);

    BIND_ENUM_CONSTANT(CLIENT_RENDERING_MODE_AUTOMATIC);
    BIND_ENUM_CONSTANT(CLIENT_RENDERING_MODE_ENABLED);
    BIND_ENUM_CONSTANT(CLIENT_RENDERING_MODE_DISABLED);

    ProjectSettings *ps = ProjectSettings::get_singleton();
    if (!ps->has_setting("phase/client_rendering_mode")) {
        ps->set_setting("phase/client_rendering_mode", CLIENT_RENDERING_MODE_AUTOMATIC);
    }
    ps->set_initial_value("phase/client_rendering_mode", CLIENT_RENDERING_MODE_AUTOMATIC);
    Dictionary info;
    info["name"] = "phase/client_rendering_mode";
    info["type"] = (int)Variant::INT;
    info["hint"] = PROPERTY_HINT_ENUM;
    info["hint_string"] = "Automatic,Enabled,Disabled";
    ps->add_property_info(info);
}

PHASEManager::PHASEManager() {
    engine_initialized = false;
    current_reverb_preset = REVERB_PRESET_SMALL_ROOM;
    client_rendering_active = false;
}

PHASEManager::~PHASEManager() {
    shutdown_engine();
}

void PHASEManager::_notification(int p_what) {
    switch (p_what) {
        case NOTIFICATION_READY: phase_ready(); break;
        case NOTIFICATION_PHYSICS_PROCESS: phase_physics_process(); break;
    }
}

void PHASEManager::phase_ready() {
    if (!Engine::get_singleton()->is_editor_hint()) {
        set_physics_process(true);
    }
    initialize_engine();
}

void PHASEManager::phase_physics_process() {
    if (engine_initialized) {
        PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
        [engine update];
    }
}

bool PHASEManager::initialize_engine() {
    if (engine_initialized) {
        return true;
    }

#if TARGET_OS_VISION
    client_rendering_active = resolve_client_rendering_mode();
    [PHASEEngineWrapper setUseClientRenderingMode:client_rendering_active];
#endif

    PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
    if (![engine start]) {
        ERR_PRINT("Failed to start PHASE Engine.");
        return false;
    }

    engine_initialized = true;
    set_scene_reverb_preset(static_cast<GodotPHASEReverbPreset>(current_reverb_preset));

    return true;
}

void PHASEManager::shutdown_engine() {
    if (!engine_initialized) {
        return;
    }

    PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
    [engine stop];
    engine_initialized = false;
}

bool PHASEManager::is_engine_initialized() const {
    return engine_initialized;
}

void PHASEManager::set_scene_reverb_preset(GodotPHASEReverbPreset preset) {
    current_reverb_preset = preset;
    if (engine_initialized) {
        PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
        [engine setSceneReverbWithPresetIndex:current_reverb_preset];
    }
}

GodotPHASEReverbPreset PHASEManager::get_scene_reverb_preset() const {
    return static_cast<GodotPHASEReverbPreset>(current_reverb_preset);
}


#if TARGET_OS_VISION
bool PHASEManager::set_world_transform(const Transform3D &transform) {
    if (engine_initialized) {
        PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
	    simd_float4x4 matrix = PHASEUtils::transform_to_simd_float4x4(transform);
        bool result = [engine setWorldTransform:matrix];
        return result;
    } else {
        return false;
    }
}
#endif

bool PHASEManager::resolve_client_rendering_mode() const {
    const int mode = (int)ProjectSettings::get_singleton()->get_setting("phase/client_rendering_mode", CLIENT_RENDERING_MODE_AUTOMATIC);
    switch (mode) {
        case CLIENT_RENDERING_MODE_ENABLED:
            return true;
        case CLIENT_RENDERING_MODE_DISABLED:
            return false;
        default:
            break;
    }

    MainLoop *main_loop = Engine::get_singleton()->get_main_loop();
    const bool detected = main_loop != nullptr && main_loop->is_class("RealitySceneTree");
    print_line(detected
            ? "GodotPhase: GodotRealityKit detected, using PHASE client rendering mode."
            : "GodotPhase: GodotRealityKit not detected, using PHASE local rendering mode.");
    return detected;
}

bool PHASEManager::is_client_rendering_active() const {
    return client_rendering_active;
}
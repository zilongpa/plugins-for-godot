//
//  PHASEManager.h
//
//  Copyright © 2026 Apple Inc.
//

#ifndef PHASEManager_H
#define PHASEManager_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/engine.hpp>

namespace godot {

// Public enum using sequential integers - PHASEWrapper handles conversion to PHASE's internal values
enum GodotPHASEReverbPreset {
    REVERB_PRESET_NONE = 0,
    REVERB_PRESET_SMALL_ROOM = 1,
    REVERB_PRESET_MEDIUM_ROOM = 2,
    REVERB_PRESET_LARGE_ROOM = 3,
    REVERB_PRESET_LARGE_ROOM_2 = 4,
    REVERB_PRESET_MEDIUM_CHAMBER = 5,
    REVERB_PRESET_LARGE_CHAMBER = 6,
    REVERB_PRESET_MEDIUM_HALL = 7,
    REVERB_PRESET_MEDIUM_HALL_2 = 8,
    REVERB_PRESET_MEDIUM_HALL_3 = 9,
    REVERB_PRESET_LARGE_HALL = 10,
    REVERB_PRESET_CATHEDRAL = 11
};

enum GodotPHASEClientRenderingMode {
    CLIENT_RENDERING_MODE_AUTOMATIC = 0,
    CLIENT_RENDERING_MODE_ENABLED = 1,
    CLIENT_RENDERING_MODE_DISABLED = 2
};

class PHASEManager : public Node {
    GDCLASS(PHASEManager, Node)

private:
    bool engine_initialized;
    int current_reverb_preset;  // Store as int for Godot compatibility
    bool client_rendering_active;

public:
    PHASEManager();
    ~PHASEManager();

    bool initialize_engine();
    void shutdown_engine();
    bool is_engine_initialized() const;

    void set_scene_reverb_preset(GodotPHASEReverbPreset preset);
    GodotPHASEReverbPreset get_scene_reverb_preset() const;

    bool is_client_rendering_active() const;

#if TARGET_OS_VISION
    bool set_world_transform(const Transform3D &transform);
#endif

protected:
    static void _bind_methods();
    void _notification(int p_what);

    Array _extract_global_meta_parameters_from_bundles() const;

private:
    template<typename T>
    bool set_global_meta_parameter(const String &param_name, T value, bool (*setter)(const char*, T));

    void phase_ready();
    void phase_physics_process();

    bool resolve_client_rendering_mode() const;
};

}

VARIANT_ENUM_CAST(godot::GodotPHASEReverbPreset);
VARIANT_ENUM_CAST(godot::GodotPHASEClientRenderingMode);

#endif

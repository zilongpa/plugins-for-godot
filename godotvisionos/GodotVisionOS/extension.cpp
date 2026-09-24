#include "uikit_hover_effect_2d.h"
#include "visionos_hover_root_2d.h"
#include "visionos_hover_style_2d.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;
using namespace godotvisionos;

static void initialize_visionos(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		GDREGISTER_CLASS(VisionOSHoverStyle2D);
		GDREGISTER_CLASS(UIKitHoverEffect2D);
		GDREGISTER_CLASS(VisionOSHoverRoot2D);
	}
}

static void uninitialize_visionos(ModuleInitializationLevel p_level) {
}

extern "C" GDExtensionBool GDE_EXPORT godotvisionos_extension_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_visionos);
	init_obj.register_terminator(uninitialize_visionos);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}

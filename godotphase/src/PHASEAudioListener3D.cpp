//
//  PHASEAudioListener3D.cpp
//
//  Copyright © 2026 Apple Inc.
//

#include "PHASEAudioListener3D.h"
#include "PHASEManager.h"
#import "PHASEWrapper.h"
#include "PHASEUtils.h"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void PHASEAudioListener3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_head_tracking", "enabled"), &PHASEAudioListener3D::set_head_tracking);
	ClassDB::bind_method(D_METHOD("get_head_tracking"), &PHASEAudioListener3D::get_head_tracking);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "head_tracking"), "set_head_tracking", "get_head_tracking");
}

PHASEAudioListener3D::~PHASEAudioListener3D() {
    PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
    [engine destroyListener];
}

void PHASEAudioListener3D::_notification(int p_what) {
    switch (p_what) {
        case NOTIFICATION_READY: phase_ready(); break;
        case NOTIFICATION_PHYSICS_PROCESS: phase_physics_process(); break;
    }
}

void PHASEAudioListener3D::phase_ready() {
    set_physics_process(true);

    PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
    if (!engine || ![engine isInitialized]) {
        return;
    }
    if (![engine createListener]) {
        ERR_PRINT("PHASEAudioListener3D: Failed to create PHASE listener.");
    }
    [engine setListenerHeadTracking:head_tracking];

    Transform3D transform = get_global_transform();
    simd_float4x4 matrix = PHASEUtils::transform_to_simd_float4x4(transform);
    [engine setListenerTransform:matrix];
}

void PHASEAudioListener3D::phase_physics_process() {
    Transform3D transform = get_global_transform();
    simd_float4x4 matrix = PHASEUtils::transform_to_simd_float4x4(transform);
    PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
    [engine setListenerTransform:matrix];
}

void PHASEAudioListener3D::set_head_tracking(bool enabled) {
	head_tracking = enabled;
	PHASEEngineWrapper* engine = [PHASEEngineWrapper sharedInstance];
	[engine setListenerHeadTracking:enabled];
}

bool PHASEAudioListener3D::get_head_tracking() const {
	return head_tracking;
}

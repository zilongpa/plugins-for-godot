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

#ifndef GDRK_H
#define GDRK_H

#import <Metal/Metal.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

#import <simd/simd.h>

#ifdef __cplusplus

#include <array>
#include <functional>

namespace gdrk {

class SceneLoader;
class ProgramCache;

} //namespace gdrk

struct GDRKVertexBufferFormat {
	uint32_t vertex_stride;
	uint32_t normal_tangent_stride;
	uint32_t attribute_stride;
	uint32_t vertex_offset;
	uint32_t normal_offset;
	uint32_t tangent_offset;
	uint32_t color_offset;
	uint32_t uv1_offset;
	uint32_t uv2_offset;
	uint32_t skin_stride;
	uint32_t skin_weight_offset;

	friend bool operator==(const GDRKVertexBufferFormat &lhs, const GDRKVertexBufferFormat &rhs) = default;
};

struct GDRKPose {
	simd_float3 position;
	simd_quatf orientation;
};

struct GDRKTransform {
	simd_float3 scale;
	simd_float3 position;
	simd_quatf orientation;

	static GDRKTransform identity;
};

// The physical size of a volume, in meters. Zero components of the minimum
// and maximum leave them unbounded.
struct GDRKVolumeSize {
	simd_float3 size;
	simd_float3 minimum;
	simd_float3 maximum;
	bool resizable;
};

// A portal window's clipping and crossing planes, in the window's space
// (meters from its center, +Z toward the person).
struct GDRKPortalPlanes {
	bool clipping;
	simd_float3 clipping_position;
	simd_float3 clipping_normal;
	bool crossing;
	simd_float3 crossing_position;
	simd_float3 crossing_normal;
};

struct GDRKRay {
	simd_float3 origin;
	simd_float3 direction;
};

#if TARGET_OS_OSX
struct GDRKIntersectionInfo {
	simd_float3 position;
	uint64_t entity_id;
};
#endif

typedef NS_ENUM(NSUInteger, PresentationStyle) {
	kVolumetricWindow,
	kVolumetricPortal,
	kImmersive,
	// The main viewport stays a 2D window; Window nodes holding a
	// RealityVolumeCamera3D or RealityPortalCamera3D open as volumes or portals.
	kWindow2D
};

typedef NS_ENUM(NSUInteger, ImmersionStyle) {
	kMixed,
	kFull,
	kProgressive
};

typedef NS_ENUM(NSUInteger, WorldEnvironmentConversion) {
	kAutomatic,
	kEnable,
	kDisable
};

typedef NS_ENUM(NSUInteger, ControllerHand) {
	kLeftHand,
	kRightHand
};

#if TARGET_OS_OSX
using GDRKColor = NSColor;
#else
using GDRKColor = UIColor;
#endif

using GDRKColorRef = GDRKColor *;

class GDRKBridgeDelegate {
public:
	explicit GDRKBridgeDelegate(gdrk::SceneLoader *p_loader) {
		loader = p_loader;
	}

	// A delegate for the volume or portal presenting a Window. SwiftUI can still
	// update the window's views after it closes; its loader is looked up each time.
	GDRKBridgeDelegate(gdrk::SceneLoader *p_loader, uint64_t p_window_id) {
		loader = p_loader;
		window_id = p_window_id;
	}

	void printError(const char *p_msg);
	void printWarning(const char *p_msg);

	struct ExtensionSettings {
		bool handlesGameControllerEvents;
		PresentationStyle presentationStyle;
		ImmersionStyle immersionStyle;
		WorldEnvironmentConversion world_environment;
		float portalWorldScale; // 0 means unset; use the interactive slider instead.

		bool should_convert_world_environment() const;
	};

	ExtensionSettings getExtensionSettings() const;

	void setPHASETransform(GDRKTransform) const;

#if TARGET_OS_OSX
	NSWindow *getDisplayServerWindow() const;
#else
	UIViewController *getDisplayServerViewController() const;
	UIImage *getBootSplashImage() const;
	UIColor *getBootSplashBgColor() const;
#endif

	void *getCameraEntity() const;

	void onWorldScaleChanged(float p_scale) const;

	// The fixed world scale of this scene's portal, or 0 for the interactive slider.
	float getPortalWorldScale() const;
	// The clipping and crossing planes of this scene's portal; both off by default.
	GDRKPortalPlanes getPortalPlanes() const;

	// The measured size of this scene's volume window, in meters.
	void onVolumeMeasured(simd_float3 p_size_meters) const;

#if TARGET_OS_OSX
	void onWindowResized(simd_float2 p_new_size) const;
#else
	void onWindowResized(simd_float3 p_new_size) const;
#endif

	GDRKTransform getXROrigin() const;

	// True while the shared-volume controller XR interface is running, i.e. the presentation
	// style is a shared volume and controller tracking is enabled. Only then is it worth
	// anchoring the controllers, since nothing else consumes their poses.
	bool wantsControllerAnchors() const;

	// Push a spatial controller's AnchorEntity(.accessory) transform, in scene-root-local
	// space, to the shared-volume controller XR interface. Ignored when that interface isn't
	// running.
	void setControllerAnchor(ControllerHand p_hand, GDRKTransform p_transform, bool p_tracked) const;

	// Sample a spatial controller's buttons / thumbstick and publish them on the shared-volume
	// controller XR interface. p_gc_controller is the GCController as an opaque pointer. Ignored
	// when that interface isn't running.
	void setControllerInput(ControllerHand p_hand, void *p_gc_controller) const;

	void onEntityPressUpdate(int64_t p_event_id,
			bool p_ended,
			uint64_t p_entity_id,
			simd_float3 p_position,
			simd_float3 p_hit_position,
			simd_float3 p_hit_normal,
			int64_t p_hit_shape_idx,
			bool p_has_input_device_pose,
			GDRKPose p_input_device_pose,
			bool p_has_selection_ray,
			GDRKRay p_selection_ray,
			bool p_has_chirality,
			uint32_t p_chirality) const;

private:
	mutable gdrk::SceneLoader *loader = nullptr;
	uint64_t window_id = 0;

	// The live loader, or null once the window it presented has closed.
	gdrk::SceneLoader *resolve_loader() const;

	void initialize_phase_manager() const;
};

template <typename Fn>
class GDRKTaskCompletionDelegate;

template <typename R, typename... Ps>
class GDRKTaskCompletionDelegate<R(Ps...)> {
public:
	explicit GDRKTaskCompletionDelegate(std::function<R(Ps...)> p_callback) :
			callback(std::move(p_callback)) {}

	R onCompleted(Ps &&...p_params) const {
		return callback(std::forward<Ps...>(p_params)...);
	}

private:
	std::function<R(Ps...)> callback;
};

using GDRKMaterialLoadDelegate = GDRKTaskCompletionDelegate<void(void *)>;
using GDRKEntityWriteDelegate = GDRKTaskCompletionDelegate<void()>;

#endif // __cplusplus

#endif // GDRK_H

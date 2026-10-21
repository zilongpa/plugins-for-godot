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

#include "../Util/culling.h"
#include "node_loader.h"
#include "volume_camera_3d.h"

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <optional>

namespace gdrk {

class CameraLoader : public NodeLoaderBase<CameraLoader, godot::Node3D> {
	NODE_LOADER(CameraLoader, NodeLoaderBase, godot::Node3D);

public:
	struct CullingInfo {
		enum CameraType {
			UNKNOWN = 0,
			PERSPECTIVE = 1,
			ORTHOGRAPHIC = 2,
			VOLUMETRIC = 3,
		};

		CameraType camera_type = CameraType::UNKNOWN;
		bool valid = false;

		// Perspective / volumetric
		float radius = 0;
		godot::Vector3 position;

		// Volumetric
		godot::AABB volume_aabb;

		// Orthographic
		godot::Vector3 ortho_right;
		godot::Vector3 ortho_up;
		godot::Vector3 ortho_forward;
		godot::Vector3 ortho_frustum_center;
		godot::Vector3 ortho_half_extents;
	};

	godot::Node3D *cast(godot::Node *p_node) const {
		if (godot::Camera3D *camera = godot::Object::cast_to<godot::Camera3D>(p_node)) {
			return camera;
		} else if (RealityVolumeCamera3D *volume_camera = godot::Object::cast_to<RealityVolumeCamera3D>(p_node)) {
			return volume_camera;
		} else {
			return nullptr;
		}
	}

	void update(const ResourceLoaderSet &p_resource_loaders);

	// The viewport whose current camera this loader follows.
	void set_viewport(godot::Viewport *p_viewport) { viewport_id = p_viewport ? p_viewport->get_instance_id() : 0; }

	GodotRealityKit::Entity get_current_entity() const { return camera_entity; }
	godot::Node3D *get_current_node() const;
	const CullingInfo &get_culling_info() const { return culling_info; }
	std::optional<CullingSystem::Collector> get_octree_collector() const;

private:
	friend class RealityVolumeCamera3D;

	uint64_t viewport_id = 0;
	GodotRealityKit::Entity camera_entity = GodotRealityKit::Entity::initAndMaterialize();
	godot::Transform3D camera_transform;
	uint32_t camera_properties_hash = 0;
	bool has_active_camera = false;
	CullingInfo culling_info;
};

} //namespace gdrk

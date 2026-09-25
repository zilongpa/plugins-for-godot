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

#include "camera_loader.h"
#include "node_loaders.h"
#include "scene_tree.h"
#include "signposts.h"
#include "volume_camera_3d.h"

#include "../../types.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/window.hpp>

using namespace gdrk;

auto get_camera_3d_prop_hasher() {
	return make_object_property_hasher(make_object_property(&godot::Camera3D::get_projection),
			make_object_property(&godot::Camera3D::get_near),
			make_object_property(&godot::Camera3D::get_far),
			make_object_property(&godot::Camera3D::get_fov),
			make_object_property(&godot::Camera3D::get_size));
}

auto get_volume_camera_3d_prop_hasher() {
	return make_object_property_hasher(make_object_property(&RealityVolumeCamera3D::get_size),
			make_object_property(&RealityVolumeCamera3D::get_keep_aspect));
}

godot::Node3D *CameraLoader::get_current_node() const {
	godot::Engine *engine = godot::Engine::get_singleton();
	RealitySceneTree *reality_scene_tree = godot::Object::cast_to<RealitySceneTree>(engine->get_main_loop());
	ERR_FAIL_NULL_V(reality_scene_tree, nullptr);

	godot::Viewport *viewport = Base::owner->window_scene_root
			? Base::owner->window_scene_root->get_viewport() : reality_scene_tree->get_root()->get_viewport();
	if (godot::Camera3D *camera_3d = viewport->get_camera_3d()) {
#if TARGET_OS_XR
		if (RealityVolumeCamera3D *volume_camera = godot::Object::cast_to<RealityVolumeCamera3D>(camera_3d->get_parent())) {
			return volume_camera;
		}
#endif // TARGET_OS_XR
		return camera_3d;
	}

	return nullptr;
}

std::optional<CullingSystem::Collector> CameraLoader::get_octree_collector() const {
	// Null collector — deactivates everything when the camera is invalid or unhandled.
	if (!culling_info.valid) {
		return std::nullopt;
	}

	switch (culling_info.camera_type) {
		case CullingInfo::CameraType::PERSPECTIVE: {
			const godot::Vector3 pos = culling_info.position;
			const float radius = culling_info.radius;
			return CullingSystem::Collector{
				.is_object_inbound = [pos, radius](const auto &e) {
					// AABB vs sphere: closest point on AABB to sphere center.
					const godot::Vector3 closest = pos.clamp(e.aabb.position, e.aabb.position + e.aabb.size);
					return closest.distance_to(pos) <= radius; },
				.is_node_inbound = [pos, radius](const auto &n) {
					// AABB–sphere intersection: closest point on node AABB to sphere center.
					const godot::Vector3 closest = pos.clamp(n.bounds_min, n.get_bounds_max());
					return closest.distance_to(pos) <= radius; },
			};
		}
		case CullingInfo::CameraType::VOLUMETRIC: {
			const godot::AABB vol = culling_info.volume_aabb;
			return CullingSystem::Collector{
				.is_object_inbound = [vol](const auto &e) { return vol.intersects(e.aabb); },
				.is_node_inbound = [vol](const auto &n) { return vol.intersects(godot::AABB(n.bounds_min, godot::Vector3(n.size, n.size, n.size))); },
			};
		}
		case CullingInfo::CameraType::ORTHOGRAPHIC: {
			const godot::Vector3 center = culling_info.ortho_frustum_center;
			const godot::Vector3 right = culling_info.ortho_right;
			const godot::Vector3 up = culling_info.ortho_up;
			const godot::Vector3 forward = culling_info.ortho_forward;
			const godot::Vector3 extents = culling_info.ortho_half_extents;

			// AABB vs OBB using a 6-axis SAT (3 OBB axes + 3 world axes).
			// Conservative: may produce false positives but never false negatives.
			auto aabb_vs_obb = [center, right, up, forward, extents](const godot::AABB &aabb) -> bool {
				const godot::Vector3 aabb_center = aabb.position + aabb.size * 0.5f;
				const godot::Vector3 half = aabb.size * 0.5f;
				const godot::Vector3 offset = aabb_center - center;

				// OBB axes.
				const float half_right = godot::Math::abs(right.x) * half.x + godot::Math::abs(right.y) * half.y + godot::Math::abs(right.z) * half.z;
				if (godot::Math::abs(offset.dot(right)) > extents.x + half_right) {
					return false;
				}
				const float half_up = godot::Math::abs(up.x) * half.x + godot::Math::abs(up.y) * half.y + godot::Math::abs(up.z) * half.z;
				if (godot::Math::abs(offset.dot(up)) > extents.y + half_up) {
					return false;
				}
				const float half_fwd = godot::Math::abs(forward.x) * half.x + godot::Math::abs(forward.y) * half.y + godot::Math::abs(forward.z) * half.z;
				if (godot::Math::abs(offset.dot(forward)) > extents.z + half_fwd) {
					return false;
				}

				// World axes.
				const float obb_half_x = godot::Math::abs(right.x) * extents.x + godot::Math::abs(up.x) * extents.y + godot::Math::abs(forward.x) * extents.z;
				if (godot::Math::abs(offset.x) > obb_half_x + half.x) {
					return false;
				}
				const float obb_half_y = godot::Math::abs(right.y) * extents.x + godot::Math::abs(up.y) * extents.y + godot::Math::abs(forward.y) * extents.z;
				if (godot::Math::abs(offset.y) > obb_half_y + half.y) {
					return false;
				}
				const float obb_half_z = godot::Math::abs(right.z) * extents.x + godot::Math::abs(up.z) * extents.y + godot::Math::abs(forward.z) * extents.z;
				if (godot::Math::abs(offset.z) > obb_half_z + half.z) {
					return false;
				}

				return true;
			};

			return CullingSystem::Collector{
				.is_object_inbound = [aabb_vs_obb](const auto &e) { return aabb_vs_obb(e.aabb); },
				.is_node_inbound = [aabb_vs_obb](const auto &n) { return aabb_vs_obb(godot::AABB(n.bounds_min, godot::Vector3(n.size, n.size, n.size))); },
			};
		}
		default: {
			return std::nullopt;
		}
	}
}

void CameraLoader::update(const ResourceLoaderSet &p_resource_loaders) {
	PROFILE_FUNC_SCOPE;

	Base::update(p_resource_loaders);

	godot::Engine *engine = godot::Engine::get_singleton();
	RealitySceneTree *scene_tree = godot::Object::cast_to<RealitySceneTree>(engine->get_main_loop());
	ERR_FAIL_NULL(scene_tree);

	godot::Node3D *current_camera = get_current_node();

	if (current_camera == nullptr && has_active_camera) {
		GodotRealityKit::Entity root_entity = Base::owner->get_root_entity();
		camera_entity.setParent(swift::Optional<GodotRealityKit::Entity>::none());
		has_active_camera = false;
	} else if (current_camera != 0 && !has_active_camera) {
		GodotRealityKit::Entity root_entity = Base::owner->get_root_entity();
		camera_entity.setParent(swift::Optional<GodotRealityKit::Entity>::some(root_entity));
		has_active_camera = true;
	}

	if (current_camera == nullptr) {
		culling_info.camera_type = CullingInfo::CameraType::UNKNOWN;
		culling_info.valid = false;
		// Reset so the camera type is re-detected when a camera reappears with the same properties.
		camera_properties_hash = 0;
		return;
	}

	const uint64_t camera_id = current_camera->get_instance_id();
	godot::Node3D *node = godot::Object::cast_to<godot::Node3D>(godot::ObjectDB::get_instance(camera_id));
	const auto found_idx = node_id_to_idx.find(camera_id);
	ERR_FAIL_COND(node == nullptr || !found_idx);

	const godot::Transform3D transform = node->get_global_transform();
	// If culling_info was invalidated (e.g. camera was absent last frame), force a recompute
	// even if transform and properties are unchanged from the previous valid frame.
	bool culling_info_needs_update = !culling_info.valid;
	if (camera_transform != transform) {
		camera_entity.setTransform(to_vector3(transform.basis.get_scale()),
				to_vector4(transform.basis.get_rotation_quaternion()),
				to_vector3(transform.origin));
		camera_transform = transform;
		culling_info_needs_update = true;
	}

	uint32_t properties_hash = 0;
	if (godot::Camera3D *camera_3d = godot::Object::cast_to<godot::Camera3D>(node)) {
		static auto prop_hasher = get_camera_3d_prop_hasher();
		properties_hash = prop_hasher.hash(camera_3d);
	} else if (RealityVolumeCamera3D *volume_camera_3d = godot::Object::cast_to<RealityVolumeCamera3D>(node)) {
		static auto prop_hasher = get_volume_camera_3d_prop_hasher();
		properties_hash = prop_hasher.hash(volume_camera_3d);
	}

	if (camera_properties_hash != properties_hash) {
		culling_info_needs_update = true;
		camera_entity.setName("CurrentCamera");
		culling_info.camera_type = CullingInfo::CameraType::UNKNOWN;
		if (godot::Camera3D *camera_3d = godot::Object::cast_to<godot::Camera3D>(node)) {
			float far = camera_3d->get_far();
			float near = camera_3d->get_near();
			if (camera_3d->get_projection() == godot::Camera3D::PROJECTION_PERSPECTIVE) {
				float fov = camera_3d->get_fov();
				camera_entity.setVolumeCameraSize(swift::Optional<GodotRealityKit::Vector3>::none());
				camera_entity.disableOrthographicCamera();
				camera_entity.setupPerspectiveCamera(near, far, fov);
				culling_info.camera_type = CullingInfo::CameraType::PERSPECTIVE;

			} else {
				// TODO: orthographic camera has no input or hover effects
				camera_entity.setVolumeCameraSize(swift::Optional<GodotRealityKit::Vector3>::none());
				float size = camera_3d->get_size();
				camera_entity.setupOrthographicCamera(near, far, size * 0.5f);
				camera_entity.disablePerspectiveCamera();
				culling_info.camera_type = CullingInfo::CameraType::ORTHOGRAPHIC;
			}
		} else if (RealityVolumeCamera3D *volume_camera_3d = godot::Object::cast_to<RealityVolumeCamera3D>(node)) {
			const GodotRealityKit::Vector3 size = gdrk::to_vector3(volume_camera_3d->get_physical_size());
			camera_entity.setVolumeCameraSize(swift::Optional<GodotRealityKit::Vector3>::some(size));
			camera_entity.disableOrthographicCamera();
			camera_entity.disablePerspectiveCamera();
			culling_info.camera_type = CullingInfo::CameraType::VOLUMETRIC;
		}
		camera_properties_hash = properties_hash;
	}

	if (culling_info_needs_update) {
		godot::Transform3D camera_transform = node->get_global_transform();
		godot::Vector3 camera_position = camera_transform.get_origin();
		godot::Vector3 scale3d = camera_transform.get_basis().get_scale();
		float scale = scale3d[scale3d.max_axis_index()];

		float aspect = 1.0f;
		if (godot::Viewport *vp = node->get_viewport()) {
			const godot::Rect2 rect = vp->get_visible_rect();
			aspect = rect.size.x / rect.size.y;
		}

		// This is useful to change to something like 0.5 to observe the effect of the culling radius when working
		// with a perspective camera.
		const float culling_radius_scale = 1.0;
		switch (culling_info.camera_type) {
			case CullingInfo::CameraType::UNKNOWN: {
				culling_info.valid = false;
				break;
			}
			case CullingInfo::CameraType::PERSPECTIVE: {
				culling_info.valid = true;
				godot::Camera3D *camera_3d = static_cast<godot::Camera3D *>(node);
				float far = camera_3d->get_far();
				float near = camera_3d->get_near();
				float depth = far - near;
				float fov = camera_3d->get_fov();
				float tan_half_vertical_fov, tan_half_horizontal_fov;
				if (camera_3d->get_keep_aspect_mode() == godot::Camera3D::KEEP_HEIGHT) {
					tan_half_vertical_fov = tan(fov * 0.5f * (float)M_PI / 180.0f);
					tan_half_horizontal_fov = tan_half_vertical_fov * aspect;
				} else {
					tan_half_horizontal_fov = tan(fov * 0.5f * (float)M_PI / 180.0f);
					tan_half_vertical_fov = tan_half_horizontal_fov / aspect;
				}

				const float half_depth = depth * 0.5f;
				const float far_half_width = far * tan_half_horizontal_fov;
				const float far_half_height = far * tan_half_vertical_fov;
				float local_radius = sqrt(far_half_width * far_half_width + far_half_height * far_half_height + half_depth * half_depth);

				godot::Vector3 view_direction = camera_transform.basis.xform(godot::Vector3(0.0f, 0.0f, -1.0f)).normalized();
				culling_info.radius = local_radius * scale * culling_radius_scale;
				culling_info.position = camera_position + view_direction * (half_depth + near);
				break;
			}
			case CullingInfo::CameraType::ORTHOGRAPHIC: {
				culling_info.valid = true;
				godot::Camera3D *camera_3d = static_cast<godot::Camera3D *>(node);
				const float size = camera_3d->get_size();
				const float near_dist = camera_3d->get_near();
				const float far_dist = camera_3d->get_far();
				const godot::Basis basis = camera_transform.get_basis();
				culling_info.ortho_right = basis.get_column(0).normalized();
				culling_info.ortho_up = basis.get_column(1).normalized();
				culling_info.ortho_forward = -basis.get_column(2).normalized();
				const float half_height = size * 0.5f * scale;
				const float half_width = half_height * aspect;
				const float half_depth = (far_dist - near_dist) * 0.5f;
				culling_info.ortho_frustum_center = camera_position + culling_info.ortho_forward * (near_dist + half_depth);
				culling_info.ortho_half_extents = godot::Vector3(half_width, half_height, half_depth);
				break;
			}
			case CullingInfo::CameraType::VOLUMETRIC: {
				culling_info.valid = true;
				RealityVolumeCamera3D *volume_camera_3d = static_cast<RealityVolumeCamera3D *>(node);
				godot::Vector3 volume_size = volume_camera_3d->get_physical_size() * culling_radius_scale;
				const godot::Vector3 half_size = volume_size * 0.5f;
				culling_info.volume_aabb = camera_transform.xform(
						godot::AABB(godot::Vector3(-half_size.x, -half_size.y, -half_size.z), volume_size));
				break;
			}
		}
	}

#if ENABLE_CULLING_DEBUG_VISUALIZATION
	if (culling_info.valid) {
		switch (culling_info.camera_type) {
			case CullingInfo::CameraType::PERSPECTIVE:
				camera_entity.setDebugCullingSphere(Base::owner->get_root_entity(),
						to_vector3(culling_info.position), culling_info.radius, 0.3f);
				break;
			case CullingInfo::CameraType::VOLUMETRIC:
				camera_entity.setDebugBoundingBox(Base::owner->get_root_entity(),
						to_vector3(culling_info.volume_aabb.position),
						to_vector3(culling_info.volume_aabb.position + culling_info.volume_aabb.size), 0.3f);
				break;
			case CullingInfo::CameraType::ORTHOGRAPHIC: {
				const float half_diag = culling_info.ortho_half_extents.length();
				camera_entity.setDebugCullingSphere(Base::owner->get_root_entity(),
						to_vector3(culling_info.ortho_frustum_center), half_diag, 0.3f);
				break;
			}
			default:
				break;
		}
	}
#endif

#if ENABLE_CULLING_FRAME_STATS
	if (culling_info.valid) {
		switch (culling_info.camera_type) {
			case CullingInfo::CameraType::PERSPECTIVE:
				std::cout << "CullingInfo (PERSPECTIVE): pos=" << to_std_string(culling_info.position)
						  << " r=" << culling_info.radius << std::endl;
				break;
			case CullingInfo::CameraType::VOLUMETRIC:
				std::cout << "CullingInfo (VOLUMETRIC): min=" << to_std_string(culling_info.volume_aabb.position)
						  << " max=" << to_std_string(culling_info.volume_aabb.position + culling_info.volume_aabb.size) << std::endl;
				break;
			case CullingInfo::CameraType::ORTHOGRAPHIC:
				std::cout << "CullingInfo (ORTHOGRAPHIC): center=" << to_std_string(culling_info.ortho_frustum_center)
						  << " extents=" << to_std_string(culling_info.ortho_half_extents) << std::endl;
				break;
			default:
				break;
		}
	}
#endif
}

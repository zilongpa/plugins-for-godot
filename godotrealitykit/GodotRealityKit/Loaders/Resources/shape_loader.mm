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

#include "shape_loader.h"
#include "bridge.h"
#include "signposts.h"

#include <godot_cpp/classes/box_shape3d.hpp>
#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/convex_polygon_shape3d.hpp>
#include <godot_cpp/classes/sphere_shape3d.hpp>

using namespace gdrk;

uint32_t ShapeLoader::find_or_add(godot::RID p_shape_rid, godot::Ref<godot::Shape3D> p_shape) {
	if (shape_rid_to_idx.has(p_shape_rid)) {
		return shape_rid_to_idx.get(p_shape_rid);
	}

	const uint32_t idx = alloc_idx();

	connect_changed(p_shape.ptr(), idx);

	shapes[idx] = Shape{
		.shape_rid = p_shape_rid,
		.shape = p_shape,
	};

	shape_rid_to_idx.insert(p_shape_rid, idx);
	return idx;
}

bool ShapeLoader::update() {
	PROFILE_FUNC_SCOPE;

	return for_each_dirty_throttled([&](uint32_t idx) {
		if (!is_used_in_frame(idx)) {
			return LocalBitVector::IterationResult::SKIPPED;
		}
		const godot::Shape3D *shape = shapes[idx].shape.ptr();
		ERR_FAIL_NULL_V(shape, LocalBitVector::IterationResult::SKIPPED);

		if (const godot::BoxShape3D *box_shape = godot::Object::cast_to<godot::BoxShape3D>(shape)) {
			// TODO: confirm shape xyz ordering
			const godot::Vector3 box_size = box_shape->get_size();
			GodotRealityKit::ShapeResource resource = GodotRealityKit::ShapeResource::generateBox(box_size.x, box_size.y, box_size.z);
			emplace_replace(&shapes[idx].resource, resource);
		} else if (const godot::CapsuleShape3D *capsule_shape = godot::Object::cast_to<godot::CapsuleShape3D>(shape)) {
			GodotRealityKit::ShapeResource resource =
					GodotRealityKit::ShapeResource::generateCapsule(capsule_shape->get_height(),
							capsule_shape->get_radius());
			emplace_replace(&shapes[idx].resource, resource);
		} else if (const godot::ConvexPolygonShape3D *convex_shape = godot::Object::cast_to<godot::ConvexPolygonShape3D>(shape)) {
			godot::PackedVector3Array points = convex_shape->get_points();
			GodotRealityKit::Vector3 zero = GodotRealityKit::Vector3::init(0, 0, 0);
			swift::Array<GodotRealityKit::Vector3> ps_points = swift::Array<GodotRealityKit::Vector3>::init(zero, points.size());
			for (godot::Vector3 point : points) {
				ps_points.append(to_vector3(point));
			}

			GodotRealityKit::ShapeResource resource = GodotRealityKit::ShapeResource::generateConvex(ps_points);
			emplace_replace(&shapes[idx].resource, resource);
			// TODO: implement concave shape resources
			//        } else if (const godot::ConcavePolygonShape3D *concave_shape = godot::Object::cast_to<godot::ConcavePolygonShape3D>(shape)) {
			//            swift::Array<GodotRealityKit::Vector3> vertices = swift::Array<GodotRealityKit::Vector3>::init();
			//            vertices.reserveCapacity(concave_shape->get_faces().size());
			//            for (godot::Vector3 &vertex : concave_shape->get_faces()) {
			//                vertices.append(GodotRealityKit::Vector3::init(vertex.x, vertex.y, vertex.z));
			//            }
			//            swift::Optional<GodotRealityKit::LowLevelMesh> low_level_mesh = GodotRealityKit::LowLevelMesh::init(vertices);
			//            ERR_FAIL_COND(low_level_mesh.isNone());
			//            swift::Optional<GodotRealityKit::MeshResource> mesh_resource = GodotRealityKit::MeshResource::init(low_level_mesh.get());
			//            ERR_FAIL_COND(mesh_resource.isNone());
			//            swift::Optional<GodotRealityKit::ShapeResource> resource = GodotRealityKit::ShapeResource::generateMesh(mesh_resource.get());
			//            ERR_FAIL_COND(resource.isNone());
			//            emplace_replace(&shapes[idx].resource, resource.get());
		} else if (const godot::SphereShape3D *sphere_shape = godot::Object::cast_to<godot::SphereShape3D>(shape)) {
			GodotRealityKit::ShapeResource resource = GodotRealityKit::ShapeResource::generateSphere(sphere_shape->get_radius());
			emplace_replace(&shapes[idx].resource, resource);
		} else {
			WARN_COMPAT_MSG("Can only load BoxShape3D, CapsuleShape3D, ConvexPolygonShape3D, ConcavePolygon3D, and SphereShape3D shapes for gesture interactions and hover effects")
		}
		return LocalBitVector::IterationResult::PROCESSED;
	});
}

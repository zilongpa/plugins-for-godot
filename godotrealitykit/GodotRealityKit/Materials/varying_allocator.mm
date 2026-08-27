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

#include "varying_allocator.h"
#include "snippets.h"
#include "types.h"
#include "visual_program_builder.h"

using namespace gdrk;

uint8_t VaryingAllocator::slot_requirement[PortType::PT_COUNT] = {
	0,
	1, // BOOL
	1, // INT
	1, // UINT
	1, // FLOAT,
	2, // VEC2F,
	3, // VEC3F,
	4, // VEC4F,
	0, // TRANSFORM3D, unsupported
	0,
	0,
	0,
};

VaryingAllocator::Slot VaryingAllocator::slot_descriptors[VaryingAllocator::MAX_SLOTS] = {
	{ .uv_index = 0, .stride = 2, .has_setter = false, .expression = "v2_x(fragment_uv0)", .declaration = "let fragment_uv0 = ND_geompropvalue_vector2(\"UV0\", (0.0f, 0.0f));" },
	{ .uv_index = 0, .stride = 2, .has_setter = false, .expression = "v2_y(fragment_uv0)" },

	{ .uv_index = 1, .stride = 2, .has_setter = false, .expression = "v2_x(fragment_uv1)", .declaration = "let fragment_uv1 = ND_geompropvalue_vector2(\"UV1\", (0.0f, 0.0f));" },
	{
			.uv_index = 1,
			.stride = 2,
			.has_setter = false,
			.expression = "v2_y(fragment_uv1)",
	},

	{ .uv_index = 2, .stride = 4, .has_setter = false, .expression = "v4_x(fragment_uv2)", .declaration = "let fragment_uv2 = ND_geompropvalue_vector4(\"UV2\", (0.0f, 0.0f, 0.0f, 0.0f));" },
	{ .uv_index = 2, .stride = 4, .has_setter = false, .expression = "v4_y(fragment_uv2)" },
	{ .uv_index = 2, .stride = 4, .has_setter = false, .expression = "v4_z(fragment_uv2)" },
	{ .uv_index = 2, .stride = 4, .has_setter = false, .expression = "v4_w(fragment_uv2)" },

	{ .uv_index = 3, .stride = 4, .has_setter = false, .expression = "v4_x(fragment_uv3)", .declaration = "let fragment_uv3 = ND_geompropvalue_vector4(\"UV3\", (0.0f, 0.0f, 0.0f, 0.0f));" },
	{ .uv_index = 3, .stride = 4, .has_setter = false, .expression = "v4_y(fragment_uv3)" },
	{ .uv_index = 3, .stride = 4, .has_setter = false, .expression = "v4_z(fragment_uv3)" },
	{ .uv_index = 3, .stride = 4, .has_setter = false, .expression = "v4_w(fragment_uv3)" },

	{ .uv_index = 4, .stride = 4, .has_setter = false, .expression = "v4_x(fragment_uv4)", .declaration = "let fragment_uv4 = ND_geompropvalue_vector4(\"UV4\", (0.0f, 0.0f, 0.0f, 0.0f));" },
	{ .uv_index = 4, .stride = 4, .has_setter = false, .expression = "v4_y(fragment_uv4)" },
	{ .uv_index = 4, .stride = 4, .has_setter = false, .expression = "v4_z(fragment_uv4)" },
	{ .uv_index = 4, .stride = 4, .has_setter = false, .expression = "v4_w(fragment_uv4)" },

	{ .uv_index = 5, .stride = 4, .has_setter = false, .expression = "v4_x(fragment_uv5)", .declaration = "let fragment_uv5 = ND_geompropvalue_vector4(\"UV5\", (0.0f, 0.0f, 0.0f, 0.0f));" },
	{ .uv_index = 5, .stride = 4, .has_setter = false, .expression = "v4_y(fragment_uv5)" },
	{ .uv_index = 5, .stride = 4, .has_setter = false, .expression = "v4_z(fragment_uv5)" },
	{ .uv_index = 5, .stride = 4, .has_setter = false, .expression = "v4_w(fragment_uv5)" },

	{ .uv_index = 6, .stride = 4, .has_setter = false, .expression = "v4_x(fragment_uv6)", .declaration = "let fragment_uv6 = ND_geompropvalue_vector4(\"UV6\", (0.0f, 0.0f, 0.0f, 0.0f));" },
	{ .uv_index = 6, .stride = 4, .has_setter = false, .expression = "v4_y(fragment_uv6)" },
	{ .uv_index = 6, .stride = 4, .has_setter = false, .expression = "v4_z(fragment_uv6)" },
	{ .uv_index = 6, .stride = 4, .has_setter = false, .expression = "v4_w(fragment_uv6)" },

	{ .uv_index = 7, .stride = 4, .has_setter = false, .expression = "v4_x(fragment_uv7)", .declaration = "let fragment_uv7 = ND_geompropvalue_vector4(\"UV7\", (0.0f, 0.0f, 0.0f, 0.0f));" },
	{ .uv_index = 7, .stride = 4, .has_setter = false, .expression = "v4_y(fragment_uv7)" },
	{ .uv_index = 7, .stride = 4, .has_setter = false, .expression = "v4_z(fragment_uv7)" },
	{ .uv_index = 7, .stride = 4, .has_setter = false, .expression = "v4_w(fragment_uv7)" },
};

VaryingAllocator::VaryingAllocator() {
	reset();
}

void VaryingAllocator::reset() {
	uv0_ptr = 0;
	uv1_ptr = 0;
	slot_count = MAX_SLOTS - 4; // start off without UV0 and UV1
	free_slot_pointer = 0;
	varyings.clear();
	memcpy(&slots, &slot_descriptors[4], sizeof(Slot) * slot_count);
}

void VaryingAllocator::release_uv0_slot() {
	if (uv0_ptr) {
		return;
	}
	memcpy(&slots[slot_count], &slot_descriptors[0], sizeof(Slot) * 2);
	uv0_ptr = slot_count;
	slot_count += 2;
}

void VaryingAllocator::release_uv1_slot() {
	if (uv1_ptr) {
		return;
	}
	memcpy(&slots[slot_count], &slot_descriptors[2], sizeof(Slot) * 2);
	uv1_ptr = slot_count;
	slot_count += 2;
}

bool VaryingAllocator::is_supported_type(PortType p_type) const {
	return slot_requirement[p_type] != 0;
}

const VaryingAllocator::VaryingDescriptor *VaryingAllocator::allocate(const godot::String &p_varying_name, PortType p_type, std::string &p_out_reason) {
	if (!is_supported_type(p_type)) {
		p_out_reason = std::format("Type not supported: {}", port_type_name(p_type));
		return nullptr;
	}

	if (varyings.has(p_varying_name)) {
		const VaryingAllocator::VaryingDescriptor &result = varyings[p_varying_name];
		if (result.type != p_type) {
			p_out_reason = std::format("[INTERNAL ERROR] Allocating existing verying with different type. Stored: {}, Requested: {}", port_type_name(result.type), port_type_name(p_type));
			return nullptr;
		}
		return &result;
	}

	uint8_t slot_count_required = slot_requirement[p_type];
	if (free_slot_pointer + slot_count_required > slot_count) {
		p_out_reason = std::format("Reached varying limit: cannot allocate more than {} floats. (currently used: {})", (uint32_t)slot_count, (uint32_t)(free_slot_pointer + slot_count_required));
		return nullptr;
	}
	uint8_t slot_index = free_slot_pointer;
	free_slot_pointer += slot_count_required;

	uint8_t count = slot_requirement[p_type];
	VaryingAllocator::VaryingDescriptor v{
		.type = p_type,
		.slot_ptr = slot_index,
		.slot_count = count,
	};

	return &(varyings.insert(p_varying_name, std::move(v))->value);
}

const VaryingAllocator::VaryingDescriptor *VaryingAllocator::get_varying(const godot::String &p_varying_name) {
	if (!varyings.has(p_varying_name)) {
		return nullptr;
	}
	return &(varyings[p_varying_name]);
}

std::string VaryingAllocator::get_vertex_slot_expression(uint8_t p_slot_index) const {
	if (p_slot_index >= free_slot_pointer ||
			!slots[p_slot_index].has_setter) {
		return "0.0f";
	} else {
		return std::format("varying_slot_{}", p_slot_index);
	}
}

void VaryingAllocator::assign_varying_slot_names(const VaryingDescriptor &p_varying) {
	for (int i = 0; i < p_varying.slot_count; ++i) {
		slots[p_varying.slot_ptr + i].has_setter = true;
	}
}

std::string VaryingAllocator::get_vertex_slot_var_name(const VaryingDescriptor &p_varying, uint8_t p_index) const {
	return get_vertex_slot_expression(p_varying.slot_ptr + p_index);
}

std::string VaryingAllocator::get_vertex_expression_for_uv(uint8_t p_index) const {
	static uint8_t slot_offset_by_uv_index[8] = { uv0_ptr, uv1_ptr, 0, 4, 8, 12, 16, 20 };
	static uint8_t uv_size_by_uv_index[8] = { 2, 2, 4, 4, 4, 4, 4, 4 };
	uint8_t uv_start_offset = slot_offset_by_uv_index[p_index];

	if (uv_start_offset >= free_slot_pointer) {
		return "-";
	}
	if (uv_size_by_uv_index[p_index] == 2) {
		return std::format("ND_combine2_vector2({}, {})", get_vertex_slot_expression(uv_start_offset + 0),
				get_vertex_slot_expression(uv_start_offset + 1));
	} else {
		return std::format("ND_combine4_vector4({}, {}, {}, {})", get_vertex_slot_expression(uv_start_offset + 0),
				get_vertex_slot_expression(uv_start_offset + 1),
				get_vertex_slot_expression(uv_start_offset + 2),
				get_vertex_slot_expression(uv_start_offset + 3));
	}
}

void VaryingAllocator::fill_uv_read_declarations(VisualProgramBuilderContext &p_context) {
	uint8_t slot_index = 0;
	while (slot_index < free_slot_pointer) {
		const Slot &slot = slots[slot_index];
		p_context.code_parts.push_back(slot.declaration);
		slot_index += slot.stride;
	}
}

std::optional<std::string> VaryingAllocator::get_fragment_expression_for_varying(const VaryingAllocator::VaryingDescriptor &p_varying) const {
	if (p_varying.type == PortType::BOOL ||
			p_varying.type == PortType::INT ||
			p_varying.type == PortType::UINT ||
			p_varying.type == PortType::FLOAT) {
		return slots[p_varying.slot_ptr].expression;
	} else if (p_varying.type == PortType::VEC2F) {
		return std::format("ND_combine2_vector2({}, {})", slots[p_varying.slot_ptr + 0].expression,
				slots[p_varying.slot_ptr + 1].expression);
	} else if (p_varying.type == PortType::VEC3F) {
		return std::format("ND_combine3_vector3({}, {}, {})", slots[p_varying.slot_ptr + 0].expression,
				slots[p_varying.slot_ptr + 1].expression,
				slots[p_varying.slot_ptr + 2].expression);
	} else if (p_varying.type == PortType::VEC4F) {
		return std::format("ND_combine4_vector4({}, {}, {}, {})", slots[p_varying.slot_ptr + 0].expression,
				slots[p_varying.slot_ptr + 1].expression,
				slots[p_varying.slot_ptr + 2].expression,
				slots[p_varying.slot_ptr + 3].expression);
	} else {
		return std::nullopt;
	}
}

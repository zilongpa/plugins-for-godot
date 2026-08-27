//
//  PHASEOccluder3D.h
//
//  Copyright © 2026 Apple Inc.
//

#ifndef PHASEOccluder3D_H
#define PHASEOccluder3D_H

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/variant/node_path.hpp>

namespace godot {
	enum PHASEMaterialPreset
	{
	    MaterialPresetCardboard,
	    MaterialPresetGlass,
	    MaterialPresetBrick,
	    MaterialPresetConcrete,
	    MaterialPresetDrywall,
	    MaterialPresetWood
	};

class PHASEOccluder3D : public Node3D {
	GDCLASS(PHASEOccluder3D, Node3D)

private:
	int64_t occluderId;
	godot::PHASEMaterialPreset material;
	NodePath mesh_node_path;

	void _create_occluder_from_mesh();

    void phase_ready();
    void phase_physics_process();

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	PHASEOccluder3D();
	~PHASEOccluder3D();

	void set_material(godot::PHASEMaterialPreset p_material);
	godot::PHASEMaterialPreset get_material() const;

	void set_mesh_node_path(const NodePath &p_path);
	NodePath get_mesh_node_path() const;

};

}

VARIANT_ENUM_CAST(godot::PHASEMaterialPreset);

#endif
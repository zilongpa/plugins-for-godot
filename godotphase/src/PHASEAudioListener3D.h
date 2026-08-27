//
//  PHASEAudioListener3D.h
//
//  Copyright © 2026 Apple Inc.
//

#ifndef PHASEAudioListener3D_H
#define PHASEAudioListener3D_H

#include <godot_cpp/classes/node3d.hpp>
#import <PHASE/PHASE.h>

namespace godot {

class PHASEAudioListener3D : public Node3D {
	GDCLASS(PHASEAudioListener3D, Node3D)

private:
    bool head_tracking = false;

    void phase_ready();
    void phase_physics_process();

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	~PHASEAudioListener3D();

	void set_head_tracking(bool enabled);
	bool get_head_tracking() const;
};

}

#endif
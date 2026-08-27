//
//  PHASEAudioStreamPlayer3D.h
//
//  Copyright © 2026 Apple Inc.
//

#ifndef PHASEAudioStreamPlayer3D_H
#define PHASEAudioStreamPlayer3D_H

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/audio_stream.hpp>
#include <atomic>

namespace godot {

class PHASEAudioStreamPlayer3DInternal;

class PHASEAudioStreamPlayer3D : public Node3D {
	GDCLASS(PHASEAudioStreamPlayer3D, Node3D)

public:
	enum MixerType {
		MIXER_SPATIAL,
		MIXER_CHANNEL,
		MIXER_AMBIENT
	};

private:
	Ref<AudioStream> stream;
	bool autoplay;
	std::atomic<bool> stream_paused;
	float volume_db;
	float pitch_scale;

	MixerType mixer_type;

	bool enable_direct_path;
	bool enable_early_reflections;
	bool enable_late_reverb;
	double cull_distance;
	float rolloff_factor;

	double direct_path_send;
	double early_reflections_send;
	double late_reverb_send;

	int max_polyphony;

	Vector<PHASEAudioStreamPlayer3DInternal*> voice_pool;

	void set_mixer_send_parameter(const char* param_suffix, double value, double& stored_value);
	double get_mixer_send_parameter(const char* param_suffix, const double& stored_value) const;
	void ensure_playback_limit();
	void stop_active_voices();

	void phase_ready();
	void phase_process(double delta);
	void phase_physics_process();

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	PHASEAudioStreamPlayer3D();
	~PHASEAudioStreamPlayer3D();

	void set_stream(Ref<AudioStream> p_stream);
	Ref<AudioStream> get_stream() const;

	void play(float p_from_pos = 0.0);
	void seek(float p_seconds);
	void stop();
	bool is_playing() const;
	float get_playback_position();

	void set_playing(bool p_enable);

	void set_volume_db(float p_volume);
	float get_volume_db() const;

	void set_volume_linear(float p_volume);
	float get_volume_linear() const;

	void set_pitch_scale(float p_pitch_scale);
	float get_pitch_scale() const;

	void set_autoplay(bool p_enable);
	bool is_autoplay_enabled() const;

	void set_stream_paused(bool p_pause);
	bool get_stream_paused() const;

	bool has_stream_playback();
	Ref<AudioStreamPlayback> get_stream_playback();

	void set_max_polyphony(int p_max_polyphony);
	int get_max_polyphony() const;

	void set_mixer_type(MixerType p_mixer_type);
	MixerType get_mixer_type() const;

	void set_enable_direct_path(bool p_enable);
	bool get_enable_direct_path() const;

	void set_enable_early_reflections(bool p_enable);
	bool get_enable_early_reflections() const;

	void set_enable_late_reverb(bool p_enable);
	bool get_enable_late_reverb() const;

	void set_cull_distance(double p_distance);
	double get_cull_distance() const;

	void set_rolloff_factor(float p_factor);
	float get_rolloff_factor() const;

	void set_direct_path_send(double p_send_level);
	double get_direct_path_send() const;

	void set_early_reflections_send(double p_send_level);
	double get_early_reflections_send() const;

	void set_late_reverb_send(double p_send_level);
	double get_late_reverb_send() const;
};

}

VARIANT_ENUM_CAST(PHASEAudioStreamPlayer3D::MixerType);

#endif

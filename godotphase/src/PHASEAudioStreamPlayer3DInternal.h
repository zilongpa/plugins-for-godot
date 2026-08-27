//
//  PHASEAudioStreamPlayer3DInternal.h
//
//  Copyright © 2026 Apple Inc.
//

#ifndef PHASEAudioStreamPlayer3DInternal_H
#define PHASEAudioStreamPlayer3DInternal_H

#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <atomic>
#include <mutex>
#import <PHASE/PHASE.h>
#import "PHASEWrapperRingBuffer.h"

#define PHASEInvalidInstanceHandle (-1)

namespace godot {

class PHASEAudioStreamPlayer3D;

class PHASEAudioStreamPlayer3DInternal {
private:
	static constexpr int RING_BUFFER_FRAME_SIZE = 4096;
	static constexpr int RING_BUFFER_COUNT = 24;

	PHASEAudioStreamPlayer3D* player_node;

	Ref<AudioStreamPlayback> stream_playback;
	std::mutex playback_mutex;
	std::atomic<bool> playing;
	std::atomic<bool> object_valid;
	std::atomic<bool> ready_for_deletion;
	std::atomic<bool> stream_ended;
	double stream_position;

	int64_t phase_source_id;
	int64_t phase_mixer_id;
	int64_t phase_stream_node_id;
	int64_t phase_sound_event_id;

	std::atomic<float> current_pitch_scale;
	bool phase_resources_initialized;
	PHASEWrapperRingBuffer* ring_buffer;
	PackedVector2Array accumulation_buffer;
	int accumulation_offset;

	void initialize_phase_resources();
	void cleanup_phase_resources();

	void create_phase_source();
	void create_phase_mixer();
	void create_phase_pull_stream_node();
	void register_phase_sound_event();

	void update_phase_source_transform();
	AVAudioFormat* create_audio_format();
	NSString* get_mixer_name() const;

	bool start_playback(const Ref<AudioStream> &p_stream, float p_from_position, float p_pitch_scale);
	void stop_playback();
	Ref<AudioStreamPlayback> create_and_start_playback(const Ref<AudioStream> &p_stream, float p_from_position);
	void output_silence(AudioBufferList* outputData);
	void fill_ring_buffer(double delta);
	void flush_accumulation_buffer(bool force_partial = false);

public:
	PHASEAudioStreamPlayer3DInternal(PHASEAudioStreamPlayer3D* p_player);
	~PHASEAudioStreamPlayer3DInternal();

	bool play(const Ref<AudioStream> &p_stream, float p_from_position, float p_pitch_scale);
	void stop();
	void seek(float p_seconds);
	bool is_playing() const;
	void update_transform();
	float get_playback_position() const;

	void process(double delta);

	void set_volume_db(float p_volume_db);
	void set_pitch_scale(float p_pitch_scale);
	void apply_mixer_send_levels();
	void resume_stream_playback();

	int64_t get_phase_source_id() const { return phase_source_id; }
	int64_t get_phase_sound_event_id() const { return phase_sound_event_id; }
	bool is_ready_for_deletion() const { return ready_for_deletion.load(std::memory_order_acquire); }
	Ref<AudioStreamPlayback> get_stream_playback() const { return stream_playback; }
};

}

#endif

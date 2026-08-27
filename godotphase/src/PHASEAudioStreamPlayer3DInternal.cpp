//
//  PHASEAudioStreamPlayer3DInternal.cpp
//
//  Copyright © 2026 Apple Inc.
//

#include "PHASEAudioStreamPlayer3DInternal.h"
#include "PHASEAudioStreamPlayer3D.h"
#include "PHASEUtils.h"
#import "PHASEWrapper.h"
#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

PHASEAudioStreamPlayer3DInternal::PHASEAudioStreamPlayer3DInternal(PHASEAudioStreamPlayer3D* p_player) {
	player_node = p_player;
	phase_source_id = PHASEInvalidInstanceHandle;
	phase_mixer_id = PHASEInvalidInstanceHandle;
	phase_stream_node_id = PHASEInvalidInstanceHandle;
	phase_sound_event_id = PHASEInvalidInstanceHandle;

	playing.store(false, std::memory_order_relaxed);
	object_valid.store(true, std::memory_order_release);
	ready_for_deletion.store(false, std::memory_order_relaxed);
	stream_ended.store(false, std::memory_order_relaxed);
	stream_position = 0.0;
	current_pitch_scale.store(1.0f, std::memory_order_relaxed);
	phase_resources_initialized = false;
	ring_buffer = nil;
	accumulation_offset = 0;
}

PHASEAudioStreamPlayer3DInternal::~PHASEAudioStreamPlayer3DInternal() {
	object_valid.store(false, std::memory_order_release);
	stop_playback();
	cleanup_phase_resources();
}

void PHASEAudioStreamPlayer3DInternal::initialize_phase_resources() {
	PHASEEngineWrapper* engine_wrapper = [PHASEEngineWrapper sharedInstance];
	if (!engine_wrapper || ![engine_wrapper isInitialized]) {
		ERR_PRINT("PHASE engine not initialized");
		return;
	}

	create_phase_source();
	if (phase_source_id == PHASEInvalidInstanceHandle) {
		return;
	}

	create_phase_mixer();
	if (phase_mixer_id == PHASEInvalidInstanceHandle) {
		cleanup_phase_resources();
		return;
	}

	create_phase_pull_stream_node();
	if (phase_stream_node_id == PHASEInvalidInstanceHandle) {
		cleanup_phase_resources();
		return;
	}

	register_phase_sound_event();
	phase_resources_initialized = true;
}

void PHASEAudioStreamPlayer3DInternal::cleanup_phase_resources() {
	PHASEEngineWrapper* engine_wrapper = [PHASEEngineWrapper sharedInstance];

	if (phase_sound_event_id != PHASEInvalidInstanceHandle) {
		BOOL success = [engine_wrapper stopSoundEventWithId:phase_sound_event_id];
		if (!success) {
			ERR_PRINT(String("Failed to stop PHASE sound event during cleanup with id: ") + String::num_int64(phase_sound_event_id));
		}
		phase_sound_event_id = PHASEInvalidInstanceHandle;
	}

	if (phase_source_id != PHASEInvalidInstanceHandle) {
		NSString* event_name = [NSString stringWithFormat:@"AudioStreamEvent_%lld", phase_source_id];
		[engine_wrapper unregisterSoundEventWithName:event_name];
	}

	if (phase_stream_node_id != PHASEInvalidInstanceHandle) {
		[engine_wrapper destroySoundEventNodeWithId:phase_stream_node_id];
		phase_stream_node_id = PHASEInvalidInstanceHandle;
	}

	if (phase_mixer_id != PHASEInvalidInstanceHandle) {
		[engine_wrapper destroyMixerWithId:phase_mixer_id];
		phase_mixer_id = PHASEInvalidInstanceHandle;
	}

	if (phase_source_id != PHASEInvalidInstanceHandle) {
		[engine_wrapper destroySourceWithId:phase_source_id];
		phase_source_id = PHASEInvalidInstanceHandle;
	}
}

void PHASEAudioStreamPlayer3DInternal::create_phase_source() {
	PHASEEngineWrapper* engine_wrapper = [PHASEEngineWrapper sharedInstance];
	phase_source_id = [engine_wrapper createSource];

	if (phase_source_id == PHASEInvalidInstanceHandle) {
		ERR_PRINT("Failed to create PHASE source");
		return;
	}

	update_phase_source_transform();
}

void PHASEAudioStreamPlayer3DInternal::create_phase_mixer() {
	PHASEEngineWrapper* engine_wrapper = [PHASEEngineWrapper sharedInstance];

	NSString* mixer_name = get_mixer_name();

	switch (player_node->get_mixer_type()) {
		case PHASEAudioStreamPlayer3D::MIXER_SPATIAL: {
			DirectivityModelParameters source_directivity { DirectivityType::None, 0, nullptr };
			DirectivityModelParameters listener_directivity { DirectivityType::None, 0, nullptr };

			phase_mixer_id = [engine_wrapper createSpatialMixerWithName:mixer_name
				enableDirectPath:player_node->get_enable_direct_path()
				enableEarlyReflections:player_node->get_enable_early_reflections()
				enableLateReverb:player_node->get_enable_late_reverb()
				cullDistance:player_node->get_cull_distance()
				rolloffFactor:player_node->get_rolloff_factor()
				sourceDirectivityModelParameters:source_directivity
				listenerDirectivityModelParameters:listener_directivity];
		} break;

		case PHASEAudioStreamPlayer3D::MIXER_CHANNEL: {
			phase_mixer_id = [engine_wrapper createChannelMixerWithName:mixer_name
				channelLayout:ChannelLayoutTypeStereo];
		} break;

		case PHASEAudioStreamPlayer3D::MIXER_AMBIENT: {
			::Quaternion orientation { 1.0f, 0.0f, 0.0f, 0.0f };
			phase_mixer_id = [engine_wrapper createAmbientMixerWithName:mixer_name
				channelLayout:ChannelLayoutTypeStereo
				orientation:orientation];
		} break;
	}

	if (phase_mixer_id == PHASEInvalidInstanceHandle) {
		ERR_PRINT("Failed to create PHASE mixer");
	}
}

void PHASEAudioStreamPlayer3DInternal::create_phase_pull_stream_node() {
	PHASEEngineWrapper* engine_wrapper = [PHASEEngineWrapper sharedInstance];
	AVAudioFormat* format = create_audio_format();
	NSString* stream_name = [NSString stringWithFormat:@"AudioStreamPullNode_%lld", phase_source_id];

	@try {
		phase_stream_node_id = [engine_wrapper createSoundEventPullStreamNodeWithAsset:stream_name
			mixerId:phase_mixer_id
			format:format
			calibrationMode:CalibrationModeNone
			level:1.0];
	} @catch (NSException* exception) {
		ERR_PRINT(String("Failed to create PHASE pull stream node: ") + String([exception.reason UTF8String]));
	}
}

void PHASEAudioStreamPlayer3DInternal::register_phase_sound_event() {
	PHASEEngineWrapper* engine_wrapper = [PHASEEngineWrapper sharedInstance];
	NSString* event_name = [NSString stringWithFormat:@"AudioStreamEvent_%lld", phase_source_id];

	BOOL success = [engine_wrapper registerSoundEventWithName:event_name rootNodeId:phase_stream_node_id];
	if (!success) {
		ERR_PRINT("Failed to register PHASE sound event");
	}
}

void PHASEAudioStreamPlayer3DInternal::update_phase_source_transform() {
	if (phase_source_id == PHASEInvalidInstanceHandle || !player_node) {
		return;
	}

	PHASEEngineWrapper* engine_wrapper = [PHASEEngineWrapper sharedInstance];
	Transform3D transform = player_node->get_global_transform();
	simd_float4x4 matrix = PHASEUtils::transform_to_simd_float4x4(transform);
	BOOL success = [engine_wrapper setSourceTransformWithId:phase_source_id transform:matrix];
	if (!success) {
		ERR_PRINT(String("Failed to set source transform for source ID: ") + String::num_int64(phase_source_id));
	}
}

AVAudioFormat* PHASEAudioStreamPlayer3DInternal::create_audio_format() {
	@autoreleasepool {
		double sample_rate = AudioServer::get_singleton()->get_mix_rate();

		AVAudioChannelLayout* layout = [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_Stereo];

		AudioStreamBasicDescription desc = { 0 };
		desc.mSampleRate = sample_rate;
		desc.mFormatID = kAudioFormatLinearPCM;
		desc.mFormatFlags = kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsNonInterleaved;
		desc.mBitsPerChannel = 32;
		desc.mChannelsPerFrame = 2;
		desc.mFramesPerPacket = 1;
		desc.mBytesPerFrame = 32 / 8;
		desc.mBytesPerPacket = desc.mBytesPerFrame * desc.mFramesPerPacket;

		return [[AVAudioFormat alloc] initWithStreamDescription:&desc channelLayout:layout];
	}
}

NSString* PHASEAudioStreamPlayer3DInternal::get_mixer_name() const {
	return [NSString stringWithFormat:@"AudioStreamMixer_%lld", phase_source_id];
}

Ref<AudioStreamPlayback> PHASEAudioStreamPlayer3DInternal::create_and_start_playback(const Ref<AudioStream> &p_stream, float p_from_position) {
	Ref<AudioStreamPlayback> new_playback = p_stream->instantiate_playback();

	if (!new_playback.is_valid()) {
		ERR_PRINT("Failed to create stream playback");
		return Ref<AudioStreamPlayback>();
	}

	if (p_from_position > 0.0f) {
		new_playback->start(0.0);
		new_playback->seek(p_from_position);
		stream_position = p_from_position;
	} else {
		new_playback->start(0.0);
		stream_position = 0.0;
	}

	return new_playback;
}

void PHASEAudioStreamPlayer3DInternal::output_silence(AudioBufferList* outputData) {
	for (UInt32 i = 0; i < outputData->mNumberBuffers; i++) {
		memset(outputData->mBuffers[i].mData, 0, outputData->mBuffers[i].mDataByteSize);
	}
}

bool PHASEAudioStreamPlayer3DInternal::play(const Ref<AudioStream> &p_stream, float p_from_position, float p_pitch_scale) {
	if (p_stream.is_null()) {
		ERR_PRINT("No AudioStream provided");
		return false;
	}

	return start_playback(p_stream, p_from_position, p_pitch_scale);
}

bool PHASEAudioStreamPlayer3DInternal::start_playback(const Ref<AudioStream> &p_stream, float p_from_position, float p_pitch_scale) {
	if (!phase_resources_initialized) {
		initialize_phase_resources();
	}

	if (phase_source_id == PHASEInvalidInstanceHandle) {
		ERR_PRINT("PHASE resources not initialized");
		return false;
	}

	ready_for_deletion.store(false, std::memory_order_relaxed);
	stream_ended.store(false, std::memory_order_relaxed);

	Ref<AudioStreamPlayback> new_playback = create_and_start_playback(p_stream, p_from_position);
	if (!new_playback.is_valid()) {
		ERR_PRINT("New playback is invalid");
		return false;
	}

	current_pitch_scale.store(p_pitch_scale, std::memory_order_relaxed);

	{
		std::lock_guard<std::mutex> lock(playback_mutex);
		stream_playback = new_playback;
	}

	ring_buffer = [[PHASEWrapperRingBuffer alloc] initWithFrameSize:RING_BUFFER_FRAME_SIZE numberOfBuffers:RING_BUFFER_COUNT format:create_audio_format()];

	// Pre-fill one slot of silence so the renderBlock never sees an empty buffer on its first call.
	PackedVector2Array silence;
	silence.resize(RING_BUFFER_FRAME_SIZE);
	silence.fill(Vector2(0.0f, 0.0f));
	[ring_buffer write:(float*)silence.ptr() frameCount:(AVAudioFrameCount)RING_BUFFER_FRAME_SIZE];

	PHASEWrapperRingBuffer* captured_ring_buffer = ring_buffer;

	playing.store(true, std::memory_order_release);

	PHASEEngineWrapper* engine_wrapper = [PHASEEngineWrapper sharedInstance];
	NSString* event_name = [NSString stringWithFormat:@"AudioStreamEvent_%lld", phase_source_id];
	NSString* stream_name = [NSString stringWithFormat:@"AudioStreamPullNode_%lld", phase_source_id];

	phase_sound_event_id = [engine_wrapper playSoundEventWithName:event_name
		sourceId:phase_source_id
		mixerIds:&phase_mixer_id
		numMixers:1
		streamName:stream_name
		renderBlock:^OSStatus(BOOL* isSilence, const AudioTimeStamp* timestamp, AVAudioFrameCount frameCount, AudioBufferList* outputData) {
			if (!object_valid.load(std::memory_order_acquire)) {
				output_silence(outputData);
				return noErr;
			}

			if (!playing.load(std::memory_order_relaxed)) {
				output_silence(outputData);
				return noErr;
			}

			if (player_node && player_node->get_stream_paused()) {
				output_silence(outputData);
				return noErr;
			}

			if (![captured_ring_buffer read:outputData frameCount:frameCount]) {
				output_silence(outputData);
				return noErr;
			}

			*isSilence = NO;
			return noErr;
		}
		completionHandlerBlock:^(PHASESoundEventStartHandlerReason reason, int64_t sourceId, int64_t soundEventId) {
			if (object_valid.load(std::memory_order_acquire)) {
				playing.store(false, std::memory_order_release);
				ready_for_deletion.store(true, std::memory_order_release);
			}
		}];

	if (phase_sound_event_id == PHASEInvalidInstanceHandle) {
		ERR_PRINT("Failed to play sound event");
		stop_playback();
		return false;
	}

	apply_mixer_send_levels();

	return true;
}

void PHASEAudioStreamPlayer3DInternal::stop() {
	stop_playback();
}

void PHASEAudioStreamPlayer3DInternal::stop_playback() {
	playing.store(false, std::memory_order_release);

	PHASEEngineWrapper* engine_wrapper = [PHASEEngineWrapper sharedInstance];
	if (phase_sound_event_id != PHASEInvalidInstanceHandle) {
		BOOL success = [engine_wrapper stopSoundEventWithId:phase_sound_event_id];
		if (!success) {
			ERR_PRINT(String("Failed to stop PHASE sound event with id: ") + String::num_int64(phase_sound_event_id));
		}
		phase_sound_event_id = PHASEInvalidInstanceHandle;
	}

	ring_buffer = nil;
	accumulation_offset = 0;
	stream_position = 0.0;

	std::lock_guard<std::mutex> lock(playback_mutex);
	if (stream_playback.is_valid()) {
		stream_playback->stop();
		stream_playback.unref();
	}
}

bool PHASEAudioStreamPlayer3DInternal::is_playing() const {
	return playing.load(std::memory_order_relaxed);
}

void PHASEAudioStreamPlayer3DInternal::update_transform() {
	update_phase_source_transform();
}

float PHASEAudioStreamPlayer3DInternal::get_playback_position() const {
	return stream_position;
}

void PHASEAudioStreamPlayer3DInternal::process(double delta) {
	bool is_playing_now = playing.load(std::memory_order_relaxed);
	bool is_paused = player_node ? player_node->get_stream_paused() : false;

	if (is_playing_now && !is_paused) {
		stream_position += delta;
	}

	if (is_playing_now) {
		fill_ring_buffer(delta);

		// Once stream data is exhausted and the ring buffer has been fully
		// consumed by PHASE, stop the sound event. The completion handler will
		// set ready_for_deletion = true so the voice is removed from the pool.
		if (stream_ended.load(std::memory_order_relaxed) && ring_buffer && [ring_buffer isEmpty]) {
			stop_playback();
		}
	}
}

void PHASEAudioStreamPlayer3DInternal::flush_accumulation_buffer(bool force_partial) {
	if (!ring_buffer) {
		return;
	}

	while (accumulation_offset >= RING_BUFFER_FRAME_SIZE) {
		[ring_buffer write:(float*)accumulation_buffer.ptr() frameCount:(AVAudioFrameCount)RING_BUFFER_FRAME_SIZE];

		int remaining = accumulation_offset - RING_BUFFER_FRAME_SIZE;
		if (remaining > 0) {
			Vector2* ptr = accumulation_buffer.ptrw();
			memmove(ptr, ptr + RING_BUFFER_FRAME_SIZE, remaining * sizeof(Vector2));
		}
		accumulation_offset = remaining;
	}

	if (force_partial && accumulation_offset > 0) {
		if (accumulation_buffer.size() < RING_BUFFER_FRAME_SIZE) {
			accumulation_buffer.resize(RING_BUFFER_FRAME_SIZE);
		}
		int pad_frames = RING_BUFFER_FRAME_SIZE - accumulation_offset;
		memset(accumulation_buffer.ptrw() + accumulation_offset, 0, pad_frames * sizeof(Vector2));
		[ring_buffer write:(float*)accumulation_buffer.ptr() frameCount:(AVAudioFrameCount)RING_BUFFER_FRAME_SIZE];
		accumulation_offset = 0;
	}
}

void PHASEAudioStreamPlayer3DInternal::fill_ring_buffer(double delta) {
	if (!ring_buffer) {
		ERR_PRINT("fill_ring_buffer: no ring buffer");
		return;
	}

	if (stream_ended.load(std::memory_order_relaxed)) {
		return;
	}

	if (player_node && player_node->get_stream_paused()) {
		return;
	}

	Ref<AudioStreamPlayback> playback_copy;
	{
		std::lock_guard<std::mutex> lock(playback_mutex);
		playback_copy = stream_playback;
	}

	if (!playback_copy.is_valid()) {
		ERR_PRINT("fill_ring_buffer: playback became invalid");
		stream_ended.store(true, std::memory_order_release);
		flush_accumulation_buffer(true);
		return;
	}

	if (!playback_copy->is_playing()) {
		stream_ended.store(true, std::memory_order_release);
		flush_accumulation_buffer(true);
		return;
	}

	double sample_rate = AudioServer::get_singleton()->get_mix_rate();
	int frames_to_mix = (int)(sample_rate * delta);
	if (frames_to_mix <= 0) {
		return;
	}

	// Cap to one ring buffer slot to avoid overwriting unread data after stalls
	// (e.g. window focus loss causes large delta spikes)
	if (frames_to_mix > RING_BUFFER_FRAME_SIZE) {
		frames_to_mix = RING_BUFFER_FRAME_SIZE;
	}

	float pitch = current_pitch_scale.load(std::memory_order_relaxed);
	PackedVector2Array audio_data = playback_copy->mix_audio(pitch, frames_to_mix);
	int mixed_frames = audio_data.size();

	if (mixed_frames <= 0) {
		stream_ended.store(true, std::memory_order_release);
		flush_accumulation_buffer(true);
		return;
	}

	int needed_size = accumulation_offset + mixed_frames;
	if (accumulation_buffer.size() < needed_size) {
		accumulation_buffer.resize(needed_size);
	}
	memcpy(accumulation_buffer.ptrw() + accumulation_offset,
		audio_data.ptr(),
		mixed_frames * sizeof(Vector2));
	accumulation_offset += mixed_frames;

	flush_accumulation_buffer(false);
}

void PHASEAudioStreamPlayer3DInternal::set_volume_db(float p_volume_db) {
	if (phase_source_id == PHASEInvalidInstanceHandle) {
		return;
	}
	// PHASE source gain is [0,1] — clamp so values above 0dB saturate at unity rather than clipping.
	double linear_gain = CLAMP(UtilityFunctions::db_to_linear(p_volume_db), 0.0, 1.0);
	PHASEEngineWrapper* engine_wrapper = [PHASEEngineWrapper sharedInstance];
	[engine_wrapper setSourceGainWithId:phase_source_id sourceGain:linear_gain];
}

void PHASEAudioStreamPlayer3DInternal::set_pitch_scale(float p_pitch_scale) {
	if (p_pitch_scale <= 0.0f) {
		ERR_PRINT("Pitch scale must be positive");
		return;
	}

	current_pitch_scale.store(p_pitch_scale, std::memory_order_relaxed);
}

void PHASEAudioStreamPlayer3DInternal::apply_mixer_send_levels() {
	if (phase_sound_event_id == PHASEInvalidInstanceHandle || !player_node) {
		return;
	}

	// Only apply send levels to spatial mixers
	if (player_node->get_mixer_type() != PHASEAudioStreamPlayer3D::MIXER_SPATIAL) {
		return;
	}

	PHASEEngineWrapper* engine_wrapper = [PHASEEngineWrapper sharedInstance];
	NSString* mixer_name = [NSString stringWithFormat:@"AudioStreamMixer_%lld", phase_source_id];

	NSString* direct_path_param = [mixer_name stringByAppendingString:@"DirectPathSend"];
	BOOL success = [engine_wrapper setMetaParameterWithId:phase_sound_event_id parameterName:direct_path_param doubleValue:player_node->get_direct_path_send()];
	if (!success) {
		ERR_PRINT(String("Failed to set DirectPathSend metaParameter on sound event ID: ") + String::num_int64(phase_sound_event_id));
	}

	NSString* early_reflections_param = [mixer_name stringByAppendingString:@"EarlyReflectionsSend"];
	success = [engine_wrapper setMetaParameterWithId:phase_sound_event_id parameterName:early_reflections_param doubleValue:player_node->get_early_reflections_send()];
	if (!success) {
		ERR_PRINT(String("Failed to set EarlyReflectionsSend metaParameter on sound event ID: ") + String::num_int64(phase_sound_event_id));
	}

	NSString* late_reverb_param = [mixer_name stringByAppendingString:@"LateReverbSend"];
	success = [engine_wrapper setMetaParameterWithId:phase_sound_event_id parameterName:late_reverb_param doubleValue:player_node->get_late_reverb_send()];
	if (!success) {
		ERR_PRINT(String("Failed to set LateReverbSend metaParameter on sound event ID: ") + String::num_int64(phase_sound_event_id));
	}
}

void PHASEAudioStreamPlayer3DInternal::resume_stream_playback() {
	std::lock_guard<std::mutex> lock(playback_mutex);
	if (playing.load(std::memory_order_relaxed) && stream_playback.is_valid() && !stream_playback->is_playing()) {
		stream_playback->start(stream_position);
	}
}

void PHASEAudioStreamPlayer3DInternal::seek(float p_seconds) {
	std::lock_guard<std::mutex> lock(playback_mutex);
	if (stream_playback.is_valid()) {
		stream_playback->seek(p_seconds);
	}
}

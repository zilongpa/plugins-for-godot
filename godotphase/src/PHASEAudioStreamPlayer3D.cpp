//
//  PHASEAudioStreamPlayer3D.cpp
//
//  Copyright © 2026 Apple Inc.
//

#include "PHASEAudioStreamPlayer3D.h"
#include "PHASEAudioStreamPlayer3DInternal.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#import "PHASEWrapper.h"

using namespace godot;

PHASEAudioStreamPlayer3D::PHASEAudioStreamPlayer3D() {
	mixer_type = MIXER_SPATIAL;
	autoplay = false;
	stream_paused = false;
	volume_db = 0.0f;
	pitch_scale = 1.0f;
	max_polyphony = 1;

	enable_direct_path = true;
	enable_early_reflections = true;
	enable_late_reverb = true;
	cull_distance = 0.0;
	rolloff_factor = 1.0f;

	direct_path_send = 1.0;
	early_reflections_send = 0.2;
	late_reverb_send = 0.2;
}

PHASEAudioStreamPlayer3D::~PHASEAudioStreamPlayer3D() {
	for (int i = 0; i < voice_pool.size(); i++) {
		if (voice_pool[i]) {
			memdelete(voice_pool[i]);
		}
	}
	voice_pool.clear();
}

void PHASEAudioStreamPlayer3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_stream", "stream"), &PHASEAudioStreamPlayer3D::set_stream);
	ClassDB::bind_method(D_METHOD("get_stream"), &PHASEAudioStreamPlayer3D::get_stream);
	ClassDB::bind_method(D_METHOD("play", "from_pos"), &PHASEAudioStreamPlayer3D::play, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("stop"), &PHASEAudioStreamPlayer3D::stop);
	ClassDB::bind_method(D_METHOD("seek", "seconds"), &PHASEAudioStreamPlayer3D::seek);
	ClassDB::bind_method(D_METHOD("set_playing", "enable"), &PHASEAudioStreamPlayer3D::set_playing);
	ClassDB::bind_method(D_METHOD("is_playing"), &PHASEAudioStreamPlayer3D::is_playing);
	ClassDB::bind_method(D_METHOD("get_playback_position"), &PHASEAudioStreamPlayer3D::get_playback_position);
	ClassDB::bind_method(D_METHOD("set_volume_db", "volume"), &PHASEAudioStreamPlayer3D::set_volume_db);
	ClassDB::bind_method(D_METHOD("get_volume_db"), &PHASEAudioStreamPlayer3D::get_volume_db);
	ClassDB::bind_method(D_METHOD("set_volume_linear", "volume"), &PHASEAudioStreamPlayer3D::set_volume_linear);
	ClassDB::bind_method(D_METHOD("get_volume_linear"), &PHASEAudioStreamPlayer3D::get_volume_linear);
	ClassDB::bind_method(D_METHOD("set_pitch_scale", "pitch_scale"), &PHASEAudioStreamPlayer3D::set_pitch_scale);
	ClassDB::bind_method(D_METHOD("get_pitch_scale"), &PHASEAudioStreamPlayer3D::get_pitch_scale);
	ClassDB::bind_method(D_METHOD("set_autoplay", "enable"), &PHASEAudioStreamPlayer3D::set_autoplay);
	ClassDB::bind_method(D_METHOD("is_autoplay_enabled"), &PHASEAudioStreamPlayer3D::is_autoplay_enabled);
	ClassDB::bind_method(D_METHOD("set_stream_paused", "pause"), &PHASEAudioStreamPlayer3D::set_stream_paused);
	ClassDB::bind_method(D_METHOD("get_stream_paused"), &PHASEAudioStreamPlayer3D::get_stream_paused);
	ClassDB::bind_method(D_METHOD("has_stream_playback"), &PHASEAudioStreamPlayer3D::has_stream_playback);
	ClassDB::bind_method(D_METHOD("get_stream_playback"), &PHASEAudioStreamPlayer3D::get_stream_playback);
	ClassDB::bind_method(D_METHOD("set_max_polyphony", "max_polyphony"), &PHASEAudioStreamPlayer3D::set_max_polyphony);
	ClassDB::bind_method(D_METHOD("get_max_polyphony"), &PHASEAudioStreamPlayer3D::get_max_polyphony);
	ClassDB::bind_method(D_METHOD("set_mixer_type", "mixer_type"), &PHASEAudioStreamPlayer3D::set_mixer_type);
	ClassDB::bind_method(D_METHOD("get_mixer_type"), &PHASEAudioStreamPlayer3D::get_mixer_type);

	ClassDB::bind_method(D_METHOD("set_enable_direct_path", "enable"), &PHASEAudioStreamPlayer3D::set_enable_direct_path);
	ClassDB::bind_method(D_METHOD("get_enable_direct_path"), &PHASEAudioStreamPlayer3D::get_enable_direct_path);
	ClassDB::bind_method(D_METHOD("set_enable_early_reflections", "enable"), &PHASEAudioStreamPlayer3D::set_enable_early_reflections);
	ClassDB::bind_method(D_METHOD("get_enable_early_reflections"), &PHASEAudioStreamPlayer3D::get_enable_early_reflections);
	ClassDB::bind_method(D_METHOD("set_enable_late_reverb", "enable"), &PHASEAudioStreamPlayer3D::set_enable_late_reverb);
	ClassDB::bind_method(D_METHOD("get_enable_late_reverb"), &PHASEAudioStreamPlayer3D::get_enable_late_reverb);
	ClassDB::bind_method(D_METHOD("set_cull_distance", "distance"), &PHASEAudioStreamPlayer3D::set_cull_distance);
	ClassDB::bind_method(D_METHOD("get_cull_distance"), &PHASEAudioStreamPlayer3D::get_cull_distance);
	ClassDB::bind_method(D_METHOD("set_rolloff_factor", "factor"), &PHASEAudioStreamPlayer3D::set_rolloff_factor);
	ClassDB::bind_method(D_METHOD("get_rolloff_factor"), &PHASEAudioStreamPlayer3D::get_rolloff_factor);

	ClassDB::bind_method(D_METHOD("set_direct_path_send", "send_level"), &PHASEAudioStreamPlayer3D::set_direct_path_send);
	ClassDB::bind_method(D_METHOD("get_direct_path_send"), &PHASEAudioStreamPlayer3D::get_direct_path_send);
	ClassDB::bind_method(D_METHOD("set_early_reflections_send", "send_level"), &PHASEAudioStreamPlayer3D::set_early_reflections_send);
	ClassDB::bind_method(D_METHOD("get_early_reflections_send"), &PHASEAudioStreamPlayer3D::get_early_reflections_send);
	ClassDB::bind_method(D_METHOD("set_late_reverb_send", "send_level"), &PHASEAudioStreamPlayer3D::set_late_reverb_send);
	ClassDB::bind_method(D_METHOD("get_late_reverb_send"), &PHASEAudioStreamPlayer3D::get_late_reverb_send);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "stream", PROPERTY_HINT_RESOURCE_TYPE, "AudioStream"), "set_stream", "get_stream");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "volume_db", PROPERTY_HINT_RANGE, "-80,24,suffix:dB"), "set_volume_db", "get_volume_db");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "volume_linear", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "set_volume_linear", "get_volume_linear");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "pitch_scale", PROPERTY_HINT_RANGE, "0.01,4,0.01,or_greater"), "set_pitch_scale", "get_pitch_scale");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "playing", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR), "set_playing", "is_playing");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "autoplay"), "set_autoplay", "is_autoplay_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "stream_paused", PROPERTY_HINT_NONE, ""), "set_stream_paused", "get_stream_paused");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_polyphony", PROPERTY_HINT_RANGE, "1,32,1"), "set_max_polyphony", "get_max_polyphony");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "mixer_type", PROPERTY_HINT_ENUM, "Spatial,Channel,Ambient"), "set_mixer_type", "get_mixer_type");

	ADD_GROUP("Spatial Mixer", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enable_direct_path"), "set_enable_direct_path", "get_enable_direct_path");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enable_early_reflections"), "set_enable_early_reflections", "get_enable_early_reflections");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enable_late_reverb"), "set_enable_late_reverb", "get_enable_late_reverb");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cull_distance", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater"), "set_cull_distance", "get_cull_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "rolloff_factor", PROPERTY_HINT_RANGE, "0,10,0.01,or_greater"), "set_rolloff_factor", "get_rolloff_factor");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "direct_path_send", PROPERTY_HINT_RANGE, "0.0,1.0,0.01"), "set_direct_path_send", "get_direct_path_send");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "early_reflections_send", PROPERTY_HINT_RANGE, "0.0,1.0,0.01"), "set_early_reflections_send", "get_early_reflections_send");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "late_reverb_send", PROPERTY_HINT_RANGE, "0.0,1.0,0.01"), "set_late_reverb_send", "get_late_reverb_send");

	BIND_ENUM_CONSTANT(MIXER_SPATIAL);
	BIND_ENUM_CONSTANT(MIXER_CHANNEL);
	BIND_ENUM_CONSTANT(MIXER_AMBIENT);

	ADD_SIGNAL(MethodInfo("finished"));
}

void PHASEAudioStreamPlayer3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY: {
			phase_ready();
		} break;
		case NOTIFICATION_PROCESS: {
			phase_process(get_process_delta_time());
		} break;
		case NOTIFICATION_PHYSICS_PROCESS: {
			phase_physics_process();
		} break;
		case NOTIFICATION_ENTER_TREE: {
			set_stream_paused(!can_process());
		} break;
		case NOTIFICATION_EXIT_TREE: {
			stop_active_voices();
		} break;
		case NOTIFICATION_PREDELETE: {
			stop_active_voices();
		} break;
        
		case 9003: // NOTIFICATION_SUSPENDED
		case NOTIFICATION_PAUSED:
#if !TARGET_OS_OSX
		case NOTIFICATION_APPLICATION_PAUSED:
		case NOTIFICATION_APPLICATION_FOCUS_OUT:
		case NOTIFICATION_WM_WINDOW_FOCUS_OUT:
#endif
		{
			stream_paused = true;
		} break;

		case NOTIFICATION_UNPAUSED: {
			stream_paused = false;
		} break;

		case 9004: // NOTIFICATION_UNSUSPENDED
#if !TARGET_OS_OSX
		case NOTIFICATION_APPLICATION_RESUMED:
		case NOTIFICATION_APPLICATION_FOCUS_IN:
		case NOTIFICATION_WM_WINDOW_FOCUS_IN:
#endif
		{
			stream_paused = false;
			for (int i = 0; i < voice_pool.size(); i++) {
				if (voice_pool[i]) {
					voice_pool[i]->resume_stream_playback();
				}
			}
		} break;
	}
}

void PHASEAudioStreamPlayer3D::phase_ready() {
	set_process(true);
	set_physics_process(true);
	if (autoplay && stream.is_valid()) {
		play();
	}
}

void PHASEAudioStreamPlayer3D::phase_process(double delta) {
	for (int i = 0; i < voice_pool.size(); i++) {
		if (voice_pool[i]) {
			voice_pool[i]->process(delta);
		}
	}

	bool any_removed = false;
	for (int i = voice_pool.size() - 1; i >= 0; i--) {
		if (voice_pool[i] && voice_pool[i]->is_ready_for_deletion()) {
			memdelete(voice_pool[i]);
			voice_pool.remove_at(i);
			any_removed = true;
		}
	}

	if (any_removed) {
		emit_signal("finished");
	}
}

void PHASEAudioStreamPlayer3D::phase_physics_process() {
	for (int i = 0; i < voice_pool.size(); i++) {
		if (voice_pool[i] && voice_pool[i]->is_playing()) {
			voice_pool[i]->update_transform();
		}
	}
}

void PHASEAudioStreamPlayer3D::stop_active_voices() {
	for (int i = 0; i < voice_pool.size(); i++) {
		if (voice_pool[i] && voice_pool[i]->is_playing()) {
			voice_pool[i]->stop();
		}
	}
}

void PHASEAudioStreamPlayer3D::set_mixer_type(MixerType p_mixer_type) {
	mixer_type = p_mixer_type;
}

PHASEAudioStreamPlayer3D::MixerType PHASEAudioStreamPlayer3D::get_mixer_type() const {
	return mixer_type;
}

void PHASEAudioStreamPlayer3D::set_stream(Ref<AudioStream> p_stream) {
	stop();
	stream = p_stream;
}

Ref<AudioStream> PHASEAudioStreamPlayer3D::get_stream() const {
	return stream;
}

void PHASEAudioStreamPlayer3D::seek(float p_seconds) {
	for (int i = 0; i < voice_pool.size(); i++) {
		if (voice_pool[i] && voice_pool[i]->is_playing()) {
			voice_pool[i]->seek(p_seconds);
		}
	}
}

void PHASEAudioStreamPlayer3D::set_playing(bool p_enable) {
	if (p_enable) {
		play(0.0);
	} else {
		stop();
	}
}

bool PHASEAudioStreamPlayer3D::is_playing() const {
	for (int i = 0; i < voice_pool.size(); i++) {
		if (voice_pool[i] && voice_pool[i]->is_playing()) {
			return true;
		}
	}
	return false;
}

float PHASEAudioStreamPlayer3D::get_playback_position() {
	if (!voice_pool.is_empty()) {
		return voice_pool[voice_pool.size() - 1]->get_playback_position();
	}
	return 0.0f;
}

void PHASEAudioStreamPlayer3D::set_volume_db(float p_volume) {
	volume_db = p_volume;

	for (int i = 0; i < voice_pool.size(); i++) {
		if (voice_pool[i]) {
			voice_pool[i]->set_volume_db(p_volume);
		}
	}
}

float PHASEAudioStreamPlayer3D::get_volume_db() const {
	return volume_db;
}

void PHASEAudioStreamPlayer3D::set_volume_linear(float p_volume) {
	set_volume_db((float)UtilityFunctions::linear_to_db(p_volume));
}

float PHASEAudioStreamPlayer3D::get_volume_linear() const {
	return (float)UtilityFunctions::db_to_linear(volume_db);
}

void PHASEAudioStreamPlayer3D::set_pitch_scale(float p_pitch_scale) {
	pitch_scale = p_pitch_scale;

	for (int i = 0; i < voice_pool.size(); i++) {
		if (voice_pool[i]) {
			voice_pool[i]->set_pitch_scale(p_pitch_scale);
		}
	}
}

float PHASEAudioStreamPlayer3D::get_pitch_scale() const {
	return pitch_scale;
}

void PHASEAudioStreamPlayer3D::set_autoplay(bool p_enable) {
	autoplay = p_enable;
}

bool PHASEAudioStreamPlayer3D::is_autoplay_enabled() const {
	return autoplay;
}

void PHASEAudioStreamPlayer3D::set_stream_paused(bool p_pause) {
	stream_paused = p_pause;
}

bool PHASEAudioStreamPlayer3D::get_stream_paused() const {
	return stream_paused;
}

bool PHASEAudioStreamPlayer3D::has_stream_playback() {
	for (int i = 0; i < voice_pool.size(); i++) {
		if (voice_pool[i] && voice_pool[i]->is_playing()) {
			return true;
		}
	}
	return false;
}

Ref<AudioStreamPlayback> PHASEAudioStreamPlayer3D::get_stream_playback() {
	// Return the most recent active playback, matching Godot's behavior
	for (int i = voice_pool.size() - 1; i >= 0; i--) {
		if (voice_pool[i] && voice_pool[i]->is_playing()) {
			return voice_pool[i]->get_stream_playback();
		}
	}
	ERR_FAIL_V_MSG(Ref<AudioStreamPlayback>(), "Player is inactive. Call play() before requesting get_stream_playback().");
}

void PHASEAudioStreamPlayer3D::set_max_polyphony(int p_max_polyphony) {
	if (p_max_polyphony > 0) {
		max_polyphony = p_max_polyphony;
	}
}

int PHASEAudioStreamPlayer3D::get_max_polyphony() const {
	return max_polyphony;
}

void PHASEAudioStreamPlayer3D::set_enable_direct_path(bool p_enable) {
	enable_direct_path = p_enable;
}

bool PHASEAudioStreamPlayer3D::get_enable_direct_path() const {
	return enable_direct_path;
}

void PHASEAudioStreamPlayer3D::set_enable_early_reflections(bool p_enable) {
	enable_early_reflections = p_enable;
}

bool PHASEAudioStreamPlayer3D::get_enable_early_reflections() const {
	return enable_early_reflections;
}

void PHASEAudioStreamPlayer3D::set_enable_late_reverb(bool p_enable) {
	enable_late_reverb = p_enable;
}

bool PHASEAudioStreamPlayer3D::get_enable_late_reverb() const {
	return enable_late_reverb;
}

void PHASEAudioStreamPlayer3D::set_cull_distance(double p_distance) {
	cull_distance = p_distance;
}

double PHASEAudioStreamPlayer3D::get_cull_distance() const {
	return cull_distance;
}

void PHASEAudioStreamPlayer3D::set_rolloff_factor(float p_factor) {
	rolloff_factor = p_factor;
}

float PHASEAudioStreamPlayer3D::get_rolloff_factor() const {
	return rolloff_factor;
}

void PHASEAudioStreamPlayer3D::set_mixer_send_parameter(const char* param_suffix, double value, double& stored_value) {
	stored_value = value;

	// Only apply send levels to spatial mixers
	if (mixer_type != MIXER_SPATIAL) {
		return;
	}

	for (int i = 0; i < voice_pool.size(); i++) {
		if (voice_pool[i] && voice_pool[i]->is_playing()) {
			PHASEEngineWrapper* engine_wrapper = [PHASEEngineWrapper sharedInstance];
			NSString* mixer_name = [NSString stringWithFormat:@"AudioStreamMixer_%lld", voice_pool[i]->get_phase_source_id()];
			NSString* param_name = [mixer_name stringByAppendingString:@(param_suffix)];
			BOOL success = [engine_wrapper setMetaParameterWithId:voice_pool[i]->get_phase_sound_event_id() parameterName:param_name doubleValue:value];
			if (!success) {
				ERR_PRINT(String("Failed to set metaParameter '") + String([param_name UTF8String]) +
				         String("' on sound event ID: ") + String::num_int64(voice_pool[i]->get_phase_sound_event_id()));
			}
		}
	}
}

double PHASEAudioStreamPlayer3D::get_mixer_send_parameter(const char* param_suffix, const double& stored_value) const {
	return stored_value;
}

void PHASEAudioStreamPlayer3D::set_direct_path_send(double p_send_level) {
	set_mixer_send_parameter("DirectPathSend", p_send_level, direct_path_send);
}

double PHASEAudioStreamPlayer3D::get_direct_path_send() const {
	return get_mixer_send_parameter("DirectPathSend", direct_path_send);
}

void PHASEAudioStreamPlayer3D::set_early_reflections_send(double p_send_level) {
	set_mixer_send_parameter("EarlyReflectionsSend", p_send_level, early_reflections_send);
}

double PHASEAudioStreamPlayer3D::get_early_reflections_send() const {
	return get_mixer_send_parameter("EarlyReflectionsSend", early_reflections_send);
}

void PHASEAudioStreamPlayer3D::set_late_reverb_send(double p_send_level) {
	set_mixer_send_parameter("LateReverbSend", p_send_level, late_reverb_send);
}

double PHASEAudioStreamPlayer3D::get_late_reverb_send() const {
	return get_mixer_send_parameter("LateReverbSend", late_reverb_send);
}

void PHASEAudioStreamPlayer3D::play(float p_from_pos) {
	if (stream.is_null()) {
		ERR_PRINT("No AudioStream set");
		return;
	}

	if (stream_paused && is_playing()) {
		stream_paused = false;
		return;
	}

	stream_paused = false;

	PHASEAudioStreamPlayer3DInternal* voice = memnew(PHASEAudioStreamPlayer3DInternal(this));
	voice_pool.push_back(voice);

	if (!voice->play(stream, p_from_pos, pitch_scale)) {
		ERR_PRINT("Failed to start playback");
		voice_pool.remove_at(voice_pool.size() - 1);
		memdelete(voice);
		return;
	}

	voice->set_volume_db(volume_db);
	ensure_playback_limit();
}

void PHASEAudioStreamPlayer3D::stop() {
	stream_paused = false;
	for (int i = 0; i < voice_pool.size(); i++) {
		if (voice_pool[i]) {
			voice_pool[i]->stop();
		}
	}
}

void PHASEAudioStreamPlayer3D::ensure_playback_limit() {
	int active_count = 0;
	for (int i = 0; i < voice_pool.size(); i++) {
		if (voice_pool[i] && voice_pool[i]->is_playing()) {
			active_count++;
		}
	}

	if (active_count > max_polyphony) {
		int to_stop = active_count - max_polyphony;
		for (int i = 0; i < voice_pool.size() && to_stop > 0; i++) {
			if (voice_pool[i] && voice_pool[i]->is_playing()) {
				voice_pool[i]->stop();
				to_stop--;
			}
		}
	}
}

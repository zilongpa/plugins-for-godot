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
#include <algorithm>
#include <array>
#include <cmath>
#include <map>
#include <string>

namespace gdrk {
// One request per window/hand; all durations use a caller-supplied monotonic clock.
class WindowHapticMixer {
    struct Request { double amplitude, frequency, start, end; bool left; };
    std::map<std::string, Request> requests;
public:
    struct Output { double amplitude = 0.0, frequency = 0.0; };
    void clear() { requests.clear(); }
	void remove(const std::string &source) { requests.erase(source); }
	void remove_hand(bool left) {
		for (auto it = requests.begin(); it != requests.end();) {
			if (it->second.left == left) {
				it = requests.erase(it);
			} else {
				++it;
			}
		}
	}
	void submit(const std::string &source, bool left, double amplitude, double frequency,
			double duration, double delay, double now) {
		if (!std::isfinite(amplitude) || !std::isfinite(frequency) || !std::isfinite(duration) || !std::isfinite(delay) || amplitude <= 0.0) {
			requests.erase(source);
			return;
		}
		const double start = now + std::max(0.0, delay);
		requests[source] = { std::clamp(amplitude, 0.0, 1.0), frequency, start,
			start + std::clamp(duration > 0.0 ? duration : 0.03, 0.001, 30.0), left };
	}
	template <typename IsTracked>
	std::array<Output, 2> evaluate(double now, IsTracked is_tracked) {
		std::array<Output, 2> outputs = {};
        for (auto it = requests.begin(); it != requests.end();) {
            const auto &r = it->second;
            if (now >= r.end || !is_tracked(it->first)) { it = requests.erase(it); continue; }
            auto &output = outputs[r.left ? 0 : 1];
            if (now >= r.start && r.amplitude > output.amplitude) {
                output = {r.amplitude, r.frequency};
            }
            ++it;
        }
        return outputs;
	}
};
}

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

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace gdrk {
template <size_t N>
struct StringLiteral {
	constexpr StringLiteral(const char (&str)[N]) {
		std::copy_n(str, N, value);
	}

	char value[N];
};

template <typename NodeLoader>
class NoopBase {
protected:
	typedef void (NodeLoader::*SignalHandler)(uint32_t);

public:
	void initialize(NodeLoader *, SignalHandler) {}
	inline void resize(uint32_t p_capacity) {}
};

struct CallableEntry {
	godot::Node *source;
	godot::Callable callable;
};

template <StringLiteral signal, typename NodeLoader>
class SignalCollectorBase : public godot::LocalVector<CallableEntry> {
protected:
	typedef void (NodeLoader::*SignalHandler)(uint32_t);
	using ThisClass = SignalCollectorBase<signal, NodeLoader>;

	inline static godot::String &signal_name() {
		static godot::String sn = godot::String(signal.value);
		return sn;
	}

	// One godot:Object to dispatch them all.
	class SignalDispatcher : public godot::Object {
	public:
		void initialize(ThisClass *p_forwarder) {
			forwarder = p_forwarder;
			base_callable = callable_mp(this, &SignalDispatcher::_signal_callback);
		}

	public:
		// Creating the base callable object which will be used to bind different indices
		godot::Callable base_callable;

	private:
		ThisClass *forwarder;
		void _signal_callback(uint32_t p_idx) {
			forwarder->_forward_signal(p_idx);
		}
	};

public:
	SignalCollectorBase() = default;
	void initialize(NodeLoader *p_loader, SignalHandler p_handler) {
		handler = p_handler;
		loader = p_loader;
		dispatcher = memnew(SignalDispatcher);
		dispatcher->initialize(this);
	}

	~SignalCollectorBase() {
		if (dispatcher) {
			memfree(dispatcher);
		}
	}

private:
	friend class SignalDispatcher;

	void _forward_signal(uint32_t p_idx) {
		(loader->*handler)(p_idx);
	}

protected:
	SignalDispatcher *dispatcher = nullptr;
	SignalHandler handler = nullptr;
	NodeLoader *loader = nullptr;
};

// SignalCollector is a container holds a connector for each node when
// connect(..) is called. The goal is to provide a single function on
// NodeLoaders to process signals for each individual nodes
// The NodeLoader should hold a NodeType (Sprite3D, DirectionalLight, etc...) determines
// if the Collector does anything, based on the `BaseTypeCondition` type. This allows integration
// of the SignalCollector on NodeLoader base classes and prevent unecessary computation in case
// the managed node type doesn't inherit from the condition
template <StringLiteral signal, typename NodeLoader, typename BaseTypeCondition = godot::Object>
class SignalCollector : public std::conditional_t<std::is_base_of<BaseTypeCondition, typename NodeLoader::NodeType>::value, SignalCollectorBase<signal, NodeLoader>, NoopBase<NodeLoader>> {
	using ThisClass = SignalCollector<signal, NodeLoader, BaseTypeCondition>;
	using Base = std::conditional_t<std::is_base_of<BaseTypeCondition, typename NodeLoader::NodeType>::value, SignalCollectorBase<signal, NodeLoader>, NoopBase<NodeLoader>>;

public:
	inline void connect(NodeLoader::NodeType *p_node, uint32_t p_idx) {
		if constexpr (std::is_base_of<BaseTypeCondition, typename NodeLoader::NodeType>::value) {
			CallableEntry &entry = (*this)[p_idx];
			entry.callable = this->dispatcher->base_callable.bind(p_idx);
			entry.source = p_node;
			p_node->connect(Base::signal_name(), entry.callable);
		}
	}

	inline void disconnect(uint32_t p_idx) {
		if constexpr (std::is_base_of<BaseTypeCondition, typename NodeLoader::NodeType>::value) {
			CallableEntry &entry = (*this)[p_idx];
			if (entry.source) {
				entry.source->disconnect(Base::signal_name(), entry.callable);
				entry.source = nullptr;
			}
		}
	}

private:
};
} //namespace gdrk

#define DECLARE_SIGNAL_COLLECTOR(Name, signal, LoaderClass, BaseTypeCondition) \
	using Name##Collector = gdrk::SignalCollector<signal, LoaderClass, BaseTypeCondition>

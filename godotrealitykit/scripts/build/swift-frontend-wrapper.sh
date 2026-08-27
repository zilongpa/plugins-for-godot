#! /bin/bash

#===----------------------------------------------------------------------===#
# Copyright © 2026 Apple Inc.
#
# Licensed under the MIT license (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# LICENSE
#
#===----------------------------------------------------------------------===#


# Newer Xcode toolchains ship swift-frontend without the compiler-plugin
# search paths that the swiftc driver normally injects automatically, so
# SwiftUI macros (@State, @Observable, ...) fail with "plugin ... not found"
# when godot's SCons build invokes swift-frontend directly (see
# platform_methods.py's setup_swift_builder). Point SCons at this wrapper via
# SWIFT_FRONTEND to add the missing -plugin-path flags derived from the SDK
# passed on the command line.

set -e

TOOLCHAIN_PATH="${APPLE_TOOLCHAIN_PATH:-"$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"}"

sdk_path=""
prev_arg=""
for arg in "$@"; do
    if [ "$prev_arg" = "-sdk" ]; then
        sdk_path="$arg"
    fi
    prev_arg="$arg"
done

plugin_args=()
if [ -n "$sdk_path" ]; then
    platform_dev_root="$(cd "$sdk_path/../.." && pwd)"
    for subdir in usr/lib/swift/host/plugins usr/local/lib/swift/host/plugins; do
        plugin_path="$platform_dev_root/$subdir"
        if [ -d "$plugin_path" ]; then
            plugin_args+=(-plugin-path "$plugin_path")
        fi
    done
fi

exec "$TOOLCHAIN_PATH/usr/bin/swift-frontend" "$@" "${plugin_args[@]}"

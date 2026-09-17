#!/bin/bash

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

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(realpath "$SCRIPT_DIR/../../")"

cd "$REPO_DIR/GodotRealityKit"

airFiles=()

# The library must target the same platform as the framework consuming it.
case "${PLATFORM_NAME:-macosx}" in
    xrsimulator) metal_sdk=xrsimulator; metal_target=air64-apple-xros26.0-simulator ;;
    xros) metal_sdk=xros; metal_target=air64-apple-xros26.0 ;;
    macosx) metal_sdk=macosx; metal_target=air64-apple-macos15.0 ;;
    *) echo "Unsupported Metal platform: $PLATFORM_NAME" >&2; exit 1 ;;
esac

mkdir -p "$METAL_LIBRARY_OUTPUT_DIR"

for metalFile in "$REPO_DIR/GodotRealityKit/Metal/"*.metal ; do
    f="$(basename "$metalFile")"
    airFile="$BUILT_PRODUCTS_DIR/${f%.metal}.air"
    airFiles+=("$airFile")

    xcrun -sdk "$metal_sdk" metal \
          -c "$metalFile" \
          -o "$airFile" \
          -std=metal3.0 \
          -target "$metal_target"
done

xcrun -sdk "$metal_sdk" metallib \
            "${airFiles[@]}" \
            -o "$METAL_LIBRARY_OUTPUT_DIR/default.metallib"

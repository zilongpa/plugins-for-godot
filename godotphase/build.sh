#!/bin/bash
# Copyright © 2026 Apple Inc.

set -e  # Exit on error

show_help() {
    cat << EOF
PHASE GDExtension Build Script

USAGE:
    $0 [OPTIONS] [PLATFORM] [ARCH]

BUILD TARGETS:
    --debug              Build debug version (template_debug, with debug symbols)
    --release            Build release version (template_release, optimized, default)
    --both               Build both debug and release versions

PLATFORMS:
    macos               macOS (default)
    ios                 iOS
    tvos                tvOS
    visionos            visionOS
    all                 All platforms (builds both debug + release)

PLATFORM OPTIONS:
    --simulator         Build for iOS simulator

BUILD OPTIONS:
    --debug-symbols     Force debug symbols in release builds
    --rebuild-godot-cpp Force rebuild of godot-cpp
    --arch ARCH         Target architecture (arm64, x86_64, universal)

SPECIAL COMMANDS:
    clean               Remove all build artifacts
    help                Show this help

EXAMPLES:
    $0                          # macOS release (default)
    $0 --debug                  # macOS debug
    $0 --both                   # macOS debug + release
    $0 all                      # All platforms, debug + release
    $0 all --debug              # All platforms, debug only
    $0 all --release            # All platforms, release only
    $0 ios --simulator          # iOS simulator, release
    $0 --debug ios --simulator  # iOS simulator, debug

EOF
}

XCODE_DEV_PATH=$(xcode-select -p)
XCODE_PATH="${XCODE_DEV_PATH%/Contents/Developer}"

if [ ! -d "$XCODE_PATH" ]; then
    echo "❌ Error: Xcode not found at $XCODE_PATH"
    echo "   Please install Xcode or run 'sudo xcode-select --switch /path/to/Xcode.app'"
    exit 1
fi

if ! command -v scons &> /dev/null; then
    echo "❌ Error: scons not found"
    echo "   Install with: brew install scons"
    exit 1
fi

if [ ! -f "godot-cpp/SConstruct" ]; then
    echo "❌ Error: godot-cpp submodule not initialized"
    echo "   Run: git submodule init && git submodule update"
    exit 1
fi

TARGET_TYPE="release"
ARCH="arm64"
DEBUG_SYMBOLS=""
REBUILD_GODOT_CPP=""
SIMULATOR=""
BUILD_BOTH=false
EXPLICIT_TARGET=false
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            TARGET_TYPE="debug"
            EXPLICIT_TARGET=true
            shift
            ;;
        --release)
            TARGET_TYPE="release"
            EXPLICIT_TARGET=true
            shift
            ;;
        --both)
            BUILD_BOTH=true
            EXPLICIT_TARGET=true
            shift
            ;;
        --debug-symbols)
            DEBUG_SYMBOLS="debug_symbols=yes"
            shift
            ;;
        --simulator)
            SIMULATOR="simulator"
            shift
            ;;
        --rebuild-godot-cpp)
            REBUILD_GODOT_CPP="rebuild_godot_cpp=yes"
            echo "🧹 Cleaning godot-cpp build artifacts..."
            rm -rf godot-cpp/bin/*.a godot-cpp/gen/
            shift
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        clean|all|help)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
        -h|--help)
            POSITIONAL_ARGS+=("help")
            shift
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]}"

case "${1:-}" in
    help)
        show_help
        exit 0
        ;;
    clean)
        echo "🧹 Cleaning build artifacts..."
        scons --clean 2>/dev/null || true
        rm -rf demo/bin/*.framework demo/bin/*.a demo/bin/.sconsign.dblite
        rm -rf demo/bin/libphasegodot_temp.*
        rm -rf demo/bin/libphasewrapper.*
        rm -rf build
        echo "✅ Clean complete"
        exit 0
        ;;
esac

build_target() {
    local platform=$1
    local target=$2
    local arch=$3
    local extra_flags=$4

    local target_name="template_${target}"
    local sim_suffix=""
    local sim_flag=""

    # Handle simulator builds
    if [ "$SIMULATOR" == "simulator" ]; then
        case $platform in
            ios)
                sim_flag="${platform}_simulator=yes"
                sim_suffix=".simulator"
                ;;
            macos|tvos|visionos)
                echo "❌ Error: --simulator is not supported for $platform"
                exit 1
                ;;
        esac
    fi

    echo "🔨 Building $platform ($target_name$sim_suffix, $arch)..."

    # Build command
    local -a cmd=(scons "platform=$platform" "arch=$arch" "target=$target_name" $extra_flags $sim_flag)

    if ! "${cmd[@]}"; then
        echo "❌ Build failed for $platform $target_name$sim_suffix"
        return 1
    fi

    # Validate output files were created
    validate_build_output "$platform" "$target_name" "$sim_suffix" "$arch"
}

validate_build_output() {
    local platform=$1
    local target=$2
    local sim_suffix=$3
    local arch=$4

    case $platform in
        macos)
            local expected="demo/bin/libphasegodot.${platform}.${target}.framework/libphasegodot.${platform}.${target}"
            ;;
        *)
            local expected="demo/bin/libphasegodot.${platform}.${target}${sim_suffix}.a"
            ;;
    esac

    if [ ! -f "$expected" ]; then
        echo "❌ Expected output file not found: $expected"
        return 1
    else
        echo "✅ Created: $expected"
    fi
}

if [ "$1" == "all" ]; then
    if [ "$SIMULATOR" == "simulator" ]; then
        platforms=("ios")
    else
        platforms=("macos" "ios" "visionos" "tvos")
    fi

    # When building all platforms without an explicit target flag, default to both debug and release
    if [ "$EXPLICIT_TARGET" = false ]; then
        BUILD_BOTH=true
    fi

    echo "🚀 Building all platforms..."

    if [ "$BUILD_BOTH" == true ]; then
        echo "   Targets: debug + release"
        for platform in "${platforms[@]}"; do
            echo ""
            echo "=== Building $platform ==="
            build_target "$platform" "debug" "$ARCH" "$DEBUG_SYMBOLS $REBUILD_GODOT_CPP"
            build_target "$platform" "release" "$ARCH" "$DEBUG_SYMBOLS $REBUILD_GODOT_CPP"
        done
    else
        echo "   Target: $TARGET_TYPE"
        for platform in "${platforms[@]}"; do
            echo ""
            echo "=== Building $platform ==="
            build_target "$platform" "$TARGET_TYPE" "$ARCH" "$DEBUG_SYMBOLS $REBUILD_GODOT_CPP"
        done
    fi

    echo ""
    echo "✅ Build all complete"

else
    PLATFORM="${1:-macos}"

    case $PLATFORM in
        macos|ios|tvos|visionos) ;;
        *)
            echo "❌ Error: Unknown platform '$PLATFORM'"
            echo "   Supported platforms: macos, ios, tvos, visionos"
            echo "   Use '$0 help' for usage information"
            exit 1
            ;;
    esac

    if [ "$BUILD_BOTH" == true ]; then
        echo "🚀 Building $PLATFORM (debug + release)..."
        build_target "$PLATFORM" "debug" "$ARCH" "$DEBUG_SYMBOLS $REBUILD_GODOT_CPP"
        build_target "$PLATFORM" "release" "$ARCH" "$DEBUG_SYMBOLS $REBUILD_GODOT_CPP"
        echo ""
        echo "✅ Build complete for $PLATFORM (both targets)"
    else
        echo "🚀 Building $PLATFORM ($TARGET_TYPE)..."
        build_target "$PLATFORM" "$TARGET_TYPE" "$ARCH" "$DEBUG_SYMBOLS $REBUILD_GODOT_CPP"
        echo ""
        echo "✅ Build complete for $PLATFORM ($TARGET_TYPE)"
    fi
fi

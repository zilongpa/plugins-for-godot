# Copyright © 2026 Apple Inc.

@tool
extends EditorExportPlugin

## EditorExportPlugin for PHASE framework dependencies
##
## Adds required Apple frameworks to generated Xcode projects:
## - PHASE.framework (Spatial audio engine)
## - ModelIO.framework (Required by PHASE)
## - Accelerate.framework (Required by PHASE)
## - AVFoundation.framework (Audio foundation)

const REQUIRED_FRAMEWORKS = [
	"PHASE.framework",
	"ModelIO.framework",
	"Accelerate.framework",
	"AVFoundation.framework"
]

func _get_name() -> String:
	return "PHASEFrameworks"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	var platform_name = platform.get_os_name()
	return platform_name in ["iOS", "visionOS", "macOS"]

func _is_ios_platform(features: PackedStringArray) -> bool:
	return "iOS" in features or "ios" in features

func _is_visionos_platform(features: PackedStringArray) -> bool:
	return "visionOS" in features or "visionos" in features

func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	if _is_ios_platform(features):
		print("PHASE Export: Adding iOS frameworks")
		for framework in REQUIRED_FRAMEWORKS:
			add_ios_framework(framework)
	elif _is_visionos_platform(features):
		print("PHASE Export: Adding visionOS frameworks")
		for framework in REQUIRED_FRAMEWORKS:
			add_apple_embedded_platform_framework(framework)

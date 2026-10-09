extends RefCounted
## Presentation data supplied by the caller. Positions use the caller's units.

var available := false
var playing := false
var position := 0.0
var maximum := 0.0
var step := 1.0
var label := ""
var speed := 1.0
var can_smooth := false
var smooth := false

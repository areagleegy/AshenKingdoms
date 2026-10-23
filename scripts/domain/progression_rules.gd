extends RefCounted
## Pure progression rules shared by offline and network gameplay.
##
## This module deliberately has no dependency on nodes, scenes, save files, or
## multiplayer state. Keep its output deterministic for a given level.

const BASE_XP_REQUIRED: int = 100
const XP_STEP_PER_LEVEL: int = 50


static func required_xp_for_level(level: int) -> int:
	return BASE_XP_REQUIRED + ((level - 1) * XP_STEP_PER_LEVEL)

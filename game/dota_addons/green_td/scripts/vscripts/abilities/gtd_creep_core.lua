-- Ability scripts are loaded by the client too, so linking here makes the modifiers known on both sides.
LinkLuaModifier("modifier_gtd_creep", "modifiers/modifier_gtd_creep", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gtd_poison", "modifiers/modifier_gtd_poison", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gtd_frost", "modifiers/modifier_gtd_frost", LUA_MODIFIER_MOTION_NONE)

-- Hidden ability on every creep: owner of modifier_gtd_creep.
gtd_creep_core = class({})

function gtd_creep_core:IsStealable()
	return false
end

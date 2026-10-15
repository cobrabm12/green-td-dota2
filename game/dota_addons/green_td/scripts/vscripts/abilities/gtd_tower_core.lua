-- Ability scripts are loaded by the client too, so linking here makes the modifiers known on both sides.
LinkLuaModifier("modifier_gtd_tower", "modifiers/modifier_gtd_tower", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gtd_poison", "modifiers/modifier_gtd_poison", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gtd_frost", "modifiers/modifier_gtd_frost", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gtd_fire_trap", "modifiers/modifier_gtd_fire_trap", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gtd_constructing", "modifiers/modifier_gtd_constructing", LUA_MODIFIER_MOTION_NONE)

-- Hidden ability on every tower: owner of the tower's modifiers and of bounce projectiles.
gtd_tower_core = class({})

function gtd_tower_core:IsStealable()
	return false
end

function gtd_tower_core:OnProjectileHit_ExtraData(target, location, extra)
	if not IsServer() or not extra then
		return true
	end
	if extra.attack then
		local tower = self:GetCaster()
		if tower and IsValidEntity(tower) and tower.gtd and target then
			GTD.Combat:OnAttackLanded(tower, target)
		end
	elseif extra.chain then
		GTD.Combat:OnBounceHit(target, extra.chain)
	end
	return true
end

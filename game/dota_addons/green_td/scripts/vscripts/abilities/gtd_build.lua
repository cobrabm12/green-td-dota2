-- Ability scripts are loaded by the client too, so linking here makes the modifiers known on both sides.
LinkLuaModifier("modifier_gtd_builder", "modifiers/modifier_gtd_builder", LUA_MODIFIER_MOTION_NONE)

-- Builder ability: the Panorama build menu picks the tower (gtd_build_select) and then starts this
-- ability's ground targeting. Like the WC3 Shade, the builder walks to the spot before building.
gtd_build = class({})

function gtd_build:GetAOERadius()
	return 64
end

function gtd_build:OnSpellStart()
	if IsServer() then
		GTD.Towers:TryBuild(self:GetCaster(), self:GetCursorPosition())
	end
end

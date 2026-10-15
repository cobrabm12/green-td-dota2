-- Fire Trap (WC3 Permanent Immolation, ANpi): damage per second to ground creeps around the trap.
-- Spell damage: ignores armor, does nothing to immune creeps.
modifier_gtd_fire_trap = class({})

function modifier_gtd_fire_trap:IsHidden() return true end
function modifier_gtd_fire_trap:IsPurgable() return false end

function modifier_gtd_fire_trap:GetEffectName()
	return "particles/items2_fx/radiance_owner.vpcf"
end

function modifier_gtd_fire_trap:GetEffectAttachType()
	return PATTACH_ABSORIGIN_FOLLOW
end

function modifier_gtd_fire_trap:OnCreated()
	if IsServer() then
		self:StartIntervalThink(1)
	end
end

function modifier_gtd_fire_trap:OnIntervalThink()
	local trap = self:GetParent()
	local g = trap.gtd
	if not g or not g.def.immolation or trap:HasModifier("modifier_gtd_constructing") then
		return
	end
	local im = g.def.immolation
	local units = FindUnitsInRadius(trap:GetTeamNumber(), trap:GetAbsOrigin(), nil, im.radius,
		DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_HERO,
		DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_ANY_ORDER, false)
	for _, u in ipairs(units) do
		if GTD.Combat:IsCreep(u) then
			local air = u.gtd.def.air
			if (air and im.air) or (not air and im.ground) then
				GTD.Combat:Damage(trap, u, im.dps, "spells", true)
			end
		end
	end
end

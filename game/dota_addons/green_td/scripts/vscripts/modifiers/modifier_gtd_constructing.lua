-- Tower under construction / being upgraded (WC3 build time): no attacks, no auras.
modifier_gtd_constructing = class({})

function modifier_gtd_constructing:IsHidden() return false end
function modifier_gtd_constructing:IsPurgable() return false end

function modifier_gtd_constructing:GetTexture()
	return "rattletrap_power_cogs"
end

function modifier_gtd_constructing:CheckState()
	return { [MODIFIER_STATE_DISARMED] = true }
end

function modifier_gtd_constructing:GetStatusEffectName()
	return "particles/status_fx/status_effect_ghost.vpcf"
end

function modifier_gtd_constructing:OnDestroy()
	if IsServer() then
		GTD.Auras:TowersChanged()
	end
end

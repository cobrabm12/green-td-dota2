-- WC3 Frost Attack (Afra / Afr2): movement slowed by FrostMoveSpeedDecrease (50%). Non-immune creeps only.
modifier_gtd_frost = class({})

function modifier_gtd_frost:IsDebuff() return true end
function modifier_gtd_frost:IsPurgable() return true end

function modifier_gtd_frost:GetEffectName()
	return "particles/generic_gameplay/generic_slowed_cold.vpcf"
end

function modifier_gtd_frost:GetEffectAttachType()
	return PATTACH_ABSORIGIN_FOLLOW
end

function modifier_gtd_frost:GetStatusEffectName()
	return "particles/status_fx/status_effect_frost.vpcf"
end

function modifier_gtd_frost:OnCreated(kv)
	if IsServer() then
		self.slow = kv.slow or 0.5
	end
end

function modifier_gtd_frost:OnRefresh(kv)
	if IsServer() then
		self.slow = math.max(self.slow or 0, kv.slow or 0.5)
	end
end

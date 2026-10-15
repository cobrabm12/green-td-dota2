-- WC3 Slow Poison (Aspo): damage per second and movement slow. Organic, non-immune creeps only.
modifier_gtd_poison = class({})

function modifier_gtd_poison:IsDebuff() return true end
function modifier_gtd_poison:IsPurgable() return true end

function modifier_gtd_poison:GetEffectName()
	return "particles/units/heroes/hero_venomancer/venomancer_gale_poison_debuff.vpcf"
end

function modifier_gtd_poison:GetEffectAttachType()
	return PATTACH_ABSORIGIN_FOLLOW
end

function modifier_gtd_poison:OnCreated(kv)
	if IsServer() then
		self.dps = kv.dps or 0
		self.slow = kv.slow or 0
		self:StartIntervalThink(1)
	end
end

function modifier_gtd_poison:OnRefresh(kv)
	if IsServer() then
		self.dps = math.max(self.dps or 0, kv.dps or 0)
		self.slow = math.max(self.slow or 0, kv.slow or 0)
	end
end

function modifier_gtd_poison:OnIntervalThink()
	local tower = self:GetCaster()
	if tower and IsValidEntity(tower) and tower.gtd and self.dps > 0 then
		GTD.Combat:Damage(tower, self:GetParent(), self.dps, "spells", true)
	end
end

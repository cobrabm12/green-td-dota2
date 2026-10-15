-- Every tower: target acquisition (air/ground rules of the WC3 unit), WC3 attack rate with speed auras,
-- and hand-off of every landed attack to GTD.Combat (native attack damage is cancelled in GTD:DamageFilter).
modifier_gtd_tower = class({})

local THINK = 0.15
local MAX_ATTACK_SPEED_MULT = 7   -- Dota attack speed cap (700)

function modifier_gtd_tower:IsHidden() return true end
function modifier_gtd_tower:IsPurgable() return false end
function modifier_gtd_tower:RemoveOnDeath() return false end

function modifier_gtd_tower:CheckState()
	return {
		[MODIFIER_STATE_INVULNERABLE] = true,
		[MODIFIER_STATE_NO_HEALTH_BAR] = true,
		[MODIFIER_STATE_NO_UNIT_COLLISION] = true,
		[MODIFIER_STATE_MAGIC_IMMUNE] = true,
	}
end

function modifier_gtd_tower:DeclareFunctions()
	return {
		MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT,
		MODIFIER_PROPERTY_PROCATTACK_FEEDBACK,
	}
end

function modifier_gtd_tower:OnCreated()
	self.asb = 0
	if IsServer() then
		self:SetHasCustomTransmitterData(true)
		self:Recalculate()
		self:StartIntervalThink(THINK)
	end
end

function modifier_gtd_tower:AddCustomTransmitterData()
	return { asb = self.asb }
end

function modifier_gtd_tower:HandleCustomTransmitterData(data)
	self.asb = data.asb or 0
end

-- WC3 interval = cooldown / (1 + speed aura). Dota runs at most one attack per MIN_ATTACK_INTERVAL and
-- at most 7x attack speed; whatever is left over becomes extra damage per attack (same DPS).
function modifier_gtd_tower:Recalculate()
	local parent = self:GetParent()
	local g = parent.gtd
	if not g or not g.def.attack then
		return
	end
	local cooldown = g.def.attack.cooldown
	local speed = (g.aura and g.aura.speed) or 0
	local wc3 = cooldown / (1 + speed)
	local bat = math.max(cooldown, GTD.MIN_ATTACK_INTERVAL)       -- = AttackRate in the unit KV
	local mult = math.min(bat / math.max(wc3, GTD.MIN_ATTACK_INTERVAL), MAX_ATTACK_SPEED_MULT)
	local interval = bat / mult
	self.asb = (mult - 1) * 100
	g.dmg_factor = interval / wc3
	self:SendBuffRefreshToClients()
end

function modifier_gtd_tower:GetModifierAttackSpeedBonus_Constant()
	return self.asb or 0
end

-- The engine attack is instant (melee type); the missile and the damage are handled by GTD.Combat.
function modifier_gtd_tower:GetModifierProcAttack_Feedback(params)
	if IsServer() then
		GTD.Combat:LaunchAttack(self:GetParent(), params.target)
	end
	return 0
end

function modifier_gtd_tower:OnIntervalThink()
	local parent = self:GetParent()
	local g = parent.gtd
	if not g or not g.def.attack or parent:HasModifier("modifier_gtd_constructing") then
		return
	end
	local at = g.def.attack
	local range = parent:Script_GetAttackRange()
	local current = parent:GetAttackTarget()
	if current and GTD.Combat:CanHit(at, current)
		and (current:GetAbsOrigin() - parent:GetAbsOrigin()):Length2D() <= range + 100 then
		return
	end
	local target = GTD.Combat:FindTarget(parent, at, range)
	if target then
		parent:MoveToTargetToAttack(target)
	elseif current then
		parent:Stop()
	end
end

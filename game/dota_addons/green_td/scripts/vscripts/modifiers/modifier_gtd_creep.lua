-- Every creep: WC3 movement speed (auras, slows, 150..522 limits), region pathing, no unit collision.
modifier_gtd_creep = class({})

local THINK = 0.1
local MIN_SPEED = 150   -- MinUnitSpeed (miscgame.txt)
local MAX_SPEED = 522   -- MaxUnitSpeed (war3mapMisc.txt)

function modifier_gtd_creep:IsHidden() return true end
function modifier_gtd_creep:IsPurgable() return false end

function modifier_gtd_creep:CheckState()
	return {
		[MODIFIER_STATE_NO_UNIT_COLLISION] = true,
	}
end

function modifier_gtd_creep:DeclareFunctions()
	return {
		MODIFIER_PROPERTY_MOVESPEED_ABSOLUTE,
		MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT,
	}
end

function modifier_gtd_creep:OnCreated()
	self.speed = self:GetParent():GetBaseMoveSpeed()
	self.regen = 0
	if IsServer() then
		self:SetHasCustomTransmitterData(true)
		self.ticks = 0
		self:StartIntervalThink(THINK)
	end
end

function modifier_gtd_creep:AddCustomTransmitterData()
	return { speed = self.speed, regen = self.regen }
end

function modifier_gtd_creep:HandleCustomTransmitterData(data)
	self.speed = data.speed
	self.regen = data.regen
end

function modifier_gtd_creep:ComputeSpeed()
	local parent = self:GetParent()
	local g = parent.gtd
	local factor = 1 + (g.aura_speed or 0)
	local poison = parent:FindModifierByName("modifier_gtd_poison")
	if poison then
		factor = factor - (poison.slow or 0)
	end
	local frost = parent:FindModifierByName("modifier_gtd_frost")
	if frost then
		factor = factor - (frost.slow or 0)
	end
	return math.min(MAX_SPEED, math.max(MIN_SPEED, g.def.speed * factor))
end

function modifier_gtd_creep:OnIntervalThink()
	local parent = self:GetParent()
	local g = parent.gtd
	if not g then
		return
	end
	local speed = self:ComputeSpeed()
	local regen = g.aura_regen or 0
	if math.abs(speed - (self.speed or 0)) > 0.5 or regen ~= self.regen then
		self.speed = speed
		self.regen = regen
		self:SendBuffRefreshToClients()
	end
	GTD.Creeps:UpdatePath(parent)
	if not parent.gtd then
		return   -- reached END
	end
	self.ticks = self.ticks + 1
	if self.ticks % 5 == 0 and parent:IsIdle() then
		GTD.Creeps:Order(parent)
	end
end

function modifier_gtd_creep:GetModifierMoveSpeed_Absolute()
	return self.speed
end

function modifier_gtd_creep:GetModifierConstantHealthRegen()
	return self.regen or 0
end

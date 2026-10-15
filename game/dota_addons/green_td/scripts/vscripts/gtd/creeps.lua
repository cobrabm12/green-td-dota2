-- Creep spawning, WC3-style region pathing and the END region.
GTD.Creeps = GTD.Creeps or {}
local Creeps = GTD.Creeps
local Util = GTD.Util

local BUCKET = 512

function Creeps:Init()
	self.alive = {}
	self.count = 0
	local map = GTD.Data.map
	self.rects = map.rects
	self.next = map.next
	self.endRegion = map.end_region
	-- Regions that have an "enters region" trigger (path nodes + END), bucketed for fast lookup.
	self.buckets = {}
	local triggers = {}
	for name in pairs(self.next) do
		triggers[name] = true
	end
	triggers[self.endRegion] = true
	for name in pairs(triggers) do
		local r = self.rects[name]
		if r then
			for bx = math.floor(r.min[1] / BUCKET), math.floor(r.max[1] / BUCKET) do
				for by = math.floor(r.min[2] / BUCKET), math.floor(r.max[2] / BUCKET) do
					local key = bx .. ":" .. by
					self.buckets[key] = self.buckets[key] or {}
					table.insert(self.buckets[key], name)
				end
			end
		end
	end
end

function Creeps:RegionAt(pos)
	local list = self.buckets[math.floor(pos.x / BUCKET) .. ":" .. math.floor(pos.y / BUCKET)]
	if not list then
		return nil
	end
	for _, name in ipairs(list) do
		if Util.InRect(pos, self.rects[name]) then
			return name
		end
	end
	return nil
end

function Creeps:Spawn(id, region, handicap)
	local def = GTD.Data.creeps[id]
	local rect = self.rects[region]
	if not def or not rect then
		print("[GTD] bad spawn " .. tostring(id) .. " @ " .. tostring(region))
		return nil
	end
	local pos = Util.Ground(Util.RectCenter(rect))
	local unit = CreateUnitByName(def.unit, pos, false, nil, nil, DOTA_TEAM_BADGUYS)
	if not unit then
		return nil
	end
	local hp = math.max(1, math.floor(def.hp * handicap / 100))
	unit:SetBaseMaxHealth(hp)
	unit:SetMaxHealth(hp)
	unit:SetHealth(hp)
	unit.gtd = {
		creep = true, id = id, def = def, inside = nil, target = nil,
		-- a creep's own auras apply to itself right away; GTD.Auras refreshes them twice per second
		aura_armor = def.devotion and def.devotion.armor or 0,
		aura_speed = (def.unholy and def.unholy.speed or 0) + (def.endurance and def.endurance.speed or 0),
		aura_regen = def.unholy and def.unholy.regen or 0,
	}
	local core = unit:FindAbilityByName("gtd_creep_core")
	if core then
		core:SetLevel(1)
	end
	if not unit:HasModifier("modifier_gtd_creep") then
		unit:AddNewModifier(unit, core, "modifier_gtd_creep", {})
	end
	self.alive[unit:entindex()] = unit
	self.count = self.count + 1
	self:UpdatePath(unit)
	return unit
end

-- WC3 semantics: every "unit enters region" trigger orders the creep to the next region's center.
function Creeps:UpdatePath(unit)
	local g = unit.gtd
	local region = self:RegionAt(unit:GetAbsOrigin())
	if region ~= g.inside then
		g.inside = region
		if region == self.endRegion then
			self:ReachedEnd(unit)
			return
		end
		if region and self.next[region] then
			g.target = self.next[region]
			self:Order(unit)
		end
	end
end

function Creeps:Order(unit)
	local g = unit.gtd
	if g.target and self.rects[g.target] then
		unit:MoveToPosition(Util.RectCenter(self.rects[g.target]))
	end
end

function Creeps:Forget(unit)
	local idx = unit:entindex()
	if self.alive[idx] then
		self.alive[idx] = nil
		self.count = self.count - 1
	end
end

-- Trigger "END": the creep is removed and the team loses a chance.
function Creeps:ReachedEnd(unit)
	self:Forget(unit)
	unit.gtd = nil
	local pos = unit:GetAbsOrigin()
	local fx = ParticleManager:CreateParticle("particles/units/heroes/hero_skeletonking/wraith_king_reincarnate.vpcf", PATTACH_WORLDORIGIN, nil)
	ParticleManager:SetParticleControl(fx, 0, pos)
	ParticleManager:ReleaseParticleIndex(fx)
	unit:AddNoDraw()
	unit:ForceKill(false)
	unit:RemoveSelf()
	GTD.Waves:LoseChance()
end

function Creeps:OnKilled(unit, killer)
	local g = unit.gtd
	if not g or not g.creep then
		return
	end
	self:Forget(unit)
	if killer and killer.gtd and killer.gtd.tower then
		local pid = killer.gtd.pid
		local def = g.def
		local bounty = def.bounty + Util.RollDice(def.bounty_dice, def.bounty_sides)
		if bounty > 0 then
			GTD.Players:AddGold(pid, bounty)
			local player = PlayerResource:GetPlayer(pid)
			if player then
				SendOverheadEventMessage(player, OVERHEAD_ALERT_GOLD, unit, bounty, player)
			end
		end
		GTD.Players:AddKill(pid)
	end
	unit.gtd = nil
end

function Creeps:KillAll()
	for _, unit in pairs(self.alive) do
		if IsValidEntity(unit) then
			unit.gtd = nil
			unit:ForceKill(false)
		end
	end
	self.alive = {}
	self.count = 0
end

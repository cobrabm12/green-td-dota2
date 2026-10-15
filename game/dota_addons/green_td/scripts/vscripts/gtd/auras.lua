-- Tower auras (damage / command / speed) and creep auras (devotion armor, unholy + endurance speed).
-- WC3 rule: the same aura buff does not stack (strongest one applies); different buffs add up.
GTD.Auras = GTD.Auras or {}
local Auras = GTD.Auras

function Auras:Init()
	self.towersDirty = true
end

function Auras:TowersChanged()
	self.towersDirty = true
end

function Auras:Think()
	if self.towersDirty then
		self.towersDirty = false
		self:UpdateTowers()
	end
	self:UpdateCreeps()
end

function Auras:UpdateTowers()
	local sources = {}
	for _, t in pairs(GTD.Towers.all) do
		if IsValidEntity(t) and t.gtd and t.gtd.def.auras and not t:HasModifier("modifier_gtd_constructing") then
			sources[#sources + 1] = t
		end
	end
	for _, t in pairs(GTD.Towers.all) do
		if IsValidEntity(t) and t.gtd then
			local aura = { damage = 0, command = 0, speed = 0 }
			local pos = t:GetAbsOrigin()
			for _, s in ipairs(sources) do
				local d = (s:GetAbsOrigin() - pos):Length2D()
				for _, a in ipairs(s.gtd.def.auras) do
					if d <= a.radius and a.value > (aura[a.kind] or 0) then
						aura[a.kind] = a.value
					end
				end
			end
			t.gtd.aura = aura
			local mod = t:FindModifierByName("modifier_gtd_tower")
			if mod then
				mod:Recalculate()
			end
		end
	end
end

-- Strongest aura value reaching `creep`. Sources are sorted strongest first, and a creep always
-- gets its own aura, so in a wave of identical creeps this stops at the first comparison.
local function Best(creep, sources, key, field)
	local own = creep.gtd.def[key]
	local best = own and own[field] or 0
	local pos
	for _, s in ipairs(sources) do
		local a = s.gtd.def[key]
		if a[field] <= best then
			break
		end
		pos = pos or creep:GetAbsOrigin()
		if (s:GetAbsOrigin() - pos):Length2D() <= a.radius then
			return a[field]
		end
	end
	return best
end

local function Collect(key, field)
	local list = {}
	for _, c in pairs(GTD.Creeps.alive) do
		if IsValidEntity(c) and c.gtd and c.gtd.def[key] then
			list[#list + 1] = c
		end
	end
	table.sort(list, function(a, b) return a.gtd.def[key][field] > b.gtd.def[key][field] end)
	return list
end

function Auras:UpdateCreeps()
	local devotion = Collect("devotion", "armor")
	local unholy = Collect("unholy", "speed")
	local endurance = Collect("endurance", "speed")
	if #devotion == 0 and #unholy == 0 and #endurance == 0 then
		return
	end
	for _, c in pairs(GTD.Creeps.alive) do
		if IsValidEntity(c) and c.gtd then
			local g = c.gtd
			g.aura_armor = Best(c, devotion, "devotion", "armor")
			g.aura_speed = Best(c, unholy, "unholy", "speed") + Best(c, endurance, "endurance", "speed")
			g.aura_regen = Best(c, unholy, "unholy", "regen")
		end
	end
end

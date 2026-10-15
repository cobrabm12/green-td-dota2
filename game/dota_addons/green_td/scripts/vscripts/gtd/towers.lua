-- Building, upgrading and selling towers.
GTD.Towers = GTD.Towers or {}
local Towers = GTD.Towers
local Grid = GTD.Grid
local Players = GTD.Players

function Towers:Init()
	self.list = GTD.Data.towers.list
	self.roots = {}
	for _, id in ipairs(GTD.Data.towers.roots) do
		self.roots[id] = true
	end
	self.selected = {}   -- pid -> tower id chosen in the build menu
	self.all = {}        -- entindex -> tower unit

	CustomGameEventManager:RegisterListener("gtd_build_select", function(_, ev) self:OnBuildSelect(ev) end)
	CustomGameEventManager:RegisterListener("gtd_upgrade", function(_, ev) self:OnUpgrade(ev) end)
	CustomGameEventManager:RegisterListener("gtd_sell", function(_, ev) self:OnSell(ev) end)
end

function Towers:Def(id)
	return self.list[id]
end

function Towers:OnBuildSelect(ev)
	local pid = ev.PlayerID
	if self.roots[ev.tower] then
		self.selected[pid] = ev.tower
	end
end

function Towers:SelectedDef(pid)
	local id = self.selected[pid]
	return id and self.list[id]
end

-- Called by the builder ability (gtd_build) when the builder reaches the target point.
function Towers:TryBuild(hero, point)
	local pid = hero:GetPlayerOwnerID()
	local def = self:SelectedDef(pid)
	if not def then
		GTD:Error(pid, "Select a tower in the build menu first.")
		return false
	end
	local center = Grid:Snap(point, def.footprint)
	if not Grid:CanBuild(center, def.footprint) then
		GTD:Error(pid, "Can't build there.")
		return false
	end
	if not Players:Spend(pid, def.cost) then
		GTD:Error(pid, "Not enough gold.")
		return false
	end
	self:Create(def, center, pid)
	GTD.Sounds:ForPlayer(pid, GTD.Sounds.BUILD)
	return true
end

function Towers:Create(def, center, pid)
	local hero = Players.heroes[pid]
	local pos = GTD.Util.Ground(center)
	local unit = CreateUnitByName(def.unit, pos, false, hero, hero, DOTA_TEAM_GOODGUYS)
	if not unit then
		print("[GTD] failed to create " .. tostring(def.unit))
		return nil
	end
	unit:SetAbsOrigin(pos)
	unit:SetForwardVector(Vector(0, -1, 0))
	if hero then
		unit:SetOwner(hero)
	end
	unit:SetControllableByPlayer(pid, true)
	unit.gtd = { tower = true, id = def.id, def = def, pid = pid, center = center, size = def.footprint, aura = {} }
	local core = unit:FindAbilityByName("gtd_tower_core")
	if core then
		core:SetLevel(1)
		unit.gtd_core = core
	end
	if not unit:HasModifier("modifier_gtd_tower") then
		unit:AddNewModifier(unit, core, "modifier_gtd_tower", {})
	end
	if (def.build_time or 0) > 0 then
		unit:AddNewModifier(unit, core, "modifier_gtd_constructing", { duration = def.build_time })
	end
	if def.immolation then
		unit:AddNewModifier(unit, core, "modifier_gtd_fire_trap", {})
	end
	Grid:Occupy(center, def.footprint, unit:entindex())
	self.all[unit:entindex()] = unit
	GTD.Auras:TowersChanged()
	return unit
end

function Towers:Remove(unit)
	local g = unit.gtd
	self.all[unit:entindex()] = nil
	Grid:Free(g.center, g.size)
	unit.gtd = nil
	unit:AddNoDraw()
	unit:ForceKill(false)
	unit:RemoveSelf()
	GTD.Auras:TowersChanged()
end

function Towers:Owned(pid, ent)
	local unit = ent and EntIndexToHScript(ent)
	if not unit or not IsValidEntity(unit) or not unit.gtd or not unit.gtd.tower then
		return nil
	end
	if unit.gtd.pid ~= pid then
		return nil
	end
	return unit
end

function Towers:OnUpgrade(ev)
	local pid = ev.PlayerID
	local unit = self:Owned(pid, tonumber(ev.entindex))
	if not unit or Players.left[pid] then
		return
	end
	local g = unit.gtd
	local ok = false
	for _, id in ipairs(g.def.upgrades or {}) do
		if id == ev.to then
			ok = true
		end
	end
	local def = ok and self.list[ev.to]
	if not def then
		return
	end
	if def.footprint ~= g.size then
		Grid:Free(g.center, g.size)
		local fits = Grid:CanBuild(g.center, def.footprint)
		Grid:Occupy(g.center, g.size, unit:entindex())
		if not fits then
			GTD:Error(pid, "Can't build there.")
			return
		end
	end
	if not Players:Spend(pid, def.cost) then
		GTD:Error(pid, "Not enough gold.")
		return
	end
	local center = g.center
	self:Remove(unit)
	local new = self:Create(def, center, pid)
	GTD.Sounds:ForPlayer(pid, GTD.Sounds.BUILD)
	if new then
		local player = PlayerResource:GetPlayer(pid)
		if player then
			CustomGameEventManager:Send_ServerToPlayer(player, "gtd_select_unit", { entindex = new:entindex() })
		end
	end
end

-- WC3: training the "SELL" unit refunds the tower's point value (level 1 towers sell for full price).
function Towers:OnSell(ev)
	local pid = ev.PlayerID
	local unit = self:Owned(pid, tonumber(ev.entindex))
	if not unit then
		return
	end
	local refund = unit.gtd.def.sell or 0
	Players:AddGold(pid, refund)
	local player = PlayerResource:GetPlayer(pid)
	if refund > 0 then
		SendOverheadEventMessage(player, OVERHEAD_ALERT_GOLD, unit, refund, player)
	end
	GTD.Sounds:ForPlayer(pid, GTD.Sounds.SELL)
	self:Remove(unit)
end

function Towers:RemoveAllOf(pid)
	local list = {}
	for _, unit in pairs(self.all) do
		if IsValidEntity(unit) and unit.gtd and unit.gtd.pid == pid then
			list[#list + 1] = unit
		end
	end
	for _, unit in ipairs(list) do
		self:Remove(unit)
	end
end

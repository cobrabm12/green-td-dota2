-- Gold, kills and slots. A Dota player id 0..8 is the WC3 player slot (0 = Red ... 8 = Gray).
-- Gold is kept here instead of Dota gold: WC3 gold goes far past Dota's 99999 cap in late waves.
GTD.Players = GTD.Players or {}
local Players = GTD.Players

function Players:Init()
	self.gold = {}
	self.kills = {}
	self.left = {}
	self.heroes = {}
end

function Players:Slot(pid)
	return GTD.Data.map.slots[pid + 1]
end

-- WC3 "GetPlayerSlotState(...) == PLAYER_SLOT_STATE_PLAYING"
function Players:IsPlaying(pid)
	if pid == nil or pid < 0 or pid >= GTD.MAX_SLOTS then
		return false
	end
	if self.left[pid] or not PlayerResource:IsValidPlayerID(pid) then
		return false
	end
	local state = PlayerResource:GetConnectionState(pid)
	return state ~= DOTA_CONNECTION_STATE_ABANDONED and state ~= DOTA_CONNECTION_STATE_FAILED
end

function Players:GetGold(pid)
	return self.gold[pid] or 0
end

function Players:SetGold(pid, amount)
	self.gold[pid] = math.max(0, math.floor(amount))
	self:Sync(pid)
end

function Players:AddGold(pid, amount)
	self:SetGold(pid, self:GetGold(pid) + amount)
end

function Players:Spend(pid, amount)
	if self:GetGold(pid) < amount then
		return false
	end
	self:SetGold(pid, self:GetGold(pid) - amount)
	return true
end

function Players:AddKill(pid)
	self.kills[pid] = (self.kills[pid] or 0) + 1
	self:Sync(pid)
end

-- Net table updates are batched (late waves give hundreds of bounties per second).
function Players:Sync(pid)
	self.dirty = self.dirty or {}
	self.dirty[pid] = true
	if self.flushScheduled then
		return
	end
	self.flushScheduled = true
	GTD:Timer(0.2, function()
		self.flushScheduled = false
		local dirty = self.dirty
		self.dirty = {}
		for id in pairs(dirty) do
			local slot = self:Slot(id)
			CustomNetTables:SetTableValue("gtd_players", tostring(id), {
				gold = self.gold[id] or 0,
				kills = self.kills[id] or 0,
				color = slot and slot.color or "",
				left = self.left[id] and 1 or 0,
			})
		end
		return nil
	end)
end

-- Melee Initialization + "nig": Red gets 250, then every user +700, then +150.
function Players:GiveStartingGold()
	GTD.Util.ForEachSlot(function(pid)
		local gold = (pid == 0) and 250 or 0
		self:SetGold(pid, gold + 700 + 150)
	end)
end

function Players:GiveAll(amount)
	GTD.Util.ForEachSlot(function(pid)
		self:AddGold(pid, amount)
	end)
end

function Players:SetupHero(hero)
	local pid = hero:GetPlayerOwnerID()
	if pid < 0 or self.heroes[pid] == hero then
		return
	end
	self.heroes[pid] = hero
	local slot = self:Slot(pid)
	if slot then
		-- the engine places the hero at the map's spawn point right after npc_spawned: move it a moment later
		GTD:Timer(0.1, function()
			if not IsValidEntity(hero) then
				return nil
			end
			local pos = GTD.Util.Ground(Vector(slot.start[1], slot.start[2], 0))
			FindClearSpaceForUnit(hero, pos, true)
			hero:Stop()
			PlayerResource:SetCameraTarget(pid, hero)
			GTD:Timer(0.5, function() PlayerResource:SetCameraTarget(pid, nil) end)
			return nil
		end)
	end
	for i = 0, hero:GetAbilityCount() - 1 do
		local ab = hero:GetAbilityByIndex(i)
		if ab and ab:GetAbilityName() == "gtd_build" then
			ab:SetLevel(1)
		end
	end
	hero:SetAbilityPoints(0)
	-- the starting TP scroll is given a moment after spawning
	GTD:Timer(1, function()
		if not IsValidEntity(hero) then
			return nil
		end
		for slot_index = 0, 16 do
			local item = hero:GetItemInSlot(slot_index)
			if item then
				hero:RemoveItem(item)
			end
		end
		return nil
	end)
	hero:AddNewModifier(hero, nil, "modifier_gtd_builder", {})
	self:Sync(pid)
end

-- WC3 "leave kill": when a player leaves all of his units die and his spawn stops.
function Players:Leave(pid, reason)
	if self.left[pid] then
		return
	end
	self.left[pid] = true
	GTD.Towers:RemoveAllOf(pid)
	local hero = self.heroes[pid]
	if hero and IsValidEntity(hero) then
		hero:AddNoDraw()
		hero:AddNewModifier(hero, nil, "modifier_stunned", {})
	end
	self:Sync(pid)
	GTD.Sounds:Global(GTD.Sounds.LEAVE)
	local slot = self:Slot(pid)
	GTD:Message(PlayerResource:GetPlayerName(pid) .. " (" .. (slot and slot.color or "?") .. ") " .. (reason or "has left the game."), { color = "#ff7f7f" })
end

function Players:CheckLeavers()
	for pid = 0, GTD.MAX_SLOTS - 1 do
		if not self.left[pid] and PlayerResource:IsValidPlayerID(pid)
			and PlayerResource:GetConnectionState(pid) == DOTA_CONNECTION_STATE_ABANDONED then
			self:Leave(pid)
		end
	end
end

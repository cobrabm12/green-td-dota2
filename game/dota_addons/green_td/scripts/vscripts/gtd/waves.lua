-- Wave flow of the original triggers:
--   WAVESCOUNT: 45 s timer -> Waves1
--   WavesN: spawns at every playing player's spawn region, then enables WavstartN+1
--   WavstartN+1: every second, if Player 12 has no units left -> (wait) -> WavesN+1 and gold to everybody
--   after the last wave: Winstart (every 10 s, no creeps left -> 10 s -> victory)
--   END region: -1 chance; 0 chances -> defeat
GTD.Waves = GTD.Waves or {}
local Waves = GTD.Waves

function Waves:Init()
	self.list = GTD.Data.waves
	self.current = 0
	self.chances = GTD.START_LIVES
	self.handicap = GTD.START_HANDICAP
	self.waitingFor = nil
	self.waitingWin = false
	self.finished = false
	self.nextAt = nil
	self:Sync()
end

function Waves:Sync()
	local w = self.list[self.current]
	CustomNetTables:SetTableValue("gtd_game", "state", {
		wave = self.current,
		total = 60,
		count = #self.list,
		chances = self.chances,
		kind = w and w.kind or "",
		text = w and GTD.Util.StripColors(w.text) or "",
		next_at = self.nextAt or -1,
		creeps = GTD.Creeps.count or 0,
	})
end

function Waves:Start()
	self.nextAt = GameRules:GetGameTime() + GTD.FIRST_WAVE_DELAY
	self:Sync()
	GTD:Timer(GTD.FIRST_WAVE_DELAY, function()
		if self.hold then
			return 1   -- held by gtd_selftest
		end
		self.nextAt = nil
		self:Run(1)
	end)
	GTD:Timer(1, function()
		return self:Think()
	end)
	GTD:Timer(GTD.FIRST_WAVE_DELAY - 1, function()
		GTD.Sounds:Global(GTD.Sounds.FIRST_WAVE_WARNING)
		return nil
	end)
end

function Waves:Run(n)
	local w = self.list[n]
	if not w or self.finished then
		return
	end
	self.current = n
	self.nextAt = nil
	self:Sync()
	print(string.format("[GTD] wave %d started (chances %d, time %.0f)", n, self.chances, GameRules:GetGameTime()))
	GTD.Sounds:Wave(w)
	GTD:Message(w.text, { color = w.kind == "air" and "#7fbfff" or (w.kind == "immune" and "#ff7fff") or "#7f7fff", duration = 8 })
	CustomGameEventManager:Send_ServerToAllClients("gtd_wave", { wave = n, kind = w.kind })

	local i = 0
	local function step()
		while true do
			i = i + 1
			local ev = w.seq[i]
			if not ev then
				if n < #self.list then
					self.waitingFor = n + 1
				else
					self.waitingWin = true
				end
				return nil
			end
			if ev.wait then
				return ev.wait
			elseif ev.handicap then
				self.handicap = ev.handicap
			elseif ev.spawn then
				if GTD.Players:IsPlaying(ev.slot) then
					for _ = 1, ev.count do
						GTD.Creeps:Spawn(ev.spawn, ev.region, self.handicap)
					end
				end
			end
		end
	end
	GTD:Timer(0, step)
end

function Waves:Think()
	if self.finished then
		return nil
	end
	GTD.Players:CheckLeavers()
	if self.hold then
		self:Sync()
		return 1
	end
	if self.waitingFor and GTD.Creeps.count <= 0 then
		local n = self.waitingFor
		self.waitingFor = nil
		local w = self.list[n]
		local function go()
			self:Run(n)
			GTD.Players:GiveAll(w.start_gold or 0)
		end
		if (w.start_delay or 0) > 0 then
			self.nextAt = GameRules:GetGameTime() + w.start_delay
			self:Sync()
			GTD:Timer(w.start_delay, function()
				self.nextAt = nil
				go()
			end)
		else
			go()
		end
	elseif self.waitingWin and GTD.Creeps.count <= 0 then
		self.waitingWin = false
		GTD:Timer(10, function()
			self:Victory()
		end)
	end
	self:Sync()
	return 1
end

function Waves:LoseChance()
	self.leaked = (self.leaked or 0) + 1
	if self.finished or self.noLose then
		return
	end
	self.chances = self.chances - 1
	self:Sync()
	GTD:Message("Warning! " .. self.chances .. " Chances left!", { color = "#ff4040", duration = 4 })
	if self.chances <= 0 then
		self:Defeat()
	end
end

function Waves:Victory()
	if self.finished then
		return
	end
	self.finished = true
	print(string.format("[GTD] VICTORY after wave %d, chances left %d", self.current, self.chances))
	GTD.Sounds:Global(GTD.Sounds.VICTORY)
	GTD:Message("Victory! All waves defeated.", { color = "#40ff40", duration = 15 })
	GameRules:SetGameWinner(DOTA_TEAM_GOODGUYS)
end

-- Trigger "defeat": every player's units die, "GAME OVER!", then defeat.
function Waves:Defeat()
	if self.finished then
		return
	end
	self.finished = true
	print(string.format("[GTD] DEFEAT at wave %d", self.current))
	for pid = 0, GTD.MAX_SLOTS - 1 do
		GTD.Towers:RemoveAllOf(pid)
	end
	GTD.Sounds:Global(GTD.Sounds.DEFEAT)
	GTD:Message("GAME OVER!", { color = "#ff0000", duration = 10 })
	GTD:Timer(6, function()
		GameRules:SetGameWinner(DOTA_TEAM_BADGUYS)
	end)
end

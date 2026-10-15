-- Developer console commands (only in the Workshop Tools, never in published games: gtd_lua runs any Lua):
--   gtd_state                    print game state
--   gtd_gold <amount> [pid]      set gold
--   gtd_build <tower> <x> <y> [pid]
--   gtd_upgrade <entindex> <tower>
--   gtd_wave <n>                 start wave n now (removes current creeps)
--   gtd_selftest                 automated checks, prints [GTD-TEST] lines
GTD.Dev = GTD.Dev or {}
local Dev = GTD.Dev

local function out(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end
	print("[GTD-TEST] " .. table.concat(parts, " "))
end

-- Registers the console commands (again after script_reload, so the handlers are current).
function Dev:Init()
	if not IsInToolsMode() then
		return
	end
	self.commands = self.commands or {}
	local flags = FCVAR_CHEAT
	local Reg = {
		RegisterCommand = function(_, name, fn, help, fl)
			self.commands[name] = true
			Convars:RegisterCommand(name, fn, help, fl)   -- replaces the old handler after script_reload
		end,
	}
	Reg:RegisterCommand("gtd_state", function() self:State() end, "Green TD: print state", flags)
	Reg:RegisterCommand("gtd_gold", function(_, amount, pid)
		GTD.Players:SetGold(tonumber(pid) or 0, tonumber(amount) or 0)
		out("gold", pid or 0, amount)
	end, "Green TD: set gold", flags)
	Reg:RegisterCommand("gtd_build", function(_, id, x, y, pid)
		local ok, u = self:Build(id, tonumber(x), tonumber(y), tonumber(pid) or 0)
		out("build", id, x, y, ok and "ok" or "failed", u and u:entindex() or "")
	end, "Green TD: build a tower", flags)
	Reg:RegisterCommand("gtd_upgrade", function(_, ent, to)
		local unit = EntIndexToHScript(tonumber(ent) or -1)
		local pid = unit and unit.gtd and unit.gtd.pid or 0
		GTD.Towers:OnUpgrade({ PlayerID = pid, entindex = tonumber(ent), to = to })
		out("upgrade", ent, to)
	end, "Green TD: upgrade a tower", flags)
	Reg:RegisterCommand("gtd_wave", function(_, n)
		GTD.Creeps:KillAll()
		GTD.Waves.waitingFor = nil
		GTD.Waves:Run(tonumber(n) or 1)
		out("wave", n)
	end, "Green TD: start a wave", flags)
	Reg:RegisterCommand("gtd_hold", function(_, v)
		GTD.Waves.hold = (tonumber(v) or 1) ~= 0
		out("hold", tostring(GTD.Waves.hold))
	end, "Green TD: hold the wave flow", flags)
	Reg:RegisterCommand("gtd_nolose", function(_, v)
		GTD.Waves.noLose = (tonumber(v) or 1) ~= 0
		out("nolose", tostring(GTD.Waves.noLose))
	end, "Green TD: creeps reaching END do not cost chances", flags)
	Reg:RegisterCommand("gtd_selftest", function()
		self:SelfTest()
	end, "Green TD: run self test", flags)
	Reg:RegisterCommand("gtd_selftest2", function()
		self:SelfTest2()
	end, "Green TD: run mechanics tests", flags)
	-- gtd_fps [seconds]: clients count their rendered frames and report back (printed as [GTD-TEST] fps ...)
	Reg:RegisterCommand("gtd_fps", function(_, seconds)
		CustomGameEventManager:Send_ServerToAllClients("gtd_measure_fps", { seconds = tonumber(seconds) or 5 })
	end, "Green TD: measure client fps", flags)
	-- gtd_hud 0|1: hide / show the interface (screenshots)
	Reg:RegisterCommand("gtd_hud", function(_, v)
		CustomGameEventManager:Send_ServerToAllClients("gtd_hud_visible", { visible = v ~= "0" })
	end, "Green TD: show / hide the HUD", flags)
	-- gtd_soundcheck <name,name,...>: the client reports which sound events exist
	Reg:RegisterCommand("gtd_soundcheck", function(_, names)
		CustomGameEventManager:Send_ServerToAllClients("gtd_sound_check", { names = names or "" })
	end, "Green TD: check sound event names", flags)
	if not self.soundListener then
		self.soundListener = CustomGameEventManager:RegisterListener("gtd_sound_result", function(_, ev)
			for item in tostring(ev.results or ""):gmatch("[^,]+") do
				out("sound " .. item)
			end
		end)
	end
	if not self.fpsListener then
		self.fpsListener = CustomGameEventManager:RegisterListener("gtd_fps_result", function(_, ev)
			local creeps = GTD.Creeps.count or 0
			local towers = 0
			for _ in pairs(GTD.Towers.all) do towers = towers + 1 end
			out(string.format("fps player=%d fps=%.1f over %.1fs (wave %d, creeps %d, towers %d)",
				ev.PlayerID or -1, ev.fps or 0, ev.seconds or 0, GTD.Waves.current or 0, creeps, towers))
		end)
	end
	-- long snippets arrive in chunks: gtd_luax_add <hex> ... then gtd_luax <last hex>
	Reg:RegisterCommand("gtd_luax_add", function(_, hex)
		self.luaBuffer = (self.luaBuffer or "") .. tostring(hex or "")
	end, "Green TD: buffer hex-encoded Lua", flags)
	Reg:RegisterCommand("gtd_luax", function(_, hex)
		local all = (self.luaBuffer or "") .. tostring(hex or "")
		self.luaBuffer = nil
		local code = all:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)
		local fn, err = loadstring(code)
		if not fn then
			out("lua compile error", err)
			return
		end
		local ok, res = pcall(fn)
		out("lua", ok and "ok" or "error", tostring(res))
	end, "Green TD: run hex-encoded Lua", flags)
	Reg:RegisterCommand("gtd_lua", function(_, ...)
		local code = table.concat({ ... }, " ")
		local fn, err = loadstring(code)
		if not fn then
			out("lua compile error", err)
			return
		end
		local ok, res = pcall(fn)
		out("lua", ok and "ok" or "error", tostring(res))
	end, "Green TD: run Lua", flags)
end

function Dev:State()
	local towers = 0
	for _ in pairs(GTD.Towers.all) do
		towers = towers + 1
	end
	out("state wave=" .. GTD.Waves.current, "chances=" .. GTD.Waves.chances, "creeps=" .. GTD.Creeps.count,
		"towers=" .. towers, "handicap=" .. GTD.Waves.handicap, "gold0=" .. GTD.Players:GetGold(0),
		"kills0=" .. (GTD.Players.kills[0] or 0), "time=" .. string.format("%.1f", GameRules:GetGameTime()))
end

function Dev:Build(id, x, y, pid)
	local hero = GTD.Players.heroes[pid]
	if not hero or not GTD.Data.towers.list[id] then
		return false
	end
	GTD.Towers.selected[pid] = id   -- any tower, not only the build menu roots
	local before = {}
	for k in pairs(GTD.Towers.all) do
		before[k] = true
	end
	local ok = GTD.Towers:TryBuild(hero, Vector(x, y, 0))
	for k, u in pairs(GTD.Towers.all) do
		if not before[k] then
			return ok, u
		end
	end
	return ok, nil
end

-- --------------------------------------------------------------------------- self test
local results = { pass = 0, fail = 0 }

local function check(name, cond, detail)
	if cond then
		results.pass = results.pass + 1
		out("PASS", name, detail or "")
	else
		results.fail = results.fail + 1
		out("FAIL", name, detail or "")
	end
end

-- first buildable spot near (x, y) that is free
function Dev:FindBuildSpot(x, y, size)
	for r = 0, 1200, 32 do
		for a = 0, 330, 30 do
			local p = Vector(x + math.cos(math.rad(a)) * r, y + math.sin(math.rad(a)) * r, 0)
			local c = GTD.Grid:Snap(p, size)
			if GTD.Grid:CanBuild(c, size) then
				return c
			end
		end
	end
	return nil
end

function Dev:SelfTest()
	results = { pass = 0, fail = 0 }
	GTD.Waves.hold = true
	GTD.Creeps:KillAll()
	for pid = 0, GTD.MAX_SLOTS - 1 do
		GTD.Towers:RemoveAllOf(pid)
	end
	out("selftest start")

	-- 1. every unit in the KV can be created
	local origin = Vector(0, -6000, 0)
	local missing = {}
	for id, t in pairs(GTD.Data.towers.list) do
		local u = CreateUnitByName(t.unit, origin, false, nil, nil, DOTA_TEAM_GOODGUYS)
		if u then u:RemoveSelf() else missing[#missing + 1] = t.unit end
	end
	for id, c in pairs(GTD.Data.creeps) do
		local u = CreateUnitByName(c.unit, origin, false, nil, nil, DOTA_TEAM_BADGUYS)
		if u then u:RemoveSelf() else missing[#missing + 1] = c.unit end
	end
	check("all units create", #missing == 0, table.concat(missing, ","))

	-- 2. build grid: path cells not buildable, spawn regions walkable
	local r = GTD.Data.map.rects["1a"]
	local c = GTD.Util.RectCenter(r)
	check("path not buildable", not GTD.Grid:CanBuild(GTD.Grid:Snap(c, 4), 4))

	-- no tower can stand on a doodad with a pathing texture (rock, statue, column ...). The WC3 pathing map
	-- already has these cells blocked; GTD.Grid:MarkDoodads marks them too.
	local tested, blocked = 0, 0
	for _, d in ipairs(GTD.Data.map.doodads or {}) do
		if d.block then
			tested = tested + 1
			if not GTD.Grid:CanBuild(GTD.Grid:Snap(Vector(d.x, d.y, 0), 4), 4) then
				blocked = blocked + 1
			end
		end
	end
	check("doodads block building", tested > 0 and blocked == tested, blocked .. "/" .. tested)

	-- 3. WC3 math
	local cm = GTD.Combat
	check("armor 0", math.abs(cm:ArmorMultiplier(0) - 1) < 1e-6)
	check("armor 10", math.abs(cm:ArmorMultiplier(10) - (1 - 0.6 / 1.6)) < 1e-6)
	check("pierce vs small", cm:TypeMultiplier("pierce", "small") == 2)
	check("magic vs fort", cm:TypeMultiplier("magic", "fort") == 0.35)

	-- every sound event used exists (GetSoundDuration returns -1 for unknown events)
	local h0 = GTD.Players.heroes[0]
	if h0 then
		local bad = {}
		for _, name in ipairs(GTD.Sounds:All()) do
			if h0:GetSoundDuration(name, "") <= 0 then
				bad[#bad + 1] = name
			end
		end
		check("sounds exist", #bad == 0, #bad == 0 and (#GTD.Sounds:All() .. " sounds") or table.concat(bad, ","))
	end

	-- 4. build + gold
	local hero = GTD.Players.heroes[0]
	check("hero exists", hero ~= nil)
	if not hero then
		GTD.Waves.hold = false
		out("selftest done", results.pass, "passed", results.fail, "failed")
		return
	end
	GTD.Players:SetGold(0, 100000)
	local spot = self:FindBuildSpot(-5264, 2080, 4)   -- next to the Pink path (region 1a)
	check("found build spot", spot ~= nil)
	local gold0 = GTD.Players:GetGold(0)
	local ok, tower = self:Build("h000", spot.x, spot.y, 0)
	check("build siege tower", ok and tower ~= nil)
	check("gold spent", GTD.Players:GetGold(0) == gold0 - 25, GTD.Players:GetGold(0))
	check("spot now occupied", not GTD.Grid:CanBuild(spot, 4))
	if tower then
		-- upgrade
		GTD.Towers:OnUpgrade({ PlayerID = 0, entindex = tower:entindex(), to = "h002" })
		local upgraded
		for _, u in pairs(GTD.Towers.all) do
			if u.gtd and u.gtd.id == "h002" then upgraded = u end
		end
		check("upgrade to h002", upgraded ~= nil)
		check("upgrade cost", GTD.Players:GetGold(0) == gold0 - 25 - 40, GTD.Players:GetGold(0))
		-- sell
		if upgraded then
			local g = GTD.Players:GetGold(0)
			GTD.Towers:OnSell({ PlayerID = 0, entindex = upgraded:entindex() })
			check("sell refund", GTD.Players:GetGold(0) == g + 40, GTD.Players:GetGold(0) - g)
			check("spot free after sell", GTD.Grid:CanBuild(spot, 4))
		end
	end

	-- 5. combat: a footman walking past a poison tower takes damage and the tower owner gets bounty
	local spot2 = self:FindBuildSpot(-5264, 2080, 4)
	local ok2, ptower = self:Build("h00F", spot2.x, spot2.y, 0)   -- Poison Tower 10 (fast, 1000 range)
	check("build poison tower", ok2 and ptower ~= nil)
	local creep = GTD.Creeps:Spawn("hfoo", "1_Pink_Spawn", 200)
	check("spawn footman", creep ~= nil)
	check("footman hp x2", creep and creep:GetMaxHealth() == 1000, creep and creep:GetMaxHealth())
	local goldBefore = GTD.Players:GetGold(0)
	local killsBefore = GTD.Players.kills[0] or 0
	local startPos = creep and creep:GetAbsOrigin()
	GTD:Timer(4, function()
		if creep and IsValidEntity(creep) and creep:IsAlive() then
			check("footman moving", (creep:GetAbsOrigin() - startPos):Length2D() > 200,
				string.format("%.0f", (creep:GetAbsOrigin() - startPos):Length2D()))
		end
		return nil
	end)
	GTD:Timer(25, function()
		local dead = not (creep and IsValidEntity(creep) and creep:IsAlive())
		check("footman killed by tower", dead)
		check("bounty paid", GTD.Players:GetGold(0) >= goldBefore + 31, GTD.Players:GetGold(0) - goldBefore)
		check("kill counted", (GTD.Players.kills[0] or 0) == killsBefore + 1)
		check("creep count back to 0", GTD.Creeps.count == 0, GTD.Creeps.count)
		if ptower and IsValidEntity(ptower) and ptower.gtd then
			GTD.Towers:Remove(ptower)
		end
		GTD.Waves.hold = false
		out("selftest done", results.pass, "passed", results.fail, "failed")
		return nil
	end)
end

if Convars then
	GTD.Dev:Init()
end

-- Mechanics tests (gtd_selftest2): every special rule of the WC3 map, checked in the running game.
local Dev = GTD.Dev

local results
local function out(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end
	print("[GTD-TEST] " .. table.concat(parts, " "))
end

local function check(name, cond, detail)
	if cond then
		results.pass = results.pass + 1
		out("PASS", name, detail or "")
	else
		results.fail = results.fail + 1
		out("FAIL", name, detail or "")
	end
end

local function alive(u)
	return u and IsValidEntity(u) and u:IsAlive()
end

local function hp(u)
	return alive(u) and u:GetHealth() or 0
end

-- spawn a creep at an exact point, held in place by a stun
local function creepAt(id, pos, handicap, stun)
	local c = GTD.Creeps:Spawn(id, "1_Pink_Spawn", handicap or 200)
	if c then
		FindClearSpaceForUnit(c, pos, false)
		c:SetAbsOrigin(GTD.Util.Ground(pos))
		if stun ~= false then
			c:AddNewModifier(c, nil, "modifier_stunned", { duration = 30 })
		end
	end
	return c
end

local function cleanup()
	GTD.Creeps:KillAll()
	for pid = 0, GTD.MAX_SLOTS - 1 do
		GTD.Towers:RemoveAllOf(pid)
	end
end

-- runs steps one after another; a step returns the delay before the next one
local function run(steps)
	local i = 0
	local function nextStep()
		i = i + 1
		local step = steps[i]
		if not step then
			return nil
		end
		local ok, delay = xpcall(step, debug.traceback)
		if not ok then
			results.fail = results.fail + 1
			out("FAIL step " .. i .. " error", delay)
			delay = 0
		end
		GTD:Timer(delay or 0, nextStep)
		return nil
	end
	nextStep()
end

function Dev:SelfTest2()
	results = { pass = 0, fail = 0 }
	GTD.Waves.hold = true
	GTD.Waves.noLose = true
	GTD.Players:SetGold(0, 1000000)
	cleanup()
	out("selftest2 start")

	local base = Vector(-4300, 3700, 0)   -- buildable area inside the Pink zone
	local t, c1, c2, c3, list, aura, h0

	run({
		-- splash: Siege Tower 5 (200/250/300 splash, 0.5 / 0.1), three footmen around the primary target
		function()
			local spot = Dev:FindBuildSpot(base.x, base.y, 4)
			local ok
			ok, t = Dev:Build("h005", spot.x, spot.y, 0)
			check("splash: tower built", ok and t ~= nil)
			local p = spot + Vector(300, 0, 0)
			c1 = creepAt("hfoo", p)
			c2 = creepAt("hfoo", p + Vector(150, 0, 0))   -- full splash area (200)
			c3 = creepAt("hfoo", p + Vector(0, 280, 0))   -- small area (300): 10 %
			return 1.5   -- build time
		end,
		function()
			local h1, h2, h3 = hp(c1), hp(c2), hp(c3)
			t.gtd.def = t.gtd.def   -- keep
			GTD.Combat:OnAttackLanded(t, c1)
			local d1, d2, d3 = h1 - hp(c1), h2 - hp(c2), h3 - hp(c3)
			check("splash: primary damaged", d1 > 300, d1)
			check("splash: full area = primary", math.abs(d2 - d1) < 5, d2)
			check("splash: small area ~10%", d3 > 0 and d3 < d1 * 0.15, d3)
			cleanup()
			return 0.5
		end,

		-- multishot: Multishot Tower 1 hits several creeps per attack
		function()
			local spot = Dev:FindBuildSpot(base.x, base.y, 4)
			local ok
			ok, t = Dev:Build("h00X", spot.x, spot.y, 0)
			list = {}
			for i = 1, 5 do
				list[i] = creepAt("hfoo", spot + Vector(250 + i * 40, (i - 3) * 60, 0))
			end
			return 3
		end,
		function()
			local hurt = 0
			for _, c in ipairs(list) do
				if not alive(c) or c:GetHealth() < c:GetMaxHealth() then hurt = hurt + 1 end
			end
			check("multishot: several targets per attack", hurt >= 4, hurt .. "/5 damaged")
			cleanup()
			return 0.5
		end,

		-- bounce: Naisha lvl 1 glaive bounces between creeps (25 targets, 3% loss)
		function()
			local spot = Dev:FindBuildSpot(base.x, base.y, 6)
			local ok
			ok, t = Dev:Build("ensh", spot.x, spot.y, 0)
			check("bounce: Naisha built", ok and t ~= nil)
			list = {}
			for i = 1, 6 do
				list[i] = creepAt("hfoo", spot + Vector(300 + i * 120, 0, 0))
			end
			return 3
		end,
		function()
			local hurt = 0
			for _, c in ipairs(list) do
				if not alive(c) or c:GetHealth() < c:GetMaxHealth() then hurt = hurt + 1 end
			end
			check("bounce: glaive hits many creeps", hurt >= 5, hurt .. "/6 damaged")
			cleanup()
			return 0.5
		end,

		-- frost: slows by 50 %, magic attack does nothing to immune creeps (wave 5 Priest)
		function()
			local spot = Dev:FindBuildSpot(base.x, base.y, 4)
			local ok
			ok, t = Dev:Build("n006", spot.x, spot.y, 0)
			c1 = creepAt("hfoo", spot + Vector(250, 0, 0), 200, false)
			c2 = creepAt("hmpr", spot + Vector(250, 150, 0), 200, false)
			c1:AddNewModifier(c1, nil, "modifier_rooted", { duration = 30 })
			c2:AddNewModifier(c2, nil, "modifier_rooted", { duration = 30 })
			return 1.5
		end,
		function()
			local h2 = hp(c2)
			GTD.Combat:OnAttackLanded(t, c1)
			GTD.Combat:OnAttackLanded(t, c2)
			check("frost: slow applied", c1:HasModifier("modifier_gtd_frost"))
			check("frost: not on immune", not c2:HasModifier("modifier_gtd_frost"))
			check("frost: no damage to immune", hp(c2) == h2, h2 - hp(c2))
			return 0.3
		end,
		function()
			local ms = c1:GetIdealSpeed()
			check("frost: speed 400 -> 200", math.abs(ms - 200) < 2, ms)
			cleanup()
			return 0.5
		end,

		-- poison: organic creeps are slowed and poisoned, mechanical (Flying Machine) are not
		function()
			local spot = Dev:FindBuildSpot(base.x, base.y, 4)
			local ok
			ok, t = Dev:Build("h008", spot.x, spot.y, 0)
			c1 = creepAt("hrif", spot + Vector(250, 0, 0), 200, false)
			c2 = creepAt("hgyr", spot + Vector(250, 150, 0), 200, false)
			c1:AddNewModifier(c1, nil, "modifier_rooted", { duration = 30 })
			c2:AddNewModifier(c2, nil, "modifier_rooted", { duration = 30 })
			return 1.5
		end,
		function()
			GTD.Combat:OnAttackLanded(t, c1)
			GTD.Combat:OnAttackLanded(t, c2)
			check("poison: on organic", c1:HasModifier("modifier_gtd_poison"))
			check("poison: not on mechanical", not c2:HasModifier("modifier_gtd_poison"))
			return 0.3
		end,
		function()
			local ms = c1:GetIdealSpeed()
			check("poison: speed 400 -> 200", math.abs(ms - 200) < 2, ms)
			cleanup()
			return 0.5
		end,

		-- air / ground: Siege Tower (ground only) ignores the Flying Machine, Air Tower only shoots it
		function()
			local spot = Dev:FindBuildSpot(base.x, base.y, 4)
			local ok
			ok, t = Dev:Build("h000", spot.x, spot.y, 0)
			c1 = creepAt("hgyr", spot + Vector(250, 0, 0))
			local siegeTarget = GTD.Combat:FindTarget(t, t.gtd.def.attack, 800)
			check("air: siege tower ignores air", siegeTarget == nil)
			local spot2 = Dev:FindBuildSpot(base.x, base.y, 4)
			local ok2, t2 = Dev:Build("n00M", spot2.x, spot2.y, 0)
			c2 = creepAt("hfoo", spot2 + Vector(200, 0, 0))
			local airTarget = GTD.Combat:FindTarget(t2, t2.gtd.def.attack, 600)
			check("air: air tower picks the flyer", airTarget == c1, tostring(airTarget and airTarget:GetUnitName()))
			cleanup()
			return 0.5
		end,

		-- fire trap: 400 dps spell damage around the trap, nothing to immune creeps
		function()
			local spot = Dev:FindBuildSpot(base.x, base.y, 6)
			local ok
			ok, t = Dev:Build("n00A", spot.x, spot.y, 0)
			c1 = creepAt("hfoo", spot + Vector(120, 0, 0))
			c2 = creepAt("hmpr", spot + Vector(0, 120, 0))
			return 5.2   -- 3 s build time + 2 ticks
		end,
		function()
			local d1 = c1:GetMaxHealth() - hp(c1)
			local d2 = c2:GetMaxHealth() - hp(c2)
			check("fire trap: burns", d1 >= 790 or not alive(c1), d1)
			check("fire trap: immune not burned", d2 == 0, d2)
			cleanup()
			return 0.5
		end,

		-- auras: Damage Tower (+100 %) next to a Siege Tower, Speed Tower (+150 % attack speed)
		function()
			local spot = Dev:FindBuildSpot(base.x, base.y, 4)
			local ok
			ok, aura = Dev:Build("h00H", spot.x, spot.y, 0)
			local spot2 = Dev:FindBuildSpot(base.x, base.y, 4)
			local ok2
			ok2, t = Dev:Build("h000", spot2.x, spot2.y, 0)
			return 1.5
		end,
		function()
			GTD.Towers:OnUpgrade({ PlayerID = 0, entindex = aura:entindex(), to = "h00I" })
			return 2
		end,
		function()
			check("aura: damage aura on neighbour", t.gtd.aura and t.gtd.aura.damage == 1, t.gtd.aura and t.gtd.aura.damage)
			c1 = creepAt("hfoo", t:GetAbsOrigin() + Vector(300, 0, 0))
			local h1 = hp(c1)
			GTD.Combat:OnAttackLanded(t, c1)
			local d = h1 - hp(c1)
			-- 51..52 x2 (aura) x siege/large 1.0 x armor 3 (0.847) = 86..88
			check("aura: doubles the damage", d >= 85 and d <= 89, d)
			for _, u in pairs(GTD.Towers.all) do
				if u.gtd.id == "h00I" then aura = u end
			end
			GTD.Towers:OnUpgrade({ PlayerID = 0, entindex = aura:entindex(), to = "h00O" })
			return 2
		end,
		function()
			for _, u in pairs(GTD.Towers.all) do
				if u.gtd.id == "h00O" then aura = u end
			end
			GTD.Towers:OnUpgrade({ PlayerID = 0, entindex = aura:entindex(), to = "h011" })   -- Speed Tower 2: +200 %
			return 2
		end,
		function()
			local mod = t:FindModifierByName("modifier_gtd_tower")
			check("aura: speed aura", t.gtd.aura.speed == 2, t.gtd.aura.speed)
			check("aura: attack speed bonus", mod and math.abs(mod.asb - 200) < 1, mod and mod.asb)
			cleanup()
			return 0.5
		end,

		-- evasion / devotion: wave 66 (Lich King: 95 % evasion, devotion 7500 around him; zombies 65 %)
		function()
			local p = base + Vector(600, 0, 0)
			c1 = creepAt("U002", p, 400)
			c2 = creepAt("nzom", p + Vector(200, 0, 0), 400)
			c3 = creepAt("nzom", p + Vector(2000, 0, 0), 400)
			return 1.2
		end,
		function()
			check("devotion: zombie next to Lich King", c2.gtd.aura_armor == 7500, c2.gtd.aura_armor)
			check("devotion: zombie far away keeps own", c3.gtd.aura_armor == 750, c3.gtd.aura_armor)
			check("lich king hp x4", c1:GetMaxHealth() == 2000000, c1:GetMaxHealth())
			local spot = Dev:FindBuildSpot(base.x, base.y, 4)
			local ok
			ok, t = Dev:Build("h02A", spot.x, spot.y, 0)   -- Multishot 12 (chaos)
			local misses = 0
			for _ = 1, 200 do
				local before = hp(c3)
				GTD.Combat:OnAttackLanded(t, c3)
				if hp(c3) == before then misses = misses + 1 end
				if not alive(c3) then break end
			end
			check("evasion: ~65% of attacks miss", misses > 100 and misses < 160, misses .. "/200")
			cleanup()
			return 0.5
		end,

		-- END region: a creep reaching it costs one chance
		function()
			GTD.Waves.noLose = false
			h0 = GTD.Waves.chances
			local r = GTD.Data.map.rects.EndGo
			c1 = GTD.Creeps:Spawn("hfoo", "EndGo", 200)
			return 4
		end,
		function()
			check("END: chance lost", GTD.Waves.chances == h0 - 1, GTD.Waves.chances)
			check("END: creep removed", GTD.Creeps.count == 0, GTD.Creeps.count)
			GTD.Waves.chances = h0
			GTD.Waves.noLose = true
			GTD.Waves:Sync()
			return 0
		end,

		function()
			cleanup()
			out("selftest2 done", results.pass, "passed", results.fail, "failed")
			return nil
		end,
	})
end

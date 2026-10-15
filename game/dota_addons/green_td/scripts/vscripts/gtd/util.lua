GTD.Util = GTD.Util or {}
local Util = GTD.Util

-- Run fn after delay seconds (game time). If fn returns a number, it runs again after that many seconds.
function GTD:Timer(delay, fn)
	local ent = GameRules:GetGameModeEntity()
	ent:SetContextThink(DoUniqueString("gtd_timer"), function()
		local ok, res = xpcall(fn, debug.traceback)
		if not ok then
			print("[GTD] timer error: " .. tostring(res))
			return nil
		end
		return res
	end, delay)
end

function Util.RollDice(dice, sides)
	local total = 0
	for _ = 1, dice or 0 do
		total = total + RandomInt(1, math.max(1, sides or 1))
	end
	return total
end

function Util.RectCenter(rect)
	return Vector((rect.min[1] + rect.max[1]) * 0.5, (rect.min[2] + rect.max[2]) * 0.5, 0)
end

function Util.InRect(pos, rect)
	return pos.x >= rect.min[1] and pos.x <= rect.max[1] and pos.y >= rect.min[2] and pos.y <= rect.max[2]
end

function Util.Ground(pos)
	return GetGroundPosition(Vector(pos.x, pos.y, 0), nil)
end

-- Removes WC3 color codes (|cAARRGGBB ... |r) from a string.
function Util.StripColors(s)
	s = tostring(s or "")
	s = s:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""):gsub("|n", " ")
	return s
end

-- Message to everybody (or to one player) in the custom HUD message area.
function GTD:Message(text, opts)
	opts = opts or {}
	local data = { text = Util.StripColors(text), color = opts.color or "#7fff7f", duration = opts.duration or 6 }
	if opts.player ~= nil then
		local player = PlayerResource:GetPlayer(opts.player)
		if player then
			CustomGameEventManager:Send_ServerToPlayer(player, "gtd_message", data)
		end
	else
		CustomGameEventManager:Send_ServerToAllClients("gtd_message", data)
	end
end

function GTD:Error(pid, text)
	local player = PlayerResource:GetPlayer(pid)
	if player then
		CustomGameEventManager:Send_ServerToPlayer(player, "gtd_error", { text = text })
	end
end

function Util.ForEachSlot(fn)
	for pid = 0, GTD.MAX_SLOTS - 1 do
		if PlayerResource:IsValidPlayerID(pid) then
			fn(pid)
		end
	end
end

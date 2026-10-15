-- Chat commands of the original map.
GTD.Commands = GTD.Commands or {}
local Commands = GTD.Commands

-- Texts of the original map (TRIGSTR_371, 370, 677, 739, 2367).
local INFO = {
	["-air"] = "-Air Levels are 7, 9,17,21,27,30,35,38,48,53,?? build Tower Air for Kill It !",
	["-immune"] = "-Immune waves: 5, 10, 15, 20, 25, 34, 43, 55, 57 ?? Ice tower and fire trap not hit imune units.",
	["-hero"] = "-Hero Levels are 39,40,41,42,43,44.45.46.47.49.50.51 52,54,55,56,",
	["-extra"] = "-Extra Levels past a 60 wave",
	["-hard"] = "-Most Hardest levels: 12, 24, 36, 49. Fast upgrade towers or upgrade auras for kill it.",
}

-- "-kick <color>" (only Red / the first player can use it).
local KICK = { blue = 1, teal = 2, purple = 3, yellow = 4, orange = 5, green = 6, pink = 7, gray = 8, grey = 8 }

function Commands:OnChat(ev)
	local pid = ev.playerid
	local text = string.lower(tostring(ev.text or ""))
	for key, msg in pairs(INFO) do
		if text:find(key, 1, true) then
			GTD:Message(msg, { color = "#8080ff", duration = 10 })
		end
	end
	local color = text:match("^%-kick (%a+)$")
	if color and pid == 0 and KICK[color] and GTD.Players:IsPlaying(KICK[color]) then
		GTD.Players:Leave(KICK[color], "was kicked by the host.")
	end
end

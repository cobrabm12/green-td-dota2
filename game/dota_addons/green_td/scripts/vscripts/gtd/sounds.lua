-- Sounds. The WC3 map played its own sound for every wave type (Wave_Normal, Wave_Air, ...); these are the
-- closest Dota sound events (all checked with GetSoundDuration in game: an unknown event returns -1).
GTD.Sounds = GTD.Sounds or {}
local Sounds = GTD.Sounds

Sounds.WAVE = {
	Wave_Normal = "ui.npe_objective_given",
	Wave_Air = "Hero_Jakiro.DualBreath.Cast",
	Wave_Immune = "DOTA_Item.BlackKingBar.Activate",
	Wave_Hero = "DOTAMusic_Hero.Reincarnate",
	Wave_Boss = "RoshanDT.Scream",
	PH1 = "RoshanDT.Scream",          -- wave 56 and the extra waves
}
Sounds.FIRST_WAVE_WARNING = "General.PingWarning"   -- WC3 PurgeTarget, 1 s before wave 1
Sounds.VICTORY = "Nemestice.Victory"
Sounds.DEFEAT = "Roshan.Death"
Sounds.BUILD = "General.Buy"
Sounds.SELL = "General.Sell"
Sounds.LEAVE = "General.Ping"                        -- WC3 HoofSteps1 when a player leaves

Sounds.FILES = {
	"soundevents/game_sounds.vsndevts",
	"soundevents/game_sounds_ui_imported.vsndevts",
	"soundevents/music/game_sounds_stingers_main.vsndevts",
	"soundevents/game_sounds_heroes/game_sounds_jakiro.vsndevts",
	"soundevents/game_sounds_creeps.vsndevts",
}

function Sounds:Global(name)
	if name then
		EmitGlobalSound(name)
	end
end

function Sounds:ForPlayer(pid, name)
	local player = pid and PlayerResource:GetPlayer(pid)
	if player and name then
		EmitSoundOnClient(name, player)
	end
end

function Sounds:Wave(wave)
	self:Global(self.WAVE[wave.sound] or self.WAVE.Wave_Normal)
end

-- every sound used, for the self test
function Sounds:All()
	local list = { self.FIRST_WAVE_WARNING, self.VICTORY, self.DEFEAT, self.BUILD, self.SELL, self.LEAVE }
	for _, name in pairs(self.WAVE) do
		list[#list + 1] = name
	end
	return list
end

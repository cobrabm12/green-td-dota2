if GTD == nil then
	GTD = {}
end

GTD.VERSION = "0.1.0"

-- Fastest attack interval we let Dota run (limits the number of missiles in flight). Faster WC3
-- towers keep their DPS by dealing proportionally more damage per attack (see modifier_gtd_tower).
-- Keep in sync with MIN_ATTACK_INTERVAL in tools/gen.py.
GTD.MIN_ATTACK_INTERVAL = 0.25

GTD.START_LIVES = 60          -- udg_Chances
GTD.FIRST_WAVE_DELAY = 45     -- WAVESCOUNT timer
GTD.START_HANDICAP = 200      -- "nig" difficulty, run by the "starte" trigger at 0s
GTD.MAX_SLOTS = 9

GTD.Data = {
	towers = require("gtd/data/towers"),
	creeps = require("gtd/data/creeps"),
	waves = require("gtd/data/waves"),
	map = require("gtd/data/map"),
}

require("gtd/util")
require("gtd/sounds")
require("gtd/grid")
require("gtd/players")
require("gtd/combat")
require("gtd/towers")
require("gtd/creeps")
require("gtd/auras")
require("gtd/waves")
require("gtd/commands")
require("gtd/visuals")
require("gtd/devtools")
require("gtd/devtests")
require("gtd/game")

LinkLuaModifier("modifier_gtd_tower", "modifiers/modifier_gtd_tower", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gtd_creep", "modifiers/modifier_gtd_creep", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gtd_poison", "modifiers/modifier_gtd_poison", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gtd_frost", "modifiers/modifier_gtd_frost", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gtd_fire_trap", "modifiers/modifier_gtd_fire_trap", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gtd_constructing", "modifiers/modifier_gtd_constructing", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gtd_builder", "modifiers/modifier_gtd_builder", LUA_MODIFIER_MOTION_NONE)

function GTD:Precache(context)
	local seen = {}
	local function add(kind, path)
		if path and not seen[path] then
			seen[path] = true
			PrecacheResource(kind, path, context)
		end
	end
	for _, t in pairs(GTD.Data.towers.list) do
		add("model", t.model)
		if t.attack then
			add("particle", t.attack.projectile)
		end
	end
	for _, c in pairs(GTD.Data.creeps) do
		add("model", c.model)
	end
	for _, d in ipairs(GTD.Data.map.doodads or {}) do
		add("model", d.model)
		add("particle", d.particle)
	end
	for _, p in ipairs({
		"particles/units/heroes/hero_skeletonking/wraith_king_reincarnate.vpcf",
		"particles/items2_fx/radiance_owner.vpcf",
		"particles/units/heroes/hero_venomancer/venomancer_gale_poison_debuff.vpcf",
		"particles/generic_gameplay/generic_slowed_cold.vpcf",
		"particles/status_fx/status_effect_frost.vpcf",
		"particles/generic_gameplay/generic_stunned.vpcf",
		"particles/econ/events/ti6/teleport_start_ti6.vpcf",
		"particles/gtd/path_dirt.vpcf",
	}) do
		add("particle", p)
	end
	for _, file in ipairs(GTD.Sounds.FILES) do
		add("soundfile", file)
	end
end

function GTD:Init()
	print("[GTD] Green TD " .. GTD.VERSION)
	GTD.Grid:Init()
	GTD.Players:Init()
	GTD.Combat:Init()
	GTD.Towers:Init()
	GTD.Creeps:Init()
	GTD.Auras:Init()
	GTD.Waves:Init()
	GTD.Dev:Init()

	GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, GTD.MAX_SLOTS)
	GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 0)
	GameRules:SetCustomGameSetupAutoLaunchDelay(10)
	GameRules:SetHeroSelectionTime(0)
	GameRules:SetStrategyTime(0)
	GameRules:SetShowcaseTime(0)
	GameRules:SetPreGameTime(0)
	GameRules:SetPostGameTime(60)
	GameRules:SetStartingGold(0)
	GameRules:SetGoldPerTick(0)
	GameRules:SetGoldTickTime(9999)
	GameRules:SetHeroRespawnEnabled(false)
	GameRules:SetUseUniversalShopMode(false)
	GameRules:SetFirstBloodActive(false)
	GameRules:SetHideKillMessageHeaders(true)
	GameRules:SetSameHeroSelectionEnabled(true)

	local mode = GameRules:GetGameModeEntity()
	mode:SetCustomGameForceHero("npc_dota_hero_wisp")
	mode:SetFogOfWarDisabled(true)            -- WC3: visibility modifier over the whole map for everybody
	mode:SetUnseenFogOfWarEnabled(false)
	mode:SetBuybackEnabled(false)
	mode:SetRecommendedItemsDisabled(true)
	mode:SetStashPurchasingDisabled(true)
	mode:SetStickyItemDisabled(true)
	mode:SetAnnouncerDisabled(true)
	mode:SetKillingSpreeAnnouncerDisabled(true)
	mode:SetDaynightCycleDisabled(true)
	mode:SetWeatherEffectsDisabled(true)
	mode:SetLoseGoldOnDeath(false)
	mode:SetCameraDistanceOverride(1500)
	mode:SetDamageFilter(Dynamic_Wrap(GTD, "DamageFilter"), GTD)
	mode:SetExecuteOrderFilter(Dynamic_Wrap(GTD, "OrderFilter"), GTD)

	ListenToGameEvent("game_rules_state_change", Dynamic_Wrap(GTD, "OnStateChange"), GTD)
	ListenToGameEvent("npc_spawned", Dynamic_Wrap(GTD, "OnNPCSpawned"), GTD)
	ListenToGameEvent("entity_killed", Dynamic_Wrap(GTD, "OnEntityKilled"), GTD)
	ListenToGameEvent("player_chat", Dynamic_Wrap(GTD, "OnPlayerChat"), GTD)
end

function GTD:OnStateChange()
	local state = GameRules:State_Get()
	if state == DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP then
		-- one team only: put everybody on it
		for pid = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
			if PlayerResource:IsValidPlayerID(pid) then
				PlayerResource:SetCustomTeamAssignment(pid, DOTA_TEAM_GOODGUYS)
			end
		end
	elseif state == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		GameRules:SetTimeOfDay(0.5)   -- always day (the day/night cycle is disabled)
		GTD.Grid:BlockTerrain()
		GTD.Visuals:DrawPaths()
		GTD.Visuals:PlaceDoodads()
		GTD.Players:GiveStartingGold()
		GTD.Waves:Start()
		GTD:Timer(0.5, function()
			GTD.Auras:Think()
			return 0.5
		end)
	end
end

function GTD:OnNPCSpawned(ev)
	local unit = EntIndexToHScript(ev.entindex)
	if unit and unit:IsRealHero() then
		GTD.Players:SetupHero(unit)
	end
end

function GTD:OnEntityKilled(ev)
	local unit = EntIndexToHScript(ev.entindex_killed)
	local killer = ev.entindex_attacker and EntIndexToHScript(ev.entindex_attacker)
	if unit and unit.gtd and unit.gtd.creep then
		GTD.Creeps:OnKilled(unit, killer)
	end
end

function GTD:OnPlayerChat(ev)
	GTD.Commands:OnChat(ev)
end

-- Towers never move; the builder may not attack.
local BLOCKED_TOWER_ORDERS = {
	[DOTA_UNIT_ORDER_MOVE_TO_POSITION] = true,
	[DOTA_UNIT_ORDER_MOVE_TO_TARGET] = true,
	[DOTA_UNIT_ORDER_ATTACK_MOVE] = true,
	[DOTA_UNIT_ORDER_HOLD_POSITION] = true,
	[DOTA_UNIT_ORDER_PATROL] = true,
}

function GTD:OrderFilter(ev)
	local order = ev.order_type
	local kept, removed = {}, false
	for key, idx in pairs(ev.units or {}) do
		local unit = EntIndexToHScript(idx)
		local drop = false
		if unit and unit.gtd and unit.gtd.tower then
			if BLOCKED_TOWER_ORDERS[order] then
				drop = true
			elseif order == DOTA_UNIT_ORDER_ATTACK_TARGET then
				local at = unit.gtd.def.attack
				drop = not at or not GTD.Combat:CanHit(at, EntIndexToHScript(ev.entindex_target))
			end
		end
		if drop then
			removed = true
		else
			kept[#kept + 1] = idx
		end
	end
	if removed then
		if #kept == 0 then
			return false
		end
		local units = {}
		for i, idx in ipairs(kept) do
			units[tostring(i - 1)] = idx
		end
		ev.units = units
	end
	return true
end

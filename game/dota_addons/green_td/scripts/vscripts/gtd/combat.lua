-- WC3 damage rules: attack type x defense type table, WC3 armor formula, splash, bounce,
-- critical strike, bash, evasion, spell immunity. Dota armor is not used at all (creeps have 0):
-- the Dota formula breaks at the armor values of the late waves (up to 8500).
GTD.Combat = GTD.Combat or {}
local Combat = GTD.Combat
local Util = GTD.Util

local ARMOR_FACTOR = 0.06   -- miscgame.txt DefenseArmor
local TARGET_TYPES = DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_HERO
local TARGET_FLAGS = DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES

function Combat:Init()
	local t = GTD.Data.towers
	self.table = t.attack_table
	self.defIndex = {}
	for i, d in ipairs(t.defense_types) do
		self.defIndex[d] = i
	end
	self.chains = {}
	self.nextChain = 0
end

function Combat:ArmorMultiplier(armor)
	if armor >= 0 then
		return 1 - (armor * ARMOR_FACTOR) / (1 + ARMOR_FACTOR * armor)
	end
	return 2 - math.pow(1 - ARMOR_FACTOR, -armor)
end

function Combat:TypeMultiplier(attackType, defenseType)
	local row = self.table[attackType] or self.table.normal
	return row[self.defIndex[defenseType] or 8] or 1
end

function Combat:CreepArmor(creep)
	local g = creep.gtd
	return (g.def.armor or 0) + (g.aura_armor or 0)
end

function Combat:IsCreep(unit)
	return unit and IsValidEntity(unit) and unit:IsAlive() and unit.gtd ~= nil and unit.gtd.creep == true
end

function Combat:CanHit(attack, unit)
	if not self:IsCreep(unit) then
		return false
	end
	if unit.gtd.def.air then
		return attack.air
	end
	return attack.ground
end

-- Deals one instance of WC3 damage from a tower. Returns the damage dealt.
function Combat:Damage(tower, target, raw, attackType, spell)
	if not self:IsCreep(target) or raw <= 0 then
		return 0
	end
	local def = target.gtd.def
	if def.immune and (attackType == "magic" or spell) then
		return 0   -- MagicImmunesResistDamage=1
	end
	local dmg = raw * self:TypeMultiplier(attackType, def.defense)
	if not spell then
		dmg = dmg * self:ArmorMultiplier(self:CreepArmor(target))   -- spell damage ignores armor
	end
	if dmg <= 0 then
		return 0
	end
	ApplyDamage({
		victim = target,
		attacker = tower,
		damage = dmg,
		damage_type = DAMAGE_TYPE_PURE,
		ability = tower.gtd_core,
		damage_flags = DOTA_DAMAGE_FLAG_NO_SPELL_AMPLIFICATION,
	})
	return dmg
end

function Combat:FindTarget(tower, attack, range)
	local units = FindUnitsInRadius(tower:GetTeamNumber(), tower:GetAbsOrigin(), nil, range,
		DOTA_UNIT_TARGET_TEAM_ENEMY, TARGET_TYPES, TARGET_FLAGS, FIND_CLOSEST, false)
	for _, u in ipairs(units) do
		if self:CanHit(attack, u) then
			return u
		end
	end
	return nil
end

function Combat:FindTargets(tower, attack, center, radius, exclude, max)
	local out = {}
	local units = FindUnitsInRadius(tower:GetTeamNumber(), center, nil, radius,
		DOTA_UNIT_TARGET_TEAM_ENEMY, TARGET_TYPES, TARGET_FLAGS, FIND_CLOSEST, false)
	for _, u in ipairs(units) do
		if #out >= max then
			break
		end
		if u ~= exclude and self:CanHit(attack, u) then
			out[#out + 1] = u
		end
	end
	return out
end

-- Raw (pre armor) damage of one attack of this tower.
function Combat:RollAttack(tower)
	local g = tower.gtd
	local at = g.def.attack
	local raw = at.base + Util.RollDice(at.dice, at.sides)
	local aura = g.aura or {}
	-- Damage aura (trueshot) and command aura add a percentage of the base damage; different buffs stack.
	raw = raw * (1 + (aura.damage or 0) + (aura.command or 0))
	return raw * (g.dmg_factor or 1)
end

-- Called from modifier_gtd_tower when the tower's (instant) engine attack fires: launches the WC3 missile
-- at the target, plus, for multishot towers (Barrage, "attack 10 units in 1 strike"), one more missile at
-- each of up to targets-1 other enemies in the area. Damage is dealt when a missile hits (OnAttackLanded).
function Combat:LaunchAttack(tower, target)
	local g = tower.gtd
	if not g or not g.def.attack or not self:CanHit(g.def.attack, target) then
		return
	end
	local def = g.def
	self:FireMissile(tower, target)
	if def.multishot and def.multishot.targets > 1 then
		local others = self:FindTargets(tower, def.attack, tower:GetAbsOrigin(), def.multishot.radius, target, def.multishot.targets - 1)
		for _, u in ipairs(others) do
			self:FireMissile(tower, u)
		end
	end
end

function Combat:FireMissile(tower, target)
	local at = tower.gtd.def.attack
	local origin = tower:GetAbsOrigin()
	ProjectileManager:CreateTrackingProjectile({
		Target = target,
		Source = tower,
		Ability = tower.gtd_core,
		EffectName = at.projectile,
		iMoveSpeed = at.missile_speed or 1200,
		vSourceLoc = origin + Vector(0, 0, 120),
		bDodgeable = false,
		bProvidesVision = false,
		ExtraData = { attack = 1 },
	})
end

-- Called when one of the tower's missiles hits (also multishot missiles).
function Combat:OnAttackLanded(tower, target)
	if not tower.gtd or not self:IsCreep(target) then
		return
	end
	local def = tower.gtd.def
	local at = def.attack
	local cdef = target.gtd.def

	if cdef.evasion and RandomFloat(0, 1) < cdef.evasion then
		SendOverheadEventMessage(nil, OVERHEAD_ALERT_MISS, target, 0, nil)
		return
	end

	local raw = self:RollAttack(tower)
	local crit = false
	if def.crits then
		for _, c in ipairs(def.crits) do
			if RandomFloat(0, 100) < c.chance then
				raw = raw * c.mult + (c.bonus or 0)
				crit = true
				break
			end
		end
	end

	local bashed = false
	if def.bash and not (def.bash.ground_only and cdef.air) and RandomFloat(0, 100) < def.bash.chance then
		raw = raw + def.bash.bonus
		bashed = true
	end

	local center = target:GetAbsOrigin()
	local dealt = self:Damage(tower, target, raw, at.type)
	if crit and dealt > 0 then
		SendOverheadEventMessage(nil, OVERHEAD_ALERT_CRITICAL, target, math.floor(dealt), nil)
	end

	if target:IsAlive() then
		if bashed then
			target:AddNewModifier(tower, tower.gtd_core, "modifier_stunned", { duration = def.bash.duration })
		end
		if def.poison and not cdef.immune and not cdef.mechanical then
			target:AddNewModifier(tower, tower.gtd_core, "modifier_gtd_poison", {
				duration = def.poison.duration, dps = def.poison.dps, slow = def.poison.slow,
			})
		end
		if def.frost and not cdef.immune then
			target:AddNewModifier(tower, tower.gtd_core, "modifier_gtd_frost", {
				duration = def.frost.duration, slow = def.frost.slow,
			})
		end
	end

	if at.splash then
		self:Splash(tower, center, raw, at, target)
	end
	if at.bounce and at.bounce.targets > 1 then
		self:StartBounce(tower, target, raw, at)
	end
end

-- WC3 missile splash: full damage inside "full" area, f_medium inside "medium", f_small inside "small".
function Combat:Splash(tower, center, raw, at, primary)
	local s = at.splash
	local radius = math.max(s.full or 0, s.medium or 0, s.small or 0)
	if radius <= 0 then
		return
	end
	local units = FindUnitsInRadius(tower:GetTeamNumber(), center, nil, radius,
		DOTA_UNIT_TARGET_TEAM_ENEMY, TARGET_TYPES, TARGET_FLAGS, FIND_ANY_ORDER, false)
	for _, u in ipairs(units) do
		if u ~= primary and self:IsCreep(u) then
			local air = u.gtd.def.air
			if (air and s.air) or (not air and s.ground) then
				local d = (u:GetAbsOrigin() - center):Length2D()
				local f = 0
				if d <= (s.full or 0) then
					f = 1
				elseif d <= (s.medium or 0) then
					f = s.f_medium or 0
				elseif d <= (s.small or 0) then
					f = s.f_small or 0
				end
				if f > 0 then
					self:Damage(tower, u, raw * f, at.type)
				end
			end
		end
	end
end

-- WC3 bouncing missile (Moon Glaive): jumps to the closest new target, losing `loss` damage per jump.
function Combat:StartBounce(tower, first, raw, at)
	local chain = { tower = tower, hit = { [first:entindex()] = true }, left = at.bounce.targets - 1, raw = raw }
	self:NextBounce(chain, first, first:GetAbsOrigin())
end

-- The glaive flies from the creep it just hit (fromUnit) to the closest creep not hit yet.
function Combat:NextBounce(chain, fromUnit, from)
	local tower = chain.tower
	if chain.left <= 0 or not IsValidEntity(tower) or not tower.gtd then
		return
	end
	local at = tower.gtd.def.attack
	local units = FindUnitsInRadius(tower:GetTeamNumber(), from, nil, at.bounce.range,
		DOTA_UNIT_TARGET_TEAM_ENEMY, TARGET_TYPES, TARGET_FLAGS, FIND_CLOSEST, false)
	for _, u in ipairs(units) do
		if not chain.hit[u:entindex()] and self:CanHit(at, u) then
			chain.hit[u:entindex()] = true
			chain.left = chain.left - 1
			chain.raw = chain.raw * (1 - (at.bounce.loss or 0))
			self.nextChain = self.nextChain + 1
			self.chains[self.nextChain] = chain
			local source = (fromUnit and IsValidEntity(fromUnit)) and fromUnit or tower
			ProjectileManager:CreateTrackingProjectile({
				Target = u,
				Source = source,
				Ability = tower.gtd_core,
				EffectName = at.projectile,
				iMoveSpeed = at.missile_speed or 1200,
				vSourceLoc = from + Vector(0, 0, 80),
				iSourceAttachment = DOTA_PROJECTILE_ATTACHMENT_HITLOCATION,
				bDodgeable = false,
				bProvidesVision = false,
				ExtraData = { chain = self.nextChain },
			})
			return
		end
	end
end

function Combat:OnBounceHit(target, chainId)
	local chain = self.chains[chainId]
	self.chains[chainId] = nil
	if not chain or not IsValidEntity(chain.tower) or not chain.tower.gtd then
		return
	end
	local at = chain.tower.gtd.def.attack
	local from
	if self:IsCreep(target) then
		from = target:GetAbsOrigin()
		local cdef = target.gtd.def
		if not (cdef.evasion and RandomFloat(0, 1) < cdef.evasion) then
			self:Damage(chain.tower, target, chain.raw, at.type)
		end
	elseif target and IsValidEntity(target) then
		from = target:GetAbsOrigin()
	end
	if from then
		self:NextBounce(chain, target, from)
	end
end

-- Damage filter: native tower attacks are cancelled, Combat applies the WC3 damage instead.
function GTD:DamageFilter(event)
	if event.entindex_inflictor_const == nil and event.entindex_attacker_const then
		local attacker = EntIndexToHScript(event.entindex_attacker_const)
		if attacker and attacker.gtd and attacker.gtd.tower then
			return false
		end
	end
	return true
end

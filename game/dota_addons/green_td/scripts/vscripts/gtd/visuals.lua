-- Paints the WC3 creep paths (unbuildable, walkable cells) on the flat Dota terrain with dirt sprites.
GTD.Visuals = GTD.Visuals or {}
local Visuals = GTD.Visuals

local BLOCK = 6          -- cells per sprite (6 x 32 = 192 units; the corridors are 12 cells wide)
local RADIUS = 300
Visuals.PATH_PARTICLE = "particles/gtd/path_dirt.vpcf"

function Visuals:DrawPaths()
	local G = GTD.Grid
	local count = 0
	for by = 0, G.h - 1, BLOCK do
		for bx = 0, G.w - 1, BLOCK do
			local path = 0
			for y = by, math.min(by + BLOCK, G.h) - 1 do
				for x = bx, math.min(bx + BLOCK, G.w) - 1 do
					if G:Kind(x, y) == "w" then
						path = path + 1
					end
				end
			end
			if path * 2 >= BLOCK * BLOCK then
				local pos = GetGroundPosition(Vector(G.ox + (bx + BLOCK / 2) * G.cell, G.oy + (by + BLOCK / 2) * G.cell, 0), nil)
				local fx = ParticleManager:CreateParticle(self.PATH_PARTICLE, PATTACH_WORLDORIGIN, nil)
				ParticleManager:SetParticleControl(fx, 0, pos)
				ParticleManager:SetParticleControl(fx, 1, Vector(RADIUS, 0, 0))
				count = count + 1
			end
		end
	end
	print("[GTD] path sprites: " .. count)
end

-- The decorations of the WC3 map (flowers, rocks, statues, columns, lanterns, fire and frost traps ...).
function Visuals:PlaceDoodads()
	local props, effects = 0, 0
	for _, d in ipairs(GTD.Data.map.doodads or {}) do
		local pos = GetGroundPosition(Vector(d.x, d.y, 0), nil)
		if d.model then
			local offsets = { Vector(0, 0, 0) }
			if d.pair then
				local rad = math.rad(d.yaw)
				local dir = Vector(math.cos(rad), math.sin(rad), 0) * d.pair
				offsets = { dir, -dir }
			end
			for _, off in ipairs(offsets) do
				local p = GetGroundPosition(pos + off, nil)
				local prop = SpawnEntityFromTableSynchronous("prop_dynamic", {
					model = d.model,
					origin = p,
					angles = Vector(0, d.yaw, 0),
				})
				if prop then
					prop:SetModelScale(d.scale or 1)
					props = props + 1
				end
			end
		elseif d.particle then
			local fx = ParticleManager:CreateParticle(d.particle, PATTACH_WORLDORIGIN, nil)
			ParticleManager:SetParticleControl(fx, 0, pos)
			effects = effects + 1
		end
	end
	print("[GTD] doodads: " .. props .. " props, " .. effects .. " effects")
end

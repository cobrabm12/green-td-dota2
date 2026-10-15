-- Build grid taken from the WC3 pathing map (war3map.wpm): 32x32 cells.
--   b = buildable, w = walkable but not buildable (creep paths), x = blocked
GTD.Grid = GTD.Grid or {}
local Grid = GTD.Grid

function Grid:Init()
	local g = GTD.Data.map.grid
	self.ox, self.oy = g.origin[1], g.origin[2]
	self.cell, self.w, self.h = g.cell, g.width, g.height
	self.rows = {}
	for i, rle in ipairs(g.rows) do
		local parts = {}
		for ch, n in rle:gmatch("(%a)(%d+)") do
			parts[#parts + 1] = string.rep(ch, tonumber(n))
		end
		self.rows[i - 1] = table.concat(parts)
	end
	self.occupied = {}
	print("[GTD] doodad cells blocked for building: " .. self:MarkDoodads())
end

function Grid:Kind(cx, cy)
	local row = self.rows[cy]
	if not row or cx < 0 or cx >= self.w then
		return "x"
	end
	return row:sub(cx + 1, cx + 1)
end

-- Snap a world position so that a footprint of `size` cells lines up with the 32x32 grid.
function Grid:Snap(pos, size)
	local c = self.cell
	local function snap(v, origin)
		if size % 2 == 0 then
			return math.floor((v - origin) / c + 0.5) * c + origin
		end
		return math.floor((v - origin) / c) * c + origin + c * 0.5
	end
	return Vector(snap(pos.x, self.ox), snap(pos.y, self.oy), 0)
end

-- WC3 cell of a world position
function Grid:Cell(x, y)
	return math.floor((x - self.ox) / self.cell), math.floor((y - self.oy) / self.cell)
end

function Grid:Cells(center, size)
	local half = size * self.cell * 0.5
	local x0 = math.floor((center.x - half - self.ox) / self.cell + 0.5)
	local y0 = math.floor((center.y - half - self.oy) / self.cell + 0.5)
	local cells = {}
	for dy = 0, size - 1 do
		for dx = 0, size - 1 do
			cells[#cells + 1] = { x0 + dx, y0 + dy }
		end
	end
	return cells
end

function Grid:CanBuild(center, size)
	for _, c in ipairs(self:Cells(center, size)) do
		local key = c[2] * self.w + c[1]
		if self:Kind(c[1], c[2]) ~= "b" or self.occupied[key] or self.doodads[key] then
			return false
		end
	end
	return true
end

-- WC3 doodads with a pathing texture (rocks, statues, columns, lanterns ...) make their cells unbuildable.
function Grid:MarkDoodads()
	self.doodads = {}
	local count = 0
	for _, d in ipairs(GTD.Data.map.doodads or {}) do
		if d.block then
			local w, h = d.block[1], d.block[2]
			local x0 = math.floor((d.x - w * self.cell * 0.5 - self.ox) / self.cell + 0.5)
			local y0 = math.floor((d.y - h * self.cell * 0.5 - self.oy) / self.cell + 0.5)
			for dy = 0, h - 1 do
				for dx = 0, w - 1 do
					self.doodads[(y0 + dy) * self.w + (x0 + dx)] = true
					count = count + 1
				end
			end
		end
	end
	return count
end

function Grid:Occupy(center, size, owner)
	for _, c in ipairs(self:Cells(center, size)) do
		self.occupied[c[2] * self.w + c[1]] = owner
	end
	self:Block(center, size)
end

function Grid:Free(center, size)
	for _, c in ipairs(self:Cells(center, size)) do
		self.occupied[c[2] * self.w + c[1]] = nil
	end
	self:Unblock(center, size)
end

-- Ground pathing. In WC3 towers block creeps (they walk around them), and cliffs are not walkable.
-- Dota pathing uses 64x64 GridNav cells, blocked here with point_simple_obstruction entities.
local NAV = 64

local function NavKey(x, y)
	return math.floor(x / NAV) .. ":" .. math.floor(y / NAV)
end

function Grid:SpawnObstruction(x, y)
	local key = NavKey(x, y)
	self.obstructions = self.obstructions or {}
	local entry = self.obstructions[key]
	if entry then
		entry.refs = entry.refs + 1
		return
	end
	local origin = Vector(math.floor(x / NAV) * NAV + NAV / 2, math.floor(y / NAV) * NAV + NAV / 2, 0)
	origin = GetGroundPosition(origin, nil)
	local ent = SpawnEntityFromTableSynchronous("point_simple_obstruction", { origin = origin, block_fow = false })
	self.obstructions[key] = { ent = ent, refs = 1 }
end

function Grid:RemoveObstruction(x, y)
	local key = NavKey(x, y)
	local entry = self.obstructions and self.obstructions[key]
	if not entry then
		return
	end
	entry.refs = entry.refs - 1
	if entry.refs <= 0 then
		if entry.ent and IsValidEntity(entry.ent) then
			entry.ent:RemoveSelf()
		end
		self.obstructions[key] = nil
	end
end

-- Nav cells whose center lies inside the footprint.
function Grid:NavCells(center, size)
	local half = size * self.cell * 0.5
	local x0, x1 = center.x - half, center.x + half
	local y0, y1 = center.y - half, center.y + half
	local out = {}
	local gx = math.floor(x0 / NAV) * NAV + NAV / 2
	while gx < x1 do
		if gx >= x0 then
			local gy = math.floor(y0 / NAV) * NAV + NAV / 2
			while gy < y1 do
				if gy >= y0 then
					out[#out + 1] = { gx, gy }
				end
				gy = gy + NAV
			end
		end
		gx = gx + NAV
	end
	return out
end

function Grid:Block(center, size)
	for _, c in ipairs(self:NavCells(center, size)) do
		self:SpawnObstruction(c[1], c[2])
	end
end

function Grid:Unblock(center, size)
	for _, c in ipairs(self:NavCells(center, size)) do
		self:RemoveObstruction(c[1], c[2])
	end
end

-- Block every nav cell where at least half of the WC3 cells are unwalkable (cliffs, map border).
function Grid:BlockTerrain()
	local count = 0
	local per = NAV / self.cell
	for ny = 0, self.h / per - 1 do
		for nx = 0, self.w / per - 1 do
			local blocked = 0
			for dy = 0, per - 1 do
				for dx = 0, per - 1 do
					if self:Kind(nx * per + dx, ny * per + dy) == "x" then
						blocked = blocked + 1
					end
				end
			end
			if blocked * 2 >= per * per then
				self:SpawnObstruction(self.ox + nx * NAV + 1, self.oy + ny * NAV + 1)
				count = count + 1
			end
		end
	end
	print("[GTD] terrain obstructions: " .. count)
end

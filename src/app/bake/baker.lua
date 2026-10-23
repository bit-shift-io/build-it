-- The baker (docs/CONTEXT.md "Baker"): renders a block model, or a
-- blueprint's triangle mesh, through the world's projection for a view into
-- a transparent sprite, once per facing, view and bake scale. The only
-- place models become pixels in the world.
--
-- The CPU projects every vertex with src/game/projection.lua; the GPU only
-- depth-tests and lights (block_shader.glsl). Same projection as the world
-- camera, so the two never diverge.
local Model = require("src.game.blocks.model")
local Mesher = require("src.game.blocks.mesher")
local Projection = require("src.game.projection")
local Mesh = require("src.game.geometry.mesh")

local Baker = {}

local SHADER_PATH = "src/app/bake/block_shader.glsl"

-- The block shader's vertex layout, shared with the builder's live view.
-- LÖVE 12 vertex formats need an explicit location per attribute; the shader
-- declares the custom ones at the same locations
-- (docs/memory/love-12-mesh-vertex-format.md). A vertex is
--   { px, py, depth, r, g, b, a, nx, ny, nz, materialId, mx, my, mz,
--     variantId, textureScale, textureRotation }
-- with (mx, my, mz) its model-space position in cells, which the shader
-- patterns the material texture by, and Baker.texture(v)'s variant id,
-- scale and rotation (radians).
Baker.VERTEX_FORMAT = {
	{ name = "VertexPosition", format = "floatvec3", location = 0 },
	{ name = "VertexColor", format = "floatvec4", location = 2 },
	{ name = "VertexNormal", format = "floatvec3", location = 3 },
	{ name = "VertexMaterial", format = "float", location = 4 },
	{ name = "VertexModel", format = "floatvec3", location = 5 },
	{ name = "VertexTexture", format = "floatvec3", location = 6 },
}
local VERTEX_FORMAT = Baker.VERTEX_FORMAT

-- The shader's id per material (docs/CONTEXT.md "Material"); a cell with no
-- material is 0, untextured.
local MATERIAL_IDS = { plank = 1, stone = 2 }

-- The shader's material id for mesher vertex `v`.
function Baker.materialId(v)
	return v.material and assert(MATERIAL_IDS[v.material], "unknown material " .. v.material) or 0
end

-- The shader's id per texture variant of each material (config.materials;
-- docs/CONTEXT.md "Texture variant"). 0, for vertices with no texture (block
-- models' cells), is the material's plain pattern props have always had.
local VARIANT_IDS = {
	plank = { polished = 1, bark = 2, shingles = 3, logs = 4 },
	stone = { polished = 1, rough = 2, jagged = 3, brick = 4 },
}

-- The shader's texture attribute for vertex `v` (its texture: { variant,
-- scale, rotation in degrees }, or none): variant id, scale, rotation in
-- radians.
function Baker.texture(v)
	local t = v.texture
	if not t then
		return 0, 1, 0
	end
	local ids = assert(VARIANT_IDS[v.material], "unknown material " .. tostring(v.material))
	return assert(ids[t.variant], "unknown variant " .. tostring(t.variant)), t.scale, math.rad(t.rotation)
end

-- The colour vertex `v` draws in: a team slot's colour in `palette`
-- (src/game/palette.lua; the owner's), else its own r, g, b. With no palette
-- a slot keeps the colour the mesh drew it in.
function Baker.color(v, palette)
	local c = v.slot and palette and palette[v.slot]
	if c then
		return c[1], c[2], c[3]
	end
	return v.r, v.g, v.b
end

local DEPTH_FORMAT = "depth24"

-- Clip-space depth band the model's depth range maps into. LÖVE 12 takes
-- GL-style clip z in [-1, 1] on every backend; staying inside keeps the
-- nearest and farthest faces from clipping.
local NEAREST_Z, FARTHEST_Z = -0.9, 0.9

local shader = nil

local function blockShader()
	if not shader then
		shader = love.graphics.newShader(SHADER_PATH)
	end
	return shader
end

local function unit(v)
	local len = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
	return { v[1] / len, v[2] / len, v[3] / len }
end

-- The model's bounds in tiles (model-local).
local function tileBounds(model)
	local b, cpt = Model.bounds(model), model.cellsPerTile
	return {
		minX = b.minX / cpt,
		minY = b.minY / cpt,
		minZ = b.minZ / cpt,
		maxX = b.maxX / cpt,
		maxY = b.maxY / cpt,
		maxZ = b.maxZ / cpt,
	}
end

-- The nearest and farthest view depth over the bounds' 8 corners. Depth is
-- affine, so a box's extremes are at its corners.
local function depthRange(p, bounds)
	local nearest, farthest = -math.huge, math.huge
	for _, x in ipairs({ bounds.minX, bounds.maxX }) do
		for _, y in ipairs({ bounds.minY, bounds.maxY }) do
			for _, z in ipairs({ bounds.minZ, bounds.maxZ }) do
				local d = Projection.depth(p, x, y, z)
				nearest, farthest = math.max(nearest, d), math.min(farthest, d)
			end
		end
	end
	return nearest, farthest
end

-- Baker vertices for `triangles` (in tiles, Mesher's vertex format) seen
-- through `p` into `frame`, team slots in `palette`'s colours. The shader
-- patterns materials by model position in cells, `cellsPerTile` to a tile.
local function meshVertices(triangles, cellsPerTile, p, frame, bounds, palette)
	local nearest, farthest = depthRange(p, bounds)
	local span = math.max(nearest - farthest, 1e-9)

	local out = {}
	for i, v in ipairs(triangles) do
		local px, py = Projection.modelToSprite(p, frame, v.x, v.y, v.z)
		local t = (nearest - Projection.depth(p, v.x, v.y, v.z)) / span -- 0 nearest, 1 farthest
		local depth = NEAREST_Z + t * (FARTHEST_Z - NEAREST_Z)
		local c = cellsPerTile
		local variant, scale, rotation = Baker.texture(v)
		local r, g, b = Baker.color(v, palette)
		out[i] = { px, py, depth, r, g, b, 1, v.nx, v.ny, v.nz, Baker.materialId(v), v.x * c, v.y * c, v.z * c, variant, scale, rotation }
	end
	return out
end

-- The largest canvas side the GPU takes.
local function textureLimit()
	return love.graphics.getSystemLimits().texturesize
end

-- The projection and sprite frame for `bounds` at bake `scale`, shrunk
-- below that scale when the sprite would be wider or taller than the GPU's
-- largest texture (a big footprint). The frame carries its own pixels per
-- tile, so Projection.placeSprite draws a shrunk sprite at full size.
local function fit(bounds, config, scale, view)
	local p = Projection.new(config, scale, view)
	local frame = Projection.spriteFrame(p, bounds)
	local limit = textureLimit()
	local side = math.max(frame.width, frame.height)
	if side > limit then
		-- One pixel of slack for the frame's rounding out to whole pixels.
		p = Projection.new(config, scale * (limit - 2) / side, view)
		frame = Projection.spriteFrame(p, bounds)
	end
	return p, frame
end

-- Draws `triangles` (tiles) into a new sprite framed on `bounds`; the
-- sprite's footprint is width x depth tiles. Team slots draw in `palette`'s
-- colours (none: as the triangles carry them).
local function render(triangles, cellsPerTile, bounds, width, depth, config, scale, view, palette)
	local p, frame = fit(bounds, config, scale, view)
	local mesh = love.graphics.newMesh(VERTEX_FORMAT, meshVertices(triangles, cellsPerTile, p, frame, bounds, palette), "triangles", "static")

	local image = love.graphics.newCanvas(frame.width, frame.height)
	local depthCanvas = love.graphics.newCanvas(frame.width, frame.height, { format = DEPTH_FORMAT })
	local s = blockShader()
	s:send("lightDirection", unit(config.bake.lightDirection))
	s:send("ambient", config.bake.ambient)

	love.graphics.push("all")
	love.graphics.origin()
	love.graphics.setCanvas({ image, depthstencil = depthCanvas })
	love.graphics.clear(0, 0, 0, 0)
	love.graphics.setDepthMode("less", true)
	love.graphics.setShader(s)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(mesh)
	love.graphics.pop()

	depthCanvas:release()
	mesh:release()
	return { image = image, frame = frame, width = width, depth = depth }
end

-- Bakes `model` turned to `facing` (Model.FACINGS) at whole bake `scale`
-- (Projection.bakeScale) through `view` (a config.views entry; default 3/4
-- top-down). Returns a sprite:
--   { image = <Canvas>, frame = <Projection.spriteFrame>, width, depth }
-- width/depth are the turned footprint in tiles. Draw it with
-- Projection.placeSprite.
function Baker.bake(model, facing, config, scale, view)
	local turned = Model.rotate(model, facing)
	assert(#turned.cells > 0, "cannot bake an empty block model")
	local cpt = turned.cellsPerTile
	local triangles = {}
	for i, v in ipairs(Mesher.mesh(turned)) do
		triangles[i] = { x = v.x / cpt, y = v.y / cpt, z = v.z / cpt, nx = v.nx, ny = v.ny, nz = v.nz, r = v.r, g = v.g, b = v.b, material = v.material }
	end
	return render(triangles, cpt, tileBounds(turned), turned.width, turned.depth, config, scale, view)
end

-- Material patterns on a blueprint mesh run at the brick grid's scale.
local MESH_CELLS_PER_TILE = 4

-- Bakes triangle mesh `triangles` (a blueprint's: tiles, on a width x
-- depth footprint) turned to `facing`, like Baker.bake. No block model in
-- between. Vertices with a team slot take its colour in `palette` (the
-- owner's team palette, src/game/palette.lua), when given.
function Baker.bakeMesh(triangles, width, depth, facing, config, scale, view, palette)
	assert(#triangles > 0, "cannot bake an empty mesh")
	local turned, w, d = Mesh.turn(triangles, width, depth, facing)
	return render(turned, MESH_CELLS_PER_TILE, Mesh.bounds(turned), w, d, config, scale, view, palette)
end

return Baker

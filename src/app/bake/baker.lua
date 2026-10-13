-- The baker (docs/CONTEXT.md "Baker"): renders a block model through the
-- world's 3/4 projection into a transparent sprite, once per facing and bake
-- scale. The only place block models become pixels in the world.
--
-- The CPU projects every vertex with src/game/projection.lua; the GPU only
-- depth-tests and lights (block_shader.glsl). Same projection as the world
-- camera, so the two never diverge.
local Model = require("src.game.blocks.model")
local Mesher = require("src.game.blocks.mesher")
local Projection = require("src.game.projection")

local Baker = {}

local SHADER_PATH = "src/app/bake/block_shader.glsl"

-- The block shader's vertex layout, shared with the builder's live view.
-- LÖVE 12 vertex formats need an explicit location per attribute; the shader
-- declares the custom ones at the same locations
-- (docs/memory/love-12-mesh-vertex-format.md). A vertex is
--   { px, py, depth, r, g, b, a, nx, ny, nz, materialId, mx, my, mz }
-- with (mx, my, mz) its model-space position in cells, which the shader
-- patterns the material texture by.
Baker.VERTEX_FORMAT = {
	{ name = "VertexPosition", format = "floatvec3", location = 0 },
	{ name = "VertexColor", format = "floatvec4", location = 2 },
	{ name = "VertexNormal", format = "floatvec3", location = 3 },
	{ name = "VertexMaterial", format = "float", location = 4 },
	{ name = "VertexModel", format = "floatvec3", location = 5 },
}
local VERTEX_FORMAT = Baker.VERTEX_FORMAT

-- The shader's id per material (config.builder.materials); a cell with no
-- material is 0, untextured.
local MATERIAL_IDS = { plank = 1, stone = 2 }

-- The shader's material id for mesher vertex `v`.
function Baker.materialId(v)
	return v.material and assert(MATERIAL_IDS[v.material], "unknown material " .. v.material) or 0
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

local function meshVertices(model, p, frame, bounds)
	local cpt = model.cellsPerTile
	local farthest = Projection.depth(p, 0, bounds.minY, bounds.minZ)
	local nearest = Projection.depth(p, 0, bounds.maxY, bounds.maxZ)
	local span = math.max(nearest - farthest, 1e-9)

	local out = {}
	for i, v in ipairs(Mesher.mesh(model)) do
		local x, y, z = v.x / cpt, v.y / cpt, v.z / cpt
		local px, py = Projection.modelToSprite(p, frame, x, y, z)
		local t = (nearest - Projection.depth(p, x, y, z)) / span -- 0 nearest, 1 farthest
		local depth = NEAREST_Z + t * (FARTHEST_Z - NEAREST_Z)
		out[i] = { px, py, depth, v.r, v.g, v.b, 1, v.nx, v.ny, v.nz, Baker.materialId(v), v.x, v.y, v.z }
	end
	return out
end

-- Bakes `model` turned to `facing` (Model.FACINGS) at whole bake `scale`
-- (Projection.bakeScale). Returns a sprite:
--   { image = <Canvas>, frame = <Projection.spriteFrame>, width, depth }
-- width/depth are the turned footprint in tiles. Draw it with
-- Projection.placeSprite.
function Baker.bake(model, facing, config, scale)
	local turned = Model.rotate(model, facing)
	assert(#turned.cells > 0, "cannot bake an empty block model")
	local p = Projection.new(config, scale)
	local bounds = tileBounds(turned)
	local frame = Projection.spriteFrame(p, bounds)
	local mesh = love.graphics.newMesh(VERTEX_FORMAT, meshVertices(turned, p, frame, bounds), "triangles", "static")

	local image = love.graphics.newCanvas(frame.width, frame.height)
	local depth = love.graphics.newCanvas(frame.width, frame.height, { format = DEPTH_FORMAT })
	local s = blockShader()
	s:send("lightDirection", unit(config.bake.lightDirection))
	s:send("ambient", config.bake.ambient)

	love.graphics.push("all")
	love.graphics.origin()
	love.graphics.setCanvas({ image, depthstencil = depth })
	love.graphics.clear(0, 0, 0, 0)
	love.graphics.setDepthMode("less", true)
	love.graphics.setShader(s)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(mesh)
	love.graphics.pop()

	depth:release()
	mesh:release()
	return { image = image, frame = frame, width = turned.width, depth = turned.depth }
end

return Baker

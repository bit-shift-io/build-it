-- Deterministic seeded RNG. A simple LCG (Numerical Recipes constants)
-- rather than math.random: LuaJIT gives no cross-platform guarantee for
-- math.random's algorithm, so the same seed could produce a different
-- sequence on another machine. Here the sequence is fixed by this module's
-- own arithmetic, so the same seed gives the same world everywhere.
-- Pure -- no `love.*` (docs/ARCHITECTURE.md "Layers").
local Rng = {}

-- Numerical Recipes' 32-bit LCG constants.
local MULTIPLIER = 1664525
local INCREMENT = 1013904223
local MODULUS = 4294967296 -- 2^32

-- Returns a new generator seeded with `seed` (any number; non-integers and
-- negatives are folded into range via modulus).
function Rng.new(seed)
	seed = math.floor(tonumber(seed) or 0)
	local state = seed % MODULUS
	if state < 0 then
		state = state + MODULUS
	end

	local rng = { state = state }

	-- Advances the generator and returns a float in [0, 1).
	function rng:next()
		self.state = (self.state * MULTIPLIER + INCREMENT) % MODULUS
		return self.state / MODULUS
	end

	-- A float uniformly distributed in [min, max).
	function rng:range(min, max)
		return min + self:next() * (max - min)
	end

	-- An integer uniformly distributed in [min, max] (inclusive both ends).
	function rng:int(min, max)
		return math.floor(self:range(min, max + 1))
	end

	return rng
end

-- a * b mod 2^32 for 32-bit a, b, split so no product passes 2^53 and loses
-- precision as a double.
local function mul32(a, b)
	local high, low = math.floor(a / 65536), a % 65536
	return ((high * b % 65536) * 65536 + low * b) % MODULUS
end

-- Folds the high bits into the low ones (an add-shift: no bit library, so
-- this runs under any Lua).
local function fold(h, shift)
	return (h + math.floor(h / shift)) % MODULUS
end

-- A 32-bit seed from any parts (strings or numbers), e.g. Rng.hash("tree", 3).
-- Use it to derive independent streams: an LCG seeded with neighbouring
-- integers gives near-identical first draws, a hashed seed does not.
-- FNV-1a-style over the parts' bytes (add in place of xor), then a
-- murmur3-style finaliser.
function Rng.hash(...)
	local h = 2166136261
	for i = 1, select("#", ...) do
		local s = tostring((select(i, ...)))
		for k = 1, #s do
			h = mul32((h + s:byte(k)) % MODULUS, 16777619)
		end
		h = mul32((h + 0x1f) % MODULUS, 16777619) -- part separator
	end
	h = mul32(fold(h, 65536), 0x85ebca6b)
	h = mul32(fold(h, 8192), 0xc2b2ae35)
	return fold(h, 65536)
end

return Rng

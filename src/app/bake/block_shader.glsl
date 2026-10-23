// Lights a block model, for the baker (src/app/bake/baker.lua) and the
// script builder's live view (src/app/render/script_builder_view.lua). The projection is
// done on the CPU: vertices arrive already in pixels (xy) with a depth in
// clip space (z, nearer is smaller), so this shader never duplicates the
// projection math.
//
// A brick's material shows as a procedural texture under its paint,
// patterned in model space (cells) so it sticks to the brick as the view
// turns: 1 plank, 2 stone. Material 0 is untextured. Each material draws
// one of its texture variants (Baker.texture, config.materials): plank 1
// polished, 2 bark, 3 shingles, 4 logs; stone 1 polished, 2 rough,
// 3 jagged, 4 brick. Variant 0 is the plain pattern block models' cells
// have always had (boards with grain; mottled blocks with mortar). The
// texture transform applies in model space before sampling: the position
// divided by the scale, the pattern turned about each face's normal by the
// rotation.

#ifdef VERTEX
// Custom attributes bind by location in LÖVE 12; 0 and 2 are VertexPosition
// and VertexColor (docs/memory/love-12-mesh-vertex-format.md).
layout (location = 3) in vec3 VertexNormal;
layout (location = 4) in float VertexMaterial;
layout (location = 5) in vec3 VertexModel;
layout (location = 6) in vec3 VertexTexture; // variant id, scale, rotation (radians)
out vec3 vNormal;
out vec3 vModel;
out float vMaterial; // the same at all three corners
out vec3 vTexture; // the same at all three corners

vec4 position(mat4 transform_projection, vec4 vertex_position) {
	vNormal = VertexNormal;
	vModel = VertexModel;
	vMaterial = VertexMaterial;
	vTexture = VertexTexture;
	vec4 p = transform_projection * vec4(vertex_position.xy, 0.0, 1.0);
	p.z = vertex_position.z;
	return p;
}
#endif

#ifdef PIXEL
in vec3 vNormal;
in vec3 vModel;
in float vMaterial;
in vec3 vTexture;
uniform vec3 lightDirection; // unit length, toward the light
uniform float ambient;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The face's own 2D coordinates, in cells: u runs horizontally, and on
// side faces v runs up.
vec2 faceCoords(vec3 n, vec3 p) {
	vec3 a = abs(n);
	if (a.z >= a.x && a.z >= a.y) return p.xy;
	if (a.x >= a.y) return vec2(p.y, p.z);
	return vec2(p.x, p.z);
}

// Boards half a cell wide along u, each its own shade, with fine grain and
// dark seams between them.
float plank(vec2 uv) {
	float board = floor(uv.y * 2.0);
	float across = fract(uv.y * 2.0);
	float shade = 0.9 + 0.12 * hash(vec2(board, 7.0));
	float grain = 0.06 * sin(uv.x * 9.0 + 6.0 * noise(vec2(uv.x * 1.5, board * 3.1 + uv.y * 14.0)));
	float seam = smoothstep(0.0, 0.08, across) * smoothstep(1.0, 0.92, across);
	return (shade + grain) * mix(0.6, 1.0, seam);
}

// Blocks a cell wide and half a cell tall in running bond, mottled and
// speckled, with pale mortar joints.
float stone(vec2 uv) {
	float row = floor(uv.y * 2.0);
	vec2 b = vec2(uv.x + 0.5 * mod(row, 2.0), uv.y * 2.0);
	vec2 cell = floor(b);
	vec2 f = fract(b);
	float shade = 0.82 + 0.2 * hash(cell);
	float mottle = 0.14 * (noise(uv * 6.0) - 0.5) + 0.1 * (hash(floor(uv * 24.0)) - 0.5);
	float edge = min(min(f.x, 1.0 - f.x) * 0.5, min(f.y, 1.0 - f.y));
	float joint = smoothstep(0.02, 0.05, edge);
	return mix(1.15, shade + mottle, joint);
}

// Wide planed boards: even shades, faint grain, fine seams, a soft sheen.
float plankPolished(vec2 uv) {
	float board = floor(uv.y);
	float across = fract(uv.y);
	float shade = 0.97 + 0.06 * hash(vec2(board, 3.0));
	float grain = 0.025 * sin(uv.x * 5.0 + 3.0 * noise(vec2(uv.x * 0.8, board * 2.3 + uv.y * 6.0)));
	float seam = smoothstep(0.0, 0.03, across) * smoothstep(1.0, 0.97, across);
	float sheen = 0.06 * smoothstep(0.3, 0.7, across) * smoothstep(1.0, 0.7, across);
	return (shade + grain + sheen) * mix(0.7, 1.0, seam);
}

// Bark: narrow dark furrows running up the trunk between rough ridges.
float plankBark(vec2 uv) {
	float wander = 0.5 * noise(vec2(uv.y * 1.5, uv.x * 0.5));
	float ridge = noise(vec2(uv.x * 7.0 + wander * 3.0, uv.y * 0.9));
	float furrow = smoothstep(0.2, 0.45, ridge);
	float fleck = 0.12 * (noise(uv * 18.0) - 0.5);
	return mix(0.5, 0.95, furrow) + fleck;
}

// Shingles: staggered rows of short boards, each lapping the row below,
// darkest at its lower edge where it casts a shadow.
float plankShingles(vec2 uv) {
	float row = floor(uv.y * 1.25);
	vec2 b = vec2(uv.x * 1.6 + 0.5 * mod(row, 2.0), uv.y * 1.25);
	vec2 cell = floor(b);
	vec2 f = fract(b);
	float shade = 0.85 + 0.2 * hash(cell);
	float lap = mix(0.45, 1.05, smoothstep(0.0, 0.45, f.y));
	float gap = smoothstep(0.0, 0.04, f.x) * smoothstep(1.0, 0.96, f.x);
	float grain = 0.05 * sin(f.x * 3.0 + f.y * 40.0 + 4.0 * noise(b * 3.0));
	return (shade + grain) * lap * mix(0.45, 1.0, gap);
}

// Logs: round logs laid along u, rounded light-to-dark across each, with
// bark lines and dark gaps between them.
float plankLogs(vec2 uv) {
	float course = floor(uv.y);
	float across = fract(uv.y);
	float bulge = sin(across * 3.14159);
	float shade = 0.85 + 0.15 * hash(vec2(course, 11.0));
	float lines = 0.08 * sin(uv.x * 14.0 + 5.0 * noise(vec2(uv.x * 2.0, course * 5.0 + across * 4.0)));
	return (shade * mix(0.4, 1.05, pow(bulge, 0.6)) + lines) * mix(0.45, 1.0, smoothstep(0.0, 0.12, bulge));
}

// The nearest and second-nearest feature distances and the nearest's hash
// on a jittered grid (cellular noise).
vec3 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + vec2(19.0, 7.0)));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = hash(i + g + vec2(3.0, 41.0));
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d1, d2, id);
}

// Polished stone: large smooth slabs with soft veins and hairline joints.
float stonePolished(vec2 uv) {
	vec2 f = fract(uv);
	float shade = 1.0 + 0.08 * hash(floor(uv));
	float vein = 1.0 - smoothstep(0.0, 0.06, abs(noise(uv * 3.0) + 0.5 * noise(uv * 7.0) - 0.75));
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	return (shade - 0.12 * vein) * mix(0.75, 1.0, smoothstep(0.0, 0.02, edge));
}

// Rough stone: rubble of rounded, unevenly shaded stones in dark joints.
float stoneRough(vec2 uv) {
	vec3 c = cells(uv * 2.0 + 0.3 * vec2(noise(uv * 4.0), noise(uv * 4.0 + 9.0)));
	float joint = smoothstep(0.03, 0.12, c.y - c.x);
	float mottle = 0.18 * (noise(uv * 9.0) - 0.5) + 0.12 * (hash(floor(uv * 28.0)) - 0.5);
	float shade = 0.75 + 0.3 * c.z - 0.25 * c.x;
	return mix(0.45, shade + mottle, joint);
}

// Jagged stone: sharp angular facets, each lit at its own angle, split by
// dark cracks.
float stoneJagged(vec2 uv) {
	vec3 c = cells(uv * 1.5);
	float facet = 0.65 + 0.5 * c.z + 0.35 * (c.y - c.x) * (c.z - 0.5);
	float crack = smoothstep(0.0, 0.05, c.y - c.x);
	float speck = 0.1 * (hash(floor(uv * 32.0)) - 0.5);
	return mix(0.3, facet + speck, crack);
}

// Stone brick: even dressed bricks in running bond with thick pale mortar.
float stoneBrick(vec2 uv) {
	float row = floor(uv.y * 2.5);
	vec2 b = vec2(uv.x * 1.25 + 0.5 * mod(row, 2.0), uv.y * 2.5);
	vec2 cell = floor(b);
	vec2 f = fract(b);
	float shade = 0.82 + 0.18 * hash(cell);
	float mottle = 0.1 * (noise(uv * 10.0) - 0.5) + 0.06 * (hash(floor(uv * 30.0)) - 0.5);
	float edge = min(min(f.x, 1.0 - f.x) * 0.5, min(f.y, 1.0 - f.y));
	return mix(1.2, shade + mottle, smoothstep(0.04, 0.07, edge));
}

// The texture of material `material`, variant `variant`, at face coords uv.
float pattern(float material, float variant, vec2 uv) {
	if (material < 1.5) {
		if (variant < 0.5) return plank(uv);
		if (variant < 1.5) return plankPolished(uv);
		if (variant < 2.5) return plankBark(uv);
		if (variant < 3.5) return plankShingles(uv);
		return plankLogs(uv);
	}
	if (variant < 0.5) return stone(uv);
	if (variant < 1.5) return stonePolished(uv);
	if (variant < 2.5) return stoneRough(uv);
	if (variant < 3.5) return stoneJagged(uv);
	return stoneBrick(uv);
}

vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screencoord) {
	vec3 n = normalize(vNormal);
	vec3 base = color.rgb;
	if (vMaterial > 0.5) {
		vec2 uv = faceCoords(n, vModel / vTexture.y);
		float c = cos(vTexture.z);
		float s = sin(vTexture.z);
		uv = vec2(c * uv.x - s * uv.y, s * uv.x + c * uv.y);
		float t = pattern(vMaterial, vTexture.x, uv);
		// Scaled, plus a little added, so the pattern shows on dark paint too.
		base = clamp(base * t + (t - 1.0) * 0.25, 0.0, 1.0);
	}
	float diffuse = max(dot(n, lightDirection), 0.0);
	return vec4(base * (ambient + (1.0 - ambient) * diffuse), color.a);
}
#endif

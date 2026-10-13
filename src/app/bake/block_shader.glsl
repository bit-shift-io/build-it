// Lights a block model, for the baker (src/app/bake/baker.lua) and the
// builder's live view (src/app/render/builder_view.lua). The projection is
// done on the CPU: vertices arrive already in pixels (xy) with a depth in
// clip space (z, nearer is smaller), so this shader never duplicates the
// projection math.
//
// A brick's material shows as a procedural texture under its paint,
// patterned in model space (cells) so it sticks to the brick as the view
// turns: 1 plank (boards with grain), 2 stone (mottled blocks with mortar).
// Material 0 is untextured -- props render exactly as before.

#ifdef VERTEX
// Custom attributes bind by location in LÖVE 12; 0 and 2 are VertexPosition
// and VertexColor (docs/memory/love-12-mesh-vertex-format.md).
layout (location = 3) in vec3 VertexNormal;
layout (location = 4) in float VertexMaterial;
layout (location = 5) in vec3 VertexModel;
out vec3 vNormal;
out vec3 vModel;
out float vMaterial; // the same at all three corners

vec4 position(mat4 transform_projection, vec4 vertex_position) {
	vNormal = VertexNormal;
	vModel = VertexModel;
	vMaterial = VertexMaterial;
	vec4 p = transform_projection * vec4(vertex_position.xy, 0.0, 1.0);
	p.z = vertex_position.z;
	return p;
}
#endif

#ifdef PIXEL
in vec3 vNormal;
in vec3 vModel;
in float vMaterial;
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

vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screencoord) {
	vec3 n = normalize(vNormal);
	vec3 base = color.rgb;
	if (vMaterial > 0.5) {
		vec2 uv = faceCoords(n, vModel);
		float t = vMaterial < 1.5 ? plank(uv) : stone(uv);
		// Scaled, plus a little added, so the pattern shows on dark paint too.
		base = clamp(base * t + (t - 1.0) * 0.25, 0.0, 1.0);
	}
	float diffuse = max(dot(n, lightDirection), 0.0);
	return vec4(base * (ambient + (1.0 - ambient) * diffuse), color.a);
}
#endif

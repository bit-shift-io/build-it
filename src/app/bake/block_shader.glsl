// Lights a baked block model (src/app/bake/baker.lua). The projection itself
// is done on the CPU by src/game/projection.lua: vertices arrive already in
// sprite pixels (xy) with a depth in clip space (z, nearer is smaller), so
// this shader never duplicates the projection math.

#ifdef VERTEX
// Custom attributes bind by location in LÖVE 12; 0 and 2 are VertexPosition
// and VertexColor (docs/memory/love-12-mesh-vertex-format.md).
layout (location = 3) in vec3 VertexNormal;
out vec3 vNormal;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
	vNormal = VertexNormal;
	vec4 p = transform_projection * vec4(vertex_position.xy, 0.0, 1.0);
	p.z = vertex_position.z;
	return p;
}
#endif

#ifdef PIXEL
in vec3 vNormal;
uniform vec3 lightDirection; // unit length, toward the light
uniform float ambient;

vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screencoord) {
	float diffuse = max(dot(normalize(vNormal), lightDirection), 0.0);
	return vec4(color.rgb * (ambient + (1.0 - ambient) * diffuse), color.a);
}
#endif

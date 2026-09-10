// Triplanar measurement grid.
//
// world space  → terrain: grid is fixed to the world, so speed and slip read against it.
// object space → car + wheels: grid is fixed to the part, so body roll/pitch and wheel
//                spin read on the part itself. (A world-space grid on a moving body just
//                swims across it and reads as nothing.)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.32, 0.36, 0.34);
uniform vec3 line_color : source_color = vec3(0.75, 0.78, 0.76);
uniform vec3 major_color : source_color = vec3(0.95, 0.95, 0.92);
uniform float grid_size = 1.0;            // metres per minor cell
uniform int major_every = 10;             // minor cells per major cell
uniform float line_width : hint_range(0.0, 0.5) = 0.04;   // fraction of a minor cell
uniform float major_width : hint_range(0.0, 0.5) = 0.025; // fraction of a major cell
uniform float minor_strength : hint_range(0.0, 1.0) = 0.55;
uniform bool object_space = false;
uniform float blend_sharpness = 8.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;

varying vec3 v_pos;
varying vec3 v_nrm;

void vertex() {
	if (object_space) {
		v_pos = VERTEX;
		v_nrm = NORMAL;
	} else {
		v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		v_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	}
}

// Anti-aliased grid lines in cell units; fades out where cells get smaller than a few pixels.
float grid(vec2 uv, float width) {
	vec2 fw = max(fwidth(uv), vec2(1e-5));
	vec2 dist = abs(fract(uv - 0.5) - 0.5);
	vec2 hw = vec2(width * 0.5);
	vec2 l = 1.0 - smoothstep(hw - fw, hw + fw, dist);
	float fade = 1.0 - smoothstep(0.15, 0.45, max(fw.x, fw.y));
	return max(l.x, l.y) * fade;
}

float triplanar_grid(vec3 p, vec3 w, float cell, float width) {
	vec3 q = p / cell;
	return grid(q.zy, width) * w.x + grid(q.xz, width) * w.y + grid(q.xy, width) * w.z;
}

void fragment() {
	vec3 w = pow(abs(normalize(v_nrm)), vec3(blend_sharpness));
	w /= max(w.x + w.y + w.z, 1e-5);

	float minor = triplanar_grid(v_pos, w, grid_size, line_width);
	float major = triplanar_grid(v_pos, w, grid_size * float(max(major_every, 1)), major_width);

	vec3 col = mix(base_color, line_color, minor * minor_strength);
	col = mix(col, major_color, major);
	ALBEDO = col;
	ROUGHNESS = roughness_value;
}

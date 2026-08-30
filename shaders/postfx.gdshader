shader_type canvas_item;
// Post "papier + encre", DOSE LEGERE : rapproche le rendu vecteur d'un rendu peint
// sans virer au filtre CRT.  Grain de papier + mouchetis + leger liseré d'encre
// sur les aretes + etalonnage chaud + vignette.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_tex, uv).rgb;

	// --- liseré d'encre discret sur les aretes ---
	float lx = luma(texture(screen_tex, uv + vec2(px.x, 0.0)).rgb)
	         - luma(texture(screen_tex, uv - vec2(px.x, 0.0)).rgb);
	float ly = luma(texture(screen_tex, uv + vec2(0.0, px.y)).rgb)
	         - luma(texture(screen_tex, uv - vec2(0.0, px.y)).rgb);
	float edge = clamp(length(vec2(lx, ly)) * 3.2, 0.0, 1.0);
	edge *= 0.4 + 0.5 * vnoise(uv / px * 0.13);
	// ne pas encrer les zones deja sombres (evite le scintillement sur le plateau)
	edge *= smoothstep(0.05, 0.28, luma(col));
	col = mix(col, vec3(0.06, 0.05, 0.045), edge * 0.16);

	// --- grain de papier (doux) ---
	vec2 pp = uv / px * 0.4;
	float paper = vnoise(pp) * 0.5 + vnoise(pp * 2.4) * 0.3 + vnoise(pp * 5.6) * 0.2;
	col *= 0.965 + paper * 0.07;

	// --- mouchetis couleur (les aplats respirent) ---
	float m = vnoise(uv * vec2(110.0, 74.0));
	col += (m - 0.5) * vec3(0.014, 0.010, 0.006);

	// --- etalonnage chaud + vignette peinte douce ---
	col *= vec3(1.03, 1.0, 0.955);
	vec2 vd = (uv - vec2(0.52, 0.52)) * vec2(1.15, 1.0);
	float vig = smoothstep(0.32, 0.90, length(vd));
	col = mix(col, col * vec3(0.60, 0.58, 0.57), vig * 0.34);

	float g = hash(uv * (floor(TIME * 9.0) + 1.0));
	col += (g - 0.5) * 0.006;

	COLOR = vec4(col, 1.0);
}

shader_type canvas_item;
// Fond du plateau (lane horizontale): degrade, teinte de la bande de farm (bas),
// blooms mouvants, vignette.

uniform float farm_edge = 0.778;   // BATTLE_ROWS / ROWS  (fraction du plateau)
uniform float top_edge = 0.138;    // HUD_H / hauteur vue

void fragment() {
	vec2 uv = UV;
	float y = clamp((uv.y - top_edge) / (1.0 - top_edge), 0.0, 1.0);

	// pierre / terre chaude et sombre : le plateau est pose dans un lieu, pas sur un panneau bleu
	vec3 top = vec3(0.072, 0.062, 0.056);
	vec3 bot = vec3(0.040, 0.033, 0.030);
	vec3 col = mix(top, bot, y);

	float farm_start = top_edge + (1.0 - top_edge) * farm_edge;
	float farm = smoothstep(farm_start - 0.006, farm_start + 0.006, uv.y);
	vec3 battle_col = col * vec3(1.04, 0.99, 0.93);
	vec3 farm_col = col * vec3(1.02, 1.04, 0.80);
	col = mix(battle_col, farm_col, farm);

	// lueurs chaudes lointaines (torches hors-champ)
	float t = TIME * 0.05;
	vec2 p1 = vec2(0.24 + sin(t) * 0.04, 0.30 + cos(t * 0.7) * 0.03);
	vec2 p2 = vec2(0.74 + cos(t * 0.9) * 0.04, 0.60 + sin(t * 1.1) * 0.03);
	col += vec3(0.055, 0.032, 0.014) * (1.0 - smoothstep(0.0, 0.44, distance(uv, p1)));
	col += vec3(0.040, 0.024, 0.010) * (1.0 - smoothstep(0.0, 0.42, distance(uv, p2)));

	// grain de pierre
	float n = fract(sin(dot(floor(uv * 640.0), vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * 0.012;

	float v = distance(uv, vec2(0.5, 0.5));
	col *= 1.0 - v * 0.62;

	COLOR = vec4(col, 1.0);
}

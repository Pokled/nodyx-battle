shader_type canvas_item;
// Flash blanc sur un sprite (degats). `flash` de 0 a 1.

uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.rgb = mix(c.rgb, vec3(1.0), flash * c.a);
	COLOR = c;
}

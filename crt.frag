#version 440
// CRT pass over the whole MDR screen: barrel curve, rounded tube corners, bloom, scanlines, vignette.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  float time;
  float strength;   // 0 flat, 0.5 subtle, 1 full
  vec2 resolution;
};
layout(binding = 1) uniform sampler2D source;

void main() {
  vec2 uv = qt_TexCoord0 * 2.0 - 1.0;
  uv += uv * (uv.yx * uv.yx) * vec2(0.035, 0.05) * strength;   // barrel curve
  vec2 tc = uv * 0.5 + 0.5;
  vec2 q = abs(uv) - (1.0 - vec2(0.045, 0.06) * strength);  // rounded tube edge
  float edge = length(max(q, 0.0)) - 0.03 * strength;
  if (edge > 0.0) { fragColor = vec4(0.0, 0.0, 0.0, 1.0) * qt_Opacity; return; }

  vec3 c = texture(source, tc).rgb;
  vec2 px = 1.0 / resolution;
  vec3 bloom = vec3(0.0);
  for (int i = 0; i < 8; i++) {
    float a = float(i) * 0.785398;
    bloom += texture(source, tc + vec2(cos(a), sin(a)) * px * 3.5).rgb;
    bloom += texture(source, tc + vec2(cos(a), sin(a)) * px * 8.0).rgb;
  }
  c += bloom / 16.0 * 0.55 * strength;
  c *= 1.0 - 0.07 * strength * (0.5 - 0.5 * sin(tc.y * resolution.y * 3.14159));   // scanlines, one per 2px
  c *= mix(1.0, smoothstep(1.75, 0.35, length(uv * vec2(0.85, 1.0))), strength);   // tube vignette
  if (strength > 0.0) c *= smoothstep(0.0, -0.025 * strength, edge);   // soft tube edge
  c *= 1.0 - 0.01 * strength * (0.5 + 0.5 * sin(time * 50.0));   // faint flicker
  fragColor = vec4(c, 1.0) * qt_Opacity;
}

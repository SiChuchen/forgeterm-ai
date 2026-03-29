#include <flutter/runtime_effect.glsl>

uniform vec2 u_resolution;
uniform float u_time;
uniform sampler2D u_texture;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / u_resolution.xy;
    
    // 1. Chromatic Aberration (色散)
    float offset = 0.001 * sin(u_time * 2.0);
    float r = texture(u_texture, uv + vec2(offset, 0.0)).r;
    float g = texture(u_texture, uv).g;
    float b = texture(u_texture, uv - vec2(offset, 0.0)).b;
    vec3 color = vec3(r, g, b);
    
    // 2. Scanline (扫描线)
    float scanline = sin(uv.y * u_resolution.y * 1.5 + u_time * 5.0) * 0.04;
    color -= scanline;
    
    // 3. Vignette (暗角)
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(uv, center);
    float vignette = smoothstep(0.8, 0.3, dist);
    color *= vignette;
    
    // 微弱闪烁
    float flicker = 0.98 + 0.02 * sin(u_time * 10.0);
    color *= flicker;
    
    fragColor = vec4(color, texture(u_texture, uv).a);
}

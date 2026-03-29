#include <flutter/runtime_effect.glsl>

uniform vec2 u_resolution;
uniform float u_time;
uniform vec4 u_color;

out vec4 fragColor;

// A simple fluid/aurora effect
void main() {
    vec2 uv = FlutterFragCoord().xy / u_resolution.xy;
    
    // Create animated waves
    vec2 p = uv * 3.0 - vec2(15.0);
    vec2 i = p;
    float c = 1.0;
    float inten = 0.05;

    for (int n = 0; n < 3; n++) {
        float t = u_time * (1.0 - (3.0 / float(n + 1)));
        i = p + vec2(cos(t - i.x) + sin(t + i.y), sin(t - i.y) + cos(t + i.x));
        c += 1.0 / length(vec2(p.x / (sin(i.x + t) / inten), p.y / (cos(i.y + t) / inten)));
    }
    c /= float(3);
    c = 1.17 - pow(c, 1.4);
    
    // Mix the base color with the fluid brightness pattern
    vec3 color = mix(u_color.rgb * 0.5, u_color.rgb, clamp(c, 0.0, 1.0));
    
    // Add some organic glow based on UV
    float glow = (0.5 + 0.5 * sin(uv.y * 3.14159 + u_time)) * 0.2;
    color += u_color.rgb * glow;
    
    fragColor = vec4(color, u_color.a);
}

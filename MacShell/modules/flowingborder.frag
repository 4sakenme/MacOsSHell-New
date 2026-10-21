#version 440

// Flowing Gradient Border Shader for TypeToSiri Pill Window
// Colors: Cyan (#00f0ff) -> Purple (#8a2be2) -> Magenta (#ff2d55) -> Amber (#ff9f0a)
// Features: Rounded Rectangle SDF, continuous flowing color gradient along perimeter, dynamic speed

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float u_time;
    float borderWidth;
    float borderRadius;
    float isThinking;
};

const float PI = 3.14159265358979323846;

// Apple Intelligence Palette
const vec3 COLOR_CYAN    = vec3(0.000, 0.941, 1.000); // #00F0FF
const vec3 COLOR_PURPLE  = vec3(0.541, 0.169, 0.886); // #8A2BE2
const vec3 COLOR_MAGENTA = vec3(1.000, 0.176, 0.333); // #FF2D55
const vec3 COLOR_AMBER   = vec3(1.000, 0.624, 0.039); // #FF9F0A

float sdRoundedBox(vec2 p, vec2 b, float r)
{
    vec2 q = abs(p) - b + vec2(r);
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void main()
{
    if (qt_Opacity <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 pos = (qt_TexCoord0 - 0.5) * itemSize;
    vec2 halfSize = (itemSize * 0.5) - vec2(1.0);
    float r = min(borderRadius, min(halfSize.x, halfSize.y));

    // Distance to outer edge
    float d = sdRoundedBox(pos, halfSize, r);

    // Compute stroke intensity using smoothstep
    float halfW = max(borderWidth * 0.5, 0.75);
    float stroke = 1.0 - smoothstep(0.0, 1.2, abs(d + halfW) - halfW);

    if (stroke <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // Normalized parameter along the pill circumference
    float aspect = halfSize.x / max(halfSize.y, 1.0);
    float angle = atan(pos.y * aspect, pos.x);
    float speed = isThinking > 0.5 ? 0.65 : 0.30;
    float phase = fract((angle / (2.0 * PI)) + (u_time * speed) + 0.5);

    // 4-Color gradient blend
    vec3 col;
    if (phase < 0.25) {
        col = mix(COLOR_CYAN, COLOR_PURPLE, phase / 0.25);
    } else if (phase < 0.50) {
        col = mix(COLOR_PURPLE, COLOR_MAGENTA, (phase - 0.25) / 0.25);
    } else if (phase < 0.75) {
        col = mix(COLOR_MAGENTA, COLOR_AMBER, (phase - 0.50) / 0.25);
    } else {
        col = mix(COLOR_AMBER, COLOR_CYAN, (phase - 0.75) / 0.25);
    }

    // Dynamic wave luminosity
    float shimmer = 1.0 + 0.25 * sin(phase * 4.0 * PI - u_time * 3.0);
    col *= shimmer;

    float alpha = stroke * (isThinking > 0.5 ? 0.95 : 0.75) * qt_Opacity;
    fragColor = vec4(col * alpha, alpha);
}

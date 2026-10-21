#version 440

// Apple Intelligence Siri Edge Glow Wave Fragment Shader
// Features: Signed Distance Field (SDF) rounded screen boundary,
// 4-color chromatic fluid sweep (Cyan -> Purple -> Magenta -> Orange),
// multi-frequency sin ripple waves, and dynamic audio-reactive breathing.
// Compile: /usr/lib/qt6/bin/qsb --qt6 -o siriedgeglow.frag.qsb siriedgeglow.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;       // screen dimension in logical px (e.g. 1920x1080)
    float u_time;        // running animation time in seconds
    float screenRadius;  // corner radius of screen bezel in px (e.g. 24.0)
    float glowWidth;     // nominal width of edge glow in px (e.g. 32.0)
    float audioLevel;    // 0.0 to 1.0 audio reactivity level
    float animProgress;  // 0.0 to 1.0 fade in/out
};

const float PI = 3.14159265358979323846;

// Signed distance to a rounded box
float sdRoundedBox(vec2 p, vec2 b, float r)
{
    vec2 q = abs(p) - b + vec2(r);
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void main()
{
    if (animProgress <= 0.001 || qt_Opacity <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 p = qt_TexCoord0 * itemSize;
    vec2 halfSize = itemSize * 0.5;
    vec2 posFromCenter = p - halfSize;

    // Distance to screen boundary with rounded corners (d == 0 at screen edge, < 0 inside)
    float d = sdRoundedBox(posFromCenter, halfSize, screenRadius);
    float inwardDist = -d;

    // Discard outside pixels or deep interior pixels where glow is imperceptible
    float maxReach = glowWidth * (1.8 + audioLevel * 1.5);
    if (inwardDist < 0.0 || inwardDist > maxReach) {
        fragColor = vec4(0.0);
        return;
    }

    // Polar angle around the screen center [-PI, PI]
    float angle = atan(posFromCenter.y, posFromCenter.x);

    // Multi-frequency wave undulation along perimeter
    float wave1 = sin(u_time * 2.8 + angle * 4.0) * 0.32;
    float wave2 = sin(u_time * 4.4 - angle * 7.0) * 0.22;
    float wave3 = cos(u_time * 1.8 + (qt_TexCoord0.x + qt_TexCoord0.y) * 10.0) * 0.18;
    float wave = wave1 + wave2 + wave3;

    // Dynamic wave-modulated glow width
    float effectiveWidth = glowWidth * (1.0 + audioLevel * 1.35 + wave * 0.40);

    // 1. Crisp luminous edge line right at the perimeter
    float edgeLine = exp(-inwardDist / 1.8) * 0.95;

    // 2. Soft volumetric chromatic aura spreading inward
    float auraDist = inwardDist / max(effectiveWidth, 1.0);
    float aura = exp(-auraDist * 1.8) * (0.85 + 0.30 * sin(u_time * 3.0 + wave));

    // Combined luminance
    float intensity = (edgeLine + aura) * animProgress;
    if (intensity <= 0.002) {
        fragColor = vec4(0.0);
        return;
    }

    // Apple Intelligence Signature 4-Color Palette:
    // Cyan (#00f0ff), Purple (#9b51e0), Magenta (#ff2d55), Orange (#ff9500)
    vec3 colCyan    = vec3(0.000, 0.941, 1.000); // #00F0FF
    vec3 colPurple  = vec3(0.608, 0.318, 0.878); // #9B51E0
    vec3 colMagenta = vec3(1.000, 0.176, 0.333); // #FF2D55
    vec3 colOrange  = vec3(1.000, 0.584, 0.000); // #FF9500

    // Smooth chromatic sweep around the boundary
    float t = fract((angle / (2.0 * PI)) + 0.5 + u_time * 0.10);
    vec3 glowColor;

    if (t < 0.25) {
        float k = smoothstep(0.0, 1.0, t / 0.25);
        glowColor = mix(colCyan, colPurple, k);
    } else if (t < 0.50) {
        float k = smoothstep(0.0, 1.0, (t - 0.25) / 0.25);
        glowColor = mix(colPurple, colMagenta, k);
    } else if (t < 0.75) {
        float k = smoothstep(0.0, 1.0, (t - 0.50) / 0.25);
        glowColor = mix(colMagenta, colOrange, k);
    } else {
        float k = smoothstep(0.0, 1.0, (t - 0.75) / 0.25);
        glowColor = mix(colOrange, colCyan, k);
    }

    // When speaking or audio level is high, brighten the core
    glowColor = mix(glowColor, vec3(1.0), audioLevel * 0.30 * edgeLine);

    fragColor = vec4(glowColor * intensity, intensity) * qt_Opacity;
}

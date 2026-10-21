#version 440

// Apple Intelligence Siri Edge Glow Wave Fragment Shader
// Features: Signed Distance Field (SDF) rounded screen boundary,
// Origin Bloom from Menu Bar Top-Right icon (0.96, 0.02),
// 4-color chromatic fluid sweep (Cyan -> Magenta -> Purple -> Amber),
// and dynamic audio-reactive breathing.
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
    vec2 u_origin;       // origin normalized coord (0.96, 0.02)
    float u_bloomProgress; // 0.0 to 1.0 radial bloom animation
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

    // ── ORIGIN RADIAL BLOOM (Top-Right Menu Bar) ──
    vec2 originPx = u_origin * itemSize;
    float distFromOrigin = length(p - originPx);
    float maxDist = length(vec2(0.0, itemSize.y) - originPx); // Max diagonal to bottom-left

    float bloomMask = 1.0;
    float bloomBoost = 0.0;

    if (u_bloomProgress < 0.999) {
        float currentRadius = u_bloomProgress * (maxDist * 1.08) + 10.0;
        // Smooth wavefront expansion
        bloomMask = 1.0 - smoothstep(currentRadius - (glowWidth * 3.5), currentRadius, distFromOrigin);
        // Bright crest on wavefront
        float waveFront = exp(-pow(distFromOrigin - currentRadius, 2.0) / (glowWidth * glowWidth * 5.0));
        bloomBoost = waveFront * 1.6;
    }

    if (bloomMask <= 0.001 && bloomBoost <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // ── CHROMATIC APPLE INTELLIGENCE GRADIENT SWEEP ──
    // Perimeter angle along screen bezel
    float angle = atan(posFromCenter.y, posFromCenter.x);
    float colorPhase = fract((angle / (2.0 * PI)) + (u_time * 0.18) + 0.5);

    // Apple Intelligence palette: Cyan (#00f0ff), Magenta (#ff2d55), Purple (#8a2be2), Amber (#ff9f0a)
    vec3 cCyan    = vec3(0.000, 0.941, 1.000);
    vec3 cMagenta = vec3(1.000, 0.176, 0.333);
    vec3 cPurple  = vec3(0.541, 0.169, 0.886);
    vec3 cAmber   = vec3(1.000, 0.624, 0.039);

    vec3 glowColor;
    if (colorPhase < 0.25) {
        glowColor = mix(cCyan, cMagenta, colorPhase / 0.25);
    } else if (colorPhase < 0.50) {
        glowColor = mix(cMagenta, cPurple, (colorPhase - 0.25) / 0.25);
    } else if (colorPhase < 0.75) {
        glowColor = mix(cPurple, cAmber, (colorPhase - 0.50) / 0.25);
    } else {
        glowColor = mix(cAmber, cCyan, (colorPhase - 0.75) / 0.25);
    }

    // ── EDGE WAVE UNDULATION & AUDIO BREATHING ──
    float wave1 = sin(angle * 7.0 + u_time * 3.8);
    float wave2 = sin(angle * 13.0 - u_time * 5.2);
    float waveDisp = (wave1 * 0.65 + wave2 * 0.35) * (glowWidth * (0.16 + audioLevel * 0.30));

    float effectiveDist = max(0.0, inwardDist + waveDisp);
    float baseThickness = glowWidth * (0.65 + audioLevel * 0.60);

    // Multi-layer Gaussian falloff for neon bloom glow
    float core = exp(-pow(effectiveDist / (baseThickness * 0.45), 2.0)) * 1.25;
    float halo = exp(-pow(effectiveDist / (baseThickness * 1.15), 1.8)) * 0.75;
    float aura = exp(-pow(effectiveDist / (baseThickness * 2.20), 1.5)) * 0.35;

    float intensity = (core + halo + aura) * animProgress * (bloomMask + bloomBoost);
    intensity = clamp(intensity, 0.0, 1.8);

    fragColor = vec4(glowColor * intensity, intensity) * qt_Opacity;
}

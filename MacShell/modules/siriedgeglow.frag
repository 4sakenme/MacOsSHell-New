#version 440

// Apple Intelligence Siri Edge Glow Wave Fragment Shader
// Features: Signed Distance Field (SDF) rounded screen boundary,
// Origin Bloom from Menu Bar Top-Right icon (0.96, 0.02),
// Edge Wave Reflection / Dampened Sinusoidal Bounce,
// Ultra-thin 16px refined bezel hugging profile,
// 4-color chromatic fluid sweep (Cyan -> Magenta -> Purple -> Amber).
// Compile: /usr/lib/qt6/bin/qsb --qt6 -o siriedgeglow.frag.qsb siriedgeglow.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;         // screen dimension in logical px (e.g. 1920x1080)
    float u_time;          // running animation time in seconds
    float screenRadius;    // corner radius of screen bezel in px (e.g. 24.0)
    float glowWidth;       // refined slim glow width (approx 16.0px)
    float audioLevel;      // 0.0 to 1.0 audio reactivity level
    float animProgress;    // 0.0 to 1.0 fade in/out
    vec2 u_origin;         // origin normalized coord (0.96, 0.02)
    float u_bloomProgress; // 0.0 to 1.0 radial bloom animation (750ms OutBack)
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

    // Refined slim boundary: only render within the slim bezel margin (~16px)
    float effectiveGlowW = glowWidth * (1.1 + audioLevel * 0.7);
    float maxReach = effectiveGlowW * 2.0;
    if (inwardDist < 0.0 || inwardDist > maxReach) {
        fragColor = vec4(0.0);
        return;
    }

    // ── ORIGIN BLOOM & EDGE WAVE REFLECTION (Top-Right Menu Bar) ──
    vec2 originPx = u_origin * itemSize;
    float distFromOrigin = length(p - originPx);
    float maxDist = length(vec2(0.0, itemSize.y) - originPx); // Max diagonal to bottom-left

    float bloomMask = 1.0;
    float bounceEcho = 0.0;

    if (u_bloomProgress < 0.999) {
        float currentRadius = u_bloomProgress * (maxDist * 1.08) + 12.0;

        // Wavefront progression
        bloomMask = 1.0 - smoothstep(currentRadius - (effectiveGlowW * 3.0), currentRadius, distFromOrigin);

        // Edge Wave Reflection: Dampened sine oscillation when wave hits the boundary
        float distDelta = currentRadius - distFromOrigin;
        if (distDelta >= 0.0) {
            // 1-2 subtle bounce reflections that dampen out quickly
            bounceEcho = sin(distDelta * 0.065) * exp(-distDelta * 0.012) * 1.25;
            bounceEcho = max(0.0, bounceEcho);
        }

        // Crest flash on the leading wavefront
        float waveFront = exp(-pow(distFromOrigin - currentRadius, 2.0) / (effectiveGlowW * effectiveGlowW * 3.5));
        bounceEcho += waveFront * 1.5;
    }

    if (bloomMask <= 0.001 && bounceEcho <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // ── CHROMATIC APPLE INTELLIGENCE GRADIENT SWEEP ──
    float angle = atan(posFromCenter.y, posFromCenter.x);
    float colorPhase = fract((angle / (2.0 * PI)) + (u_time * 0.12) + 0.5);

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

    // ── REFINED SLIM EDGE BREATHING ──
    float wave1 = sin(angle * 8.0 + u_time * 2.8);
    float wave2 = sin(angle * 14.0 - u_time * 3.6);
    float waveDisp = (wave1 * 0.65 + wave2 * 0.35) * (effectiveGlowW * (0.12 + audioLevel * 0.20));

    float effectiveDist = max(0.0, inwardDist + waveDisp);
    float baseThickness = effectiveGlowW * (0.48 + audioLevel * 0.35);

    // Slim Gaussian falloff for tight bezel hugging
    float core = exp(-pow(effectiveDist / (baseThickness * 0.40), 2.0)) * 1.35;
    float halo = exp(-pow(effectiveDist / (baseThickness * 0.95), 1.8)) * 0.70;
    float aura = exp(-pow(effectiveDist / (baseThickness * 1.80), 1.5)) * 0.25;

    float intensity = (core + halo + aura) * animProgress * (bloomMask + bounceEcho);
    intensity = clamp(intensity, 0.0, 1.8);

    fragColor = vec4(glowColor * intensity, intensity) * qt_Opacity;
}

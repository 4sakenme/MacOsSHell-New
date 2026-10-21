#version 440

// Apple Intelligence Siri Edge Glow Wave Fragment Shader
// Features:
// 1. Two-tier Wave Deformation Algorithm:
//    - Tier 1: Ambient Idle Flow (very slow, smooth, minimal 0.14 breathing undulation)
//    - Tier 2: Voice Micro-Ripples (high-frequency delicate water ripples when speaking)
//    - When silent (audioLevel == 0), edge automatically settles flat and serene
// 2. Intro Animation:
//    - Phase 1: Screen Flash / Vignette Mist Layer spreading from top-right origin (180ms)
//    - Phase 2: Settle to Edge: Mist fades out while energy converges into 45px-52px edge glow
// 3. Outro Animation:
//    - Border Shrink: Edge width collapses toward bezel into 0px
//    - Reverse Radial Collapse: Wave drains along perimeter back to top-right origin
//    - Smooth Opacity Fade (380ms)
// Compile: /usr/lib/qt6/bin/qsb --qt6 -o siriedgeglow.frag.qsb siriedgeglow.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;         // Screen dimension in logical px (e.g. 1920x1080)
    float u_time;          // Running animation time in seconds
    float screenRadius;    // Corner radius of screen bezel in px (e.g. 28.0)
    float glowWidth;       // Base glow width in px (~32.0px)
    float audioLevel;      // 0.0 to 1.0 smoothed audio reactivity level
    float animProgress;    // 0.0 to 1.0 fade in/out
    vec2 u_origin;         // Origin normalized coord (0.96, 0.02)
    float u_bloomProgress; // 0.0 to 1.0 perimeter bloom animation (forward in intro, reverse in outro)
    float u_introMist;     // 0.0 to 1.0 fullscreen vignette mist overlay during intro
    float u_shrinkFactor;  // 1.0 active, collapses to 0.0 during outro
};

const float PI = 3.14159265358979323846;
const float TWO_PI = 6.28318530717958647692;

// Signed distance to a rounded box (d == 0 at screen edge, < 0 inside)
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

    // ── ORIGIN COORDINATES & PERIMETER PARAMETERS ──
    vec2 originPx = u_origin * itemSize;
    vec2 originFromCenter = originPx - halfSize;
    float angleP = atan(posFromCenter.y, posFromCenter.x);
    float angleO = atan(originFromCenter.y, originFromCenter.x);

    float angleDiff = abs(angleP - angleO);
    if (angleDiff > PI) {
        angleDiff = TWO_PI - angleDiff;
    }
    float normDist = angleDiff / PI;

    // ── APPLE INTELLIGENCE CHROMATIC PALETTE ──
    vec3 cCyan    = vec3(0.000, 0.882, 1.000);
    vec3 cMagenta = vec3(1.000, 0.180, 0.330);
    vec3 cPurple  = vec3(0.624, 0.235, 0.941);
    vec3 cAmber   = vec3(1.000, 0.580, 0.000);

    // ── 1. INTRO PHASE 1: SCREEN FLASH / PURE NEON MIST (NO DARK VIGNETTE) ──
    vec4 mistOutput = vec4(0.0);
    if (u_introMist > 0.01) {
        float distFromOrigin = length(p - originPx);
        float maxDist = length(vec2(0.0, itemSize.y) - originPx);
        float mistRadius = max(40.0, u_introMist * maxDist * 1.25);

        float mistGrad = smoothstep(mistRadius, mistRadius * 0.15, distFromOrigin);
        float mistAlpha = mistGrad * u_introMist * 0.08;
        vec3 mistRgb = mix(cCyan, cMagenta, 0.5 + 0.5 * sin(u_time * 1.8 + distFromOrigin * 0.004));
        mistOutput = vec4(mistRgb * mistAlpha, mistAlpha);
    }

    // ── 2. TWO-TIER WAVE DEFORMATION ALGORITHM ──
    float d = sdRoundedBox(posFromCenter, halfSize, screenRadius);
    float inwardDist = -d;

    // Perimeter coordinate (0.0 to 1.0 around the 4 edges)
    float perimeterCoord = (angleP / TWO_PI) + 0.5;
    float pRad = perimeterCoord * TWO_PI;

    // TIER 1: Ambient Idle Flow (bồng bềnh uốn lượn rõ nét, ~0.26 undulation)
    float amb1 = sin(pRad * 5.0 - u_time * 1.3) * 0.65;
    float amb2 = cos(pRad * 11.0 + u_time * 1.0) * 0.35;
    float ambientWave = (amb1 + amb2) * 0.26;

    // TIER 2: Voice Micro-Ripples (delicate, high-frequency water ripples when speaking)
    float voiceRipple = sin(perimeterCoord * 45.0 - u_time * 6.0) 
                      * cos(perimeterCoord * 25.0 + u_time * 4.0);
    float voiceOffset = voiceRipple * clamp(audioLevel, 0.0, 1.0) * 0.18;

    // Settle Bloom: initial energy convergence (reaches ~48px-52px, then settles to base width)
    float settleBoost = (u_bloomProgress < 0.999) ? (0.50 * sin(u_bloomProgress * PI)) : 0.0;
    float dynamicBaseW = glowWidth * (1.0 + settleBoost);

    // Border Shrink in Outro: collapses cleanly to 0px
    dynamicBaseW *= clamp(u_shrinkFactor, 0.0, 1.0);

    // Dynamic width modulated cleanly by ambient breathing and voice micro-ripples
    float dynamicWidth = dynamicBaseW * max(0.35, (1.0 + ambientWave + voiceOffset));

    float maxReach = dynamicWidth * 2.2;
    if ((inwardDist < 0.0 || inwardDist > maxReach) && mistOutput.a <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // ── 3. PERIMETER BLOOM WAVE & REVERSE RADIAL COLLAPSE ──
    float wavePos = u_bloomProgress * 1.12;
    float bloomMask = 1.0 - smoothstep(wavePos - 0.20, wavePos, normDist);
    float bounceEcho = 0.0;

    if (u_bloomProgress < 0.999) {
        float distDelta = wavePos - normDist;
        if (distDelta >= 0.0) {
            bounceEcho = sin(distDelta * 24.0) * exp(-distDelta * 8.0) * 1.1;
            bounceEcho = max(0.0, bounceEcho);
        }
        float crest = exp(-pow((normDist - wavePos) * 18.0, 2.0)) * 1.6;
        bounceEcho += crest;
    }

    // ── 4. CHROMATIC SPECTRUM SLIDING ALONG WAVE FLOW ──
    float colorPhase = fract(perimeterCoord + ambientWave * 0.05 + u_time * 0.07);
    vec3 glowColor;
    if (colorPhase < 0.25) {
        glowColor = mix(cCyan, cMagenta, smoothstep(0.0, 1.0, colorPhase / 0.25));
    } else if (colorPhase < 0.50) {
        glowColor = mix(cMagenta, cPurple, smoothstep(0.0, 1.0, (colorPhase - 0.25) / 0.25));
    } else if (colorPhase < 0.75) {
        glowColor = mix(cPurple, cAmber, smoothstep(0.0, 1.0, (colorPhase - 0.50) / 0.25));
    } else {
        glowColor = mix(cAmber, cCyan, smoothstep(0.0, 1.0, (colorPhase - 0.75) / 0.25));
    }

    // ── 5. MULTI-TIER SOFT LUMINESCENT GLOW & VOICE GLEAM (BALANCED & ELEGANT) ──
    vec4 edgeOutput = vec4(0.0);
    if (inwardDist >= 0.0 && inwardDist <= maxReach && dynamicWidth > 0.5) {
        float normDistToEdge = inwardDist / dynamicWidth;
        float core = exp(-pow(normDistToEdge / 0.35, 2.0)) * 1.05;
        float halo = exp(-pow(normDistToEdge / 0.80, 1.6)) * 0.60;
        float aura = exp(-pow(normDistToEdge / 1.50, 1.2)) * 0.22;

        // Gentle voice gleam when speaking
        float crestGleam = 1.0 + max(0.0, voiceRipple) * clamp(audioLevel, 0.0, 1.0) * 0.35;
        float edgeIntensity = (core + halo + aura) * crestGleam * animProgress * (bloomMask + bounceEcho);

        // Activation spark near origin
        if (u_bloomProgress < 0.30) {
            float originProx = exp(-length(p - originPx) / 110.0);
            edgeIntensity += originProx * (1.0 - u_bloomProgress / 0.30) * 0.9;
        }

        // Feather outer bezel edge smoothly to prevent black edge halos
        float edgeFeather = smoothstep(0.0, 3.5, inwardDist);
        edgeIntensity *= edgeFeather;

        // Softened alpha for a refined, premium Apple aesthetic
        float alpha = clamp(edgeIntensity * 0.78, 0.0, 0.88) * qt_Opacity;
        vec3 whiteHighlight = vec3(1.0, 1.0, 1.0) * pow(core * 0.45, 2.6);
        vec3 pureNeonColor = glowColor + whiteHighlight;

        // Premultiplied alpha format: soft luminous neon without harsh saturation
        edgeOutput = vec4(pureNeonColor * alpha, alpha);
    }

    // Blend mist overlay with edge glow
    vec4 result = edgeOutput + mistOutput * (1.0 - edgeOutput.a);
    fragColor = result * qt_Opacity;
}

#version 440

// Apple Intelligence Siri Edge Glow Wave Fragment Shader
// Features:
// 1. Multi-layered Organic Wave Function along screen perimeter:
//    - High waveIntensity (0.70 - 0.95) for distinct undulating neon silk ribbons
//    - Audio-reactive amplitude & brightness surging with mic volume
//    - Color shifting smoothly slides along wave peaks
//    - Crest luminance boost at surging wave peaks
// 2. Perimeter Inception Shockwave:
//    - Dual-branch bloom originating from Menu Bar top-right icon (0.96, 0.02)
//    - Edge wave reflection bounce & crest flare
// 3. Multi-tier light diffusion: Crisp Core + Chromatic Fluid Halo + Soft Aura
// Compile: /usr/lib/qt6/bin/qsb --qt6 -o siriedgeglow.frag.qsb siriedgeglow.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;         // Screen dimension in logical px (e.g. 1920x1080)
    float u_time;          // Running animation time in seconds
    float screenRadius;    // Corner radius of screen bezel in px (e.g. 28.0)
    float glowWidth;       // Base glow width in px (~26.0px)
    float audioLevel;      // 0.0 to 1.0 audio reactivity level
    float animProgress;    // 0.0 to 1.0 fade in/out
    vec2 u_origin;         // Origin normalized coord (0.96, 0.02)
    float u_bloomProgress; // 0.0 to 1.0 perimeter bloom animation
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

    // Distance to screen boundary with rounded corners (d == 0 at edge, inwardDist > 0 inside)
    float d = sdRoundedBox(posFromCenter, halfSize, screenRadius);
    float inwardDist = -d;

    // ── 1. PERIMETER COORDINATE & MULTI-LAYERED ORGANIC WAVE FUNCTION ──
    float angleP = atan(posFromCenter.y, posFromCenter.x);
    // Continuous perimeter parameter from 0.0 to 1.0 around the 4 edges
    float perimeterCoord = (angleP / TWO_PI) + 0.5;
    float pRad = perimeterCoord * TWO_PI;

    // Multi-frequency harmonic sinusoidal waves for fluid ribbon motion
    float wave1 = sin(pRad * 10.0 - u_time * 2.2) * 0.50;
    float wave2 = cos(pRad * 22.0 + u_time * 1.6) * 0.30;
    float wave3 = sin(pRad * 5.0 + u_time * 0.8) * 0.35;
    float totalWave = wave1 + wave2 + wave3;

    // High wave intensity (~0.70 to 0.95 with audio) for bold ribbon peaks & troughs
    float waveIntensity = 0.72 + audioLevel * 0.28;

    // Inward burst expansion during activation bloom
    float burstBloom = (u_bloomProgress < 0.999) ? (0.55 * sin(u_bloomProgress * PI)) : 0.0;
    float baseGlowW = glowWidth * (1.0 + burstBloom + audioLevel * 0.40);

    // Dynamic wave thickness directly modulated by totalWave
    float dynamicWidth = baseGlowW * max(0.22, (1.0 + totalWave * waveIntensity));

    // Maximum reach covering Core, undulating Halo, and outer diffused Aura
    float maxReach = dynamicWidth * 2.4;
    if (inwardDist < 0.0 || inwardDist > maxReach) {
        fragColor = vec4(0.0);
        return;
    }

    // ── 2. PERIMETER INCEPTION PROPAGATION (Top-Right Menu Bar Origin) ──
    vec2 originPx = u_origin * itemSize;
    vec2 originFromCenter = originPx - halfSize;
    float angleO = atan(originFromCenter.y, originFromCenter.x);

    // Angular distance along perimeter (0.0 at origin, 1.0 at diagonally opposite corner)
    float angleDiff = abs(angleP - angleO);
    if (angleDiff > PI) {
        angleDiff = TWO_PI - angleDiff;
    }
    float normDist = angleDiff / PI;

    float bloomMask = 1.0;
    float bounceEcho = 0.0;

    if (u_bloomProgress < 0.999) {
        float wavePos = u_bloomProgress * 1.15;
        bloomMask = 1.0 - smoothstep(wavePos - 0.22, wavePos, normDist);

        float distDelta = wavePos - normDist;
        if (distDelta >= 0.0) {
            // Harmonic wave reflection bounce
            bounceEcho = sin(distDelta * 26.0) * exp(-distDelta * 7.5) * 1.4;
            bounceEcho = max(0.0, bounceEcho);
        }

        // Shockwave crest flare riding the wavefront
        float crest = exp(-pow((normDist - wavePos) * 18.0, 2.0)) * 2.2;
        bounceEcho += crest;
    }

    if (bloomMask <= 0.001 && bounceEcho <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // ── 3. CHROMATIC COLOR SPECTRUM SLIDING ALONG WAVE MOTION ──
    // Color phase moves with time and slides dynamically across wave contours
    float colorPhase = fract(perimeterCoord + totalWave * 0.08 + u_time * 0.09);

    // Apple Intelligence Official Palette:
    // Cyan (#00e1ff), Magenta (#ff2e54), Purple (#9f3cf0), Warm Amber (#ff9400)
    vec3 cCyan    = vec3(0.000, 0.882, 1.000);
    vec3 cMagenta = vec3(1.000, 0.180, 0.330);
    vec3 cPurple  = vec3(0.624, 0.235, 0.941);
    vec3 cAmber   = vec3(1.000, 0.580, 0.000);

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

    // ── 4. MULTI-TIER LIGHT EMISSION & WAVE PEAK CREST SURGE ──
    float normDistToEdge = inwardDist / dynamicWidth;

    // 1. Crisp Core: high-intensity vibrant rim right at the outer edge
    float core = exp(-pow(normDistToEdge / 0.30, 2.2)) * 1.45;

    // 2. Chromatic Halo: the undulating fluid body of the wave ribbon
    float halo = exp(-pow(normDistToEdge / 0.82, 1.7)) * 0.90;

    // 3. Atmospheric Soft Aura: deep volumetric diffusion into desktop
    float aura = exp(-pow(normDistToEdge / 1.65, 1.3)) * 0.45;

    // Crest Surge: wave peaks surge in brightness and flare with voice
    float crestSurge = 1.0 + max(0.0, totalWave) * 0.65 + audioLevel * 0.45;

    float baseIntensity = (core + halo + aura) * crestSurge * animProgress;
    float totalIntensity = baseIntensity * (bloomMask + bounceEcho);

    // Initial activation spark near origin
    if (u_bloomProgress < 0.35) {
        float originProx = exp(-length(p - originPx) / 130.0);
        totalIntensity += originProx * (1.0 - u_bloomProgress / 0.35) * 1.5;
    }

    totalIntensity = clamp(totalIntensity, 0.0, 2.8);

    // Specular iridescent highlight on wave crests
    vec3 whiteHighlight = vec3(1.0, 1.0, 1.0) * pow(core * 0.70, 2.0);
    vec3 finalRgb = glowColor * totalIntensity + whiteHighlight;

    float finalAlpha = clamp(totalIntensity * 0.88, 0.0, 1.0) * qt_Opacity;
    fragColor = vec4(finalRgb * finalAlpha, finalAlpha);
}

#version 440

// Apple Intelligence Siri Edge Glow Wave Fragment Shader
// Features:
// 1. Refined, gentle organic wave ribbon (reduced waveIntensity for subtle elegance):
//    - Controlled wave amplitude (0.35 - 0.55) so the glow hugs the bezel comfortably
//    - Does not jump excessively or occlude screen workspace
//    - Smooth chromatic shift (Cyan, Magenta, Purple, Amber) sliding along wave flow
// 2. Perimeter Inception Shockwave:
//    - Dual-branch bloom originating from Menu Bar top-right icon (0.96, 0.02)
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
    float glowWidth;       // Base glow width in px (~22.0px)
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

    // ── 1. GENTLE ORGANIC WAVE FUNCTION (REDUCED INTENSITY) ──
    float angleP = atan(posFromCenter.y, posFromCenter.x);
    float perimeterCoord = (angleP / TWO_PI) + 0.5;
    float pRad = perimeterCoord * TWO_PI;

    // Refined multi-harmonic waves with gentle amplitudes
    float wave1 = sin(pRad * 8.0 - u_time * 1.8) * 0.40;
    float wave2 = cos(pRad * 16.0 + u_time * 1.3) * 0.25;
    float wave3 = sin(pRad * 4.0 + u_time * 0.7) * 0.25;
    float totalWave = wave1 + wave2 + wave3;

    // Moderate, elegant wave intensity (~0.35, up to 0.55 when speaking)
    float waveIntensity = 0.35 + audioLevel * 0.20;

    // Soft inward expansion during activation bloom
    float burstBloom = (u_bloomProgress < 0.999) ? (0.35 * sin(u_bloomProgress * PI)) : 0.0;
    float baseGlowW = glowWidth * (1.0 + burstBloom + audioLevel * 0.30);

    // Subtle dynamic width that hugs the bezel without covering screen content
    float dynamicWidth = baseGlowW * max(0.40, (1.0 + totalWave * waveIntensity));

    // Boundary cutoff to prevent any unnecessary GPU texture fill
    float maxReach = dynamicWidth * 2.2;
    if (inwardDist < 0.0 || inwardDist > maxReach) {
        fragColor = vec4(0.0);
        return;
    }

    // ── 2. PERIMETER INCEPTION PROPAGATION (Top-Right Menu Bar Origin) ──
    vec2 originPx = u_origin * itemSize;
    vec2 originFromCenter = originPx - halfSize;
    float angleO = atan(originFromCenter.y, originFromCenter.x);

    float angleDiff = abs(angleP - angleO);
    if (angleDiff > PI) {
        angleDiff = TWO_PI - angleDiff;
    }
    float normDist = angleDiff / PI;

    float bloomMask = 1.0;
    float bounceEcho = 0.0;

    if (u_bloomProgress < 0.999) {
        float wavePos = u_bloomProgress * 1.12;
        bloomMask = 1.0 - smoothstep(wavePos - 0.20, wavePos, normDist);

        float distDelta = wavePos - normDist;
        if (distDelta >= 0.0) {
            bounceEcho = sin(distDelta * 24.0) * exp(-distDelta * 8.0) * 1.1;
            bounceEcho = max(0.0, bounceEcho);
        }

        float crest = exp(-pow((normDist - wavePos) * 18.0, 2.0)) * 1.8;
        bounceEcho += crest;
    }

    if (bloomMask <= 0.001 && bounceEcho <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // ── 3. CHROMATIC COLOR SPECTRUM SLIDING ALONG WAVE FLOW ──
    float colorPhase = fract(perimeterCoord + totalWave * 0.06 + u_time * 0.08);

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

    // ── 4. MULTI-TIER LIGHT EMISSION & SUBTLE CREST SURGE ──
    float normDistToEdge = inwardDist / dynamicWidth;

    float core = exp(-pow(normDistToEdge / 0.32, 2.2)) * 1.35;
    float halo = exp(-pow(normDistToEdge / 0.85, 1.7)) * 0.80;
    float aura = exp(-pow(normDistToEdge / 1.65, 1.3)) * 0.35;

    // Gentle crest surge
    float crestSurge = 1.0 + max(0.0, totalWave) * 0.35 + audioLevel * 0.30;

    float baseIntensity = (core + halo + aura) * crestSurge * animProgress;
    float totalIntensity = baseIntensity * (bloomMask + bounceEcho);

    // Initial activation spark near origin
    if (u_bloomProgress < 0.30) {
        float originProx = exp(-length(p - originPx) / 110.0);
        totalIntensity += originProx * (1.0 - u_bloomProgress / 0.30) * 1.2;
    }

    totalIntensity = clamp(totalIntensity, 0.0, 2.2);

    vec3 whiteHighlight = vec3(1.0, 1.0, 1.0) * pow(core * 0.65, 2.0);
    vec3 finalRgb = glowColor * totalIntensity + whiteHighlight;

    float finalAlpha = clamp(totalIntensity * 0.85, 0.0, 1.0) * qt_Opacity;
    fragColor = vec4(finalRgb * finalAlpha, finalAlpha);
}

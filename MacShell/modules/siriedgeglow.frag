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
    float u_voiceActive;   // 0.0 to 1.0 binary voice state (100ms smooth transition)
    float u_isThinking;    // 0.0 to 1.0 thinking / processing state (shimmer ripples)
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

    // Distance to screen boundary: d == 0 at screen edge, < 0 inside screen
    float d = sdRoundedBox(posFromCenter, halfSize, screenRadius);
    float inwardDist = -d;

    // Discard pixels strictly outside the screen bezel corner radius
    if (inwardDist < 0.0) {
        fragColor = vec4(0.0);
        return;
    }

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

    // ── 1. FULLSCREEN VIVID OCEAN WAVE BURST (FILL FULL MÀN HÌNH MƯỢT MÀ) ──
    vec4 shockwaveOutput = vec4(0.0);
    if (u_bloomProgress < 0.999 && animProgress > 0.01) {
        float distFromOrigin = length(p - originPx);
        float maxScreenDist = length(itemSize);

        // 1. Primary Ocean Wave front expanding across the display from origin
        float waveRadius = u_bloomProgress * maxScreenDist * 1.30;
        float waveDelta = distFromOrigin - waveRadius;

        // Leading crest (vành sóng chính bung mạnh mẽ)
        float leadingCrest = exp(-pow(waveDelta / 85.0, 2.0)) * 2.2;

        // Trailing ocean swells (các gợn sóng biển mềm mại nối tiếp ngọn sóng)
        float trailingSwells = 0.0;
        if (waveDelta < 0.0) {
            float swellOsc = sin(waveDelta * 0.045);
            trailingSwells = max(0.0, swellOsc) * exp(waveDelta / 280.0) * 1.3;
        }

        // Inner luminous wake fill across the screen
        float innerWake = smoothstep(waveRadius + 80.0, 0.0, distFromOrigin) * 0.40;

        // Total organic fluid wave field
        float totalWaves = leadingCrest + trailingSwells + innerWake;

        // Smooth dissipation over the 1500ms duration
        float burstEnvelope = sin(clamp(u_bloomProgress * 1.15, 0.0, 1.0) * PI);
        float shockIntensity = totalWaves * burstEnvelope * animProgress;

        // Saturated chromatic spectrum matching Apple Intelligence palette
        float angleOrigin = atan(p.y - originPx.y, p.x - originPx.x);
        float shockHue = fract(angleOrigin / TWO_PI + distFromOrigin * 0.0010 - u_time * 0.35);

        vec3 shockColor;
        if (shockHue < 0.25) {
            shockColor = mix(cCyan * 1.35, cMagenta * 1.40, shockHue / 0.25);
        } else if (shockHue < 0.50) {
            shockColor = mix(cMagenta * 1.40, cPurple * 1.35, (shockHue - 0.25) / 0.25);
        } else if (shockHue < 0.75) {
            shockColor = mix(cPurple * 1.35, cAmber * 1.30, (shockHue - 0.50) / 0.25);
        } else {
            shockColor = mix(cAmber * 1.30, cCyan * 1.35, (shockHue - 0.75) / 0.25);
        }

        // Luminous foam crest highlight along the wave peaks
        float crestHighlight = exp(-pow(waveDelta / 28.0, 2.0)) * 0.45;
        shockColor += vec3(1.0) * crestHighlight;

        // Clamped rich translucent alpha without dark clipping
        float shockAlpha = clamp(shockIntensity * 0.38, 0.0, 0.65) * qt_Opacity;
        shockwaveOutput = vec4(shockColor * shockAlpha, shockAlpha);
    }

    // ── 2. TWO-TIER WAVE DEFORMATION ALGORITHM ──
    // Perimeter coordinate (0.0 to 1.0 around the 4 edges)
    float perimeterCoord = (angleP / TWO_PI) + 0.5;
    float pRad = perimeterCoord * TWO_PI;

    // TIER 1: Ambient Idle Flow (minimal breathing ~0.20 when idle)
    float amb1 = sin(pRad * 5.0 - u_time * 1.3) * 0.65;
    float amb2 = cos(pRad * 11.0 + u_time * 1.0) * 0.35;
    float ambientWave = (amb1 + amb2) * 0.20;

    // TIER 2: Active Voice State Wave (giảm nhẹ độ cao ~0.50 cho sóng uốn lượn vừa vặn, thanh lịch)
    float voiceRip1 = sin(perimeterCoord * 28.0 - u_time * 4.2) * 0.55;
    float voiceRip2 = cos(perimeterCoord * 52.0 + u_time * 3.6) * 0.45;
    float voiceWave = (voiceRip1 + voiceRip2) * 0.50 * u_voiceActive;

    // TIER 3: Thinking / Processing Mode (bình thường, nhịp nhàng êm dịu, không bị giật hay quá dày)
    float thinkRip1 = sin(perimeterCoord * 32.0 - u_time * 2.8) * 0.55;
    float thinkRip2 = cos(perimeterCoord * 56.0 + u_time * 2.2) * 0.45;
    float thinkWave = (thinkRip1 + thinkRip2) * 0.32 * u_isThinking;

    // Combined perimeter wave displacement
    float totalWave = ambientWave * (1.0 - max(u_voiceActive, u_isThinking) * 0.3) + voiceWave + thinkWave;

    // Settle Bloom: initial energy convergence (reaches ~48px-52px, then settles to base width)
    float settleBoost = (u_bloomProgress < 0.999) ? (0.50 * sin(u_bloomProgress * PI)) : 0.0;
    
    // Dynamic width expansion when voice or thinking is active
    float stateBoost = 0.20 * u_voiceActive + 0.12 * u_isThinking;
    float dynamicBaseW = glowWidth * (1.0 + settleBoost + stateBoost);

    // Border Shrink in Outro: collapses cleanly to 0px
    dynamicBaseW *= clamp(u_shrinkFactor, 0.0, 1.0);

    // Dynamic width modulated cleanly by waves
    float dynamicWidth = dynamicBaseW * max(0.35, (1.0 + totalWave));

    float maxReach = dynamicWidth * 2.2;
    if ((inwardDist < 0.0 || inwardDist > maxReach) && shockwaveOutput.a <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // ── 3. IPHONE-STYLE VIVID TRAVELLING LINE PULSE & DISSIPATING BLOOM ──
    vec4 lineOutput = vec4(0.0);
    if (u_bloomProgress < 0.999 && animProgress > 0.01) {
        float sweepHead = u_bloomProgress * 1.25;
        float dHead = sweepHead - normDist;

        if (dHead >= 0.0 && dHead <= 0.45) {
            // High-intensity sharp traveling line hugging the border bezel
            float sharpLine = exp(-pow((inwardDist - 3.2) / 2.6, 2.0));
            float headPulse = exp(-pow(dHead / 0.045, 2.0)) * 2.8;

            // Rich expanding luminous wake behind the travelling line
            float wakeBloom = exp(-dHead * 7.0) * exp(-pow(inwardDist / (dynamicWidth * 1.3), 1.7)) * 1.6;

            // Dissipation factor: bursts strongly then fades out smoothly as progress completes
            float burstFactor = sin(clamp(u_bloomProgress * 1.15, 0.0, 1.0) * PI);
            float lineIntensity = (sharpLine * headPulse + wakeBloom) * burstFactor * animProgress;

            // Deep saturated Apple Intelligence colors (Electric Cyan, Vivid Magenta, Royal Purple)
            vec3 saturatedColor = mix(cMagenta * 1.4, cCyan * 1.3, 0.5 + 0.5 * sin(normDist * TWO_PI * 2.0 + u_time * 3.0));
            float lineAlpha = clamp(lineIntensity * 0.90, 0.0, 1.0) * qt_Opacity;

            lineOutput = vec4(saturatedColor * lineAlpha, lineAlpha);
        }
    }

    // ── 4. PERIMETER AMBIENT BLOOM MASK & REVERSE RADIAL COLLAPSE ──
    float wavePos = u_bloomProgress * 1.12;
    float bloomMask = 1.0 - smoothstep(wavePos - 0.20, wavePos, normDist);
    float bounceEcho = 0.0;

    if (u_bloomProgress < 0.999) {
        float distDelta = wavePos - normDist;
        if (distDelta >= 0.0) {
            bounceEcho = sin(distDelta * 24.0) * exp(-distDelta * 8.0) * 0.8;
            bounceEcho = max(0.0, bounceEcho);
        }
        float crest = exp(-pow((normDist - wavePos) * 18.0, 2.0)) * 1.2;
        bounceEcho += crest;
    }

    // ── 5. CHROMATIC SPECTRUM SLIDING ALONG WAVE FLOW ──
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

        // Voice & Thinking gleam boost
        float crestGleam = 1.0 + (0.55 * u_voiceActive) + (0.80 * u_isThinking);
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

    // Blend layers: base edge glow + saturated travelling beam + fullscreen vivid shockwave
    vec4 result = edgeOutput + lineOutput * (1.0 - edgeOutput.a * 0.35);
    result = result + shockwaveOutput * (1.0 - result.a * 0.5);
    fragColor = result * qt_Opacity;
}

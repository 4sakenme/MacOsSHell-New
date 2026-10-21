#version 440

// Apple Intelligence Siri Orb - Soft Fluid Plasma 3D Shader
// Colors: Cyan (#00f0ff), Magenta (#ff2d55), Purple (#8a2be2), Amber (#ff9f0a)
// Features: Soft Gaussian feathered edge, multi-layer fluid noise (NO CD ray artifacts),
// dynamic breathing with audioLevel and processing state.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float u_time;
    float u_audioLevel;
    float isProcessing;
};

// Apple Intelligence 4-color palette
const vec3 COLOR_CYAN    = vec3(0.000, 0.941, 1.000); // #00F0FF
const vec3 COLOR_MAGENTA = vec3(1.000, 0.176, 0.333); // #FF2D55
const vec3 COLOR_PURPLE  = vec3(0.541, 0.169, 0.886); // #8A2BE2
const vec3 COLOR_AMBER   = vec3(1.000, 0.624, 0.039); // #FF9F0A

void main()
{
    if (qt_Opacity <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // Normalized UV: [-1.0, 1.0] centered
    vec2 uv = (qt_TexCoord0 - 0.5) * 2.0;
    float r = length(uv);

    // Soft Gaussian feathered boundary (completely eliminates jagged or hard circular edge)
    float edgeSoftness = smoothstep(1.0, 0.72, r);
    if (edgeSoftness <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // Dynamic animation speed based on audio and processing
    float speed = 0.8 + isProcessing * 1.5 + u_audioLevel * 1.2;
    float t = u_time * speed;

    // 3D spherical depth projection
    float z = sqrt(max(0.0, 1.0 - r * r));
    vec3 p = vec3(uv.x, uv.y, z);

    // Multi-octave continuous 3D fluid turbulence (NO angular division / NO CD rays)
    float n1 = sin(p.x * 2.4 + t * 0.9) * cos(p.y * 2.4 + t * 0.7) + sin(p.z * 2.0 + t * 0.5);
    float n2 = sin(p.y * 3.6 - t * 1.1) * cos(p.z * 3.6 + t * 0.8) + cos(p.x * 3.0 - t * 0.6);
    float n3 = sin(p.z * 4.5 + t * 1.3) * cos(p.x * 4.5 + t * 1.0);

    // Soft continuous color weights
    float wCyan    = pow(max(0.0, sin(p.x * 1.6 + n1 * 0.7 + t * 0.6)), 1.5);
    float wMagenta = pow(max(0.0, cos(p.y * 1.6 + n2 * 0.7 - t * 0.5)), 1.5);
    float wPurple  = pow(max(0.0, sin(p.z * 1.6 + n3 * 0.7 + t * 0.7)), 1.5);
    float wAmber   = pow(max(0.0, cos(p.x * 1.4 - p.y * 1.4 + t * 0.4)), 1.5);

    float sumW = wCyan + wMagenta + wPurple + wAmber + 0.001;
    vec3 fluidColor = (COLOR_CYAN * wCyan + COLOR_MAGENTA * wMagenta + COLOR_PURPLE * wPurple + COLOR_AMBER * wAmber) / sumW;

    // Luminescence variation
    float lum = 0.85 + 0.35 * sin(n1 * 2.0 + t);
    fluidColor *= lum;

    // Soft Fresnel rim glow (glows gently at edges)
    float fresnel = pow(1.0 - z, 2.2);
    vec3 rimColor = mix(COLOR_CYAN, COLOR_MAGENTA, 0.5 + 0.5 * sin(t + p.x));
    fluidColor = mix(fluidColor, rimColor, fresnel * 0.45);

    // Breathing inner core highlight
    float coreRadius = 0.32 + u_audioLevel * 0.18 + isProcessing * 0.10;
    float coreGlow = exp(-r * r / max(coreRadius * coreRadius, 0.02));
    fluidColor += vec3(1.0, 1.0, 1.0) * (coreGlow * (0.35 + 0.25 * sin(t * 2.5)));

    // Outer bloom aura
    float outerAura = smoothstep(0.65, 0.95, r) * (0.2 + 0.15 * u_audioLevel);
    fluidColor += rimColor * outerAura;

    // Premultiplied alpha output with Gaussian softness
    float finalAlpha = edgeSoftness * qt_Opacity;
    fragColor = vec4(fluidColor * finalAlpha, finalAlpha);
}

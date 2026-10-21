#version 440

// Apple Intelligence Siri Orb - Ultra-Smooth Fluid Plasma 3D Shader
// Colors: Cyan (#00f0ff), Magenta (#ff2d55), Purple (#8a2be2), Amber (#ff9f0a)
// Features: Ultra-soft feathered boundary (smoothstep 1.0 -> 0.48),
// Gentle hypnotic slow plasma drift (reduced rotation speed when speaking),
// completely seamless continuous blend.
// Compile: /usr/lib/qt6/bin/qsb --qt6 -o siriorb.frag.qsb siriorb.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_audioLevel;
    float isProcessing;
};

// Official Apple Intelligence tones
const vec3 COLOR_CYAN    = vec3(0.000, 0.941, 1.000); // #00f0ff
const vec3 COLOR_MAGENTA = vec3(1.000, 0.176, 0.333); // #ff2d55
const vec3 COLOR_PURPLE  = vec3(0.541, 0.169, 0.886); // #8a2be2
const vec3 COLOR_AMBER   = vec3(1.000, 0.624, 0.039); // #ff9f0a

void main()
{
    if (qt_Opacity <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // Normalized UV: [-1.0, 1.0] centered
    vec2 uv = (qt_TexCoord0 - 0.5) * 2.0;
    float r = length(uv);

    // Ultra-soft feathered boundary: smooth fade starting deep from r=0.48 to 1.0
    float edgeSoftness = smoothstep(1.0, 0.48, r);
    if (edgeSoftness <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // Gentle, hypnotic fluid plasma drift (reduced rotation speed even when listening/speaking)
    float speed = 0.15 + isProcessing * 0.10 + u_audioLevel * 0.08;
    float t = u_time * speed;

    // 3D spherical depth projection
    float z = sqrt(max(0.0, 1.0 - r * r));
    vec3 p = vec3(uv.x, uv.y, z);

    // Multi-octave continuous 3D fluid turbulence (ultra-smooth drifting)
    float n1 = sin(p.x * 2.0 + t * 0.35) * cos(p.y * 2.0 + t * 0.25) + sin(p.z * 1.6 + t * 0.18);
    float n2 = sin(p.y * 2.8 - t * 0.38) * cos(p.z * 2.8 + t * 0.28) + cos(p.x * 2.4 - t * 0.22);
    float n3 = sin(p.z * 3.6 + t * 0.42) * cos(p.x * 3.6 + t * 0.32);

    // Soft continuous color weights without sharp angular boundaries
    float wCyan    = pow(max(0.0, sin(p.x * 1.4 + n1 * 0.6 + t * 0.25)), 1.4);
    float wMagenta = pow(max(0.0, cos(p.y * 1.4 + n2 * 0.6 - t * 0.20)), 1.4);
    float wPurple  = pow(max(0.0, sin(p.z * 1.4 + n3 * 0.6 + t * 0.28)), 1.4);
    float wAmber   = pow(max(0.0, cos(p.x * 1.2 - p.y * 1.2 + t * 0.16)), 1.4);

    float sumW = wCyan + wMagenta + wPurple + wAmber + 0.001;
    vec3 fluidColor = (COLOR_CYAN * wCyan + COLOR_MAGENTA * wMagenta + COLOR_PURPLE * wPurple + COLOR_AMBER * wAmber) / sumW;

    // Subtle gentle luminescence variation
    float lum = 0.90 + 0.20 * sin(n1 * 1.4 + t * 0.5);
    fluidColor *= lum;

    // Soft atmospheric Fresnel rim glow
    float fresnel = pow(1.0 - z, 2.0);
    vec3 rimColor = mix(COLOR_CYAN, COLOR_MAGENTA, 0.5 + 0.5 * sin(t * 0.4 + p.x));
    fluidColor = mix(fluidColor, rimColor, fresnel * 0.30);

    // Gentle breathing inner nucleus
    float coreRadius = 0.35 + u_audioLevel * 0.12 + isProcessing * 0.06;
    float coreGlow = exp(-r * r / max(coreRadius * coreRadius, 0.03));
    fluidColor += vec3(1.0, 1.0, 1.0) * (coreGlow * (0.24 + 0.12 * sin(t * 1.0)));

    // Premultiplied alpha output with ultra-soft Gaussian edge
    float finalAlpha = edgeSoftness * qt_Opacity;
    fragColor = vec4(fluidColor * finalAlpha, finalAlpha);
}

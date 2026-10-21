#version 440

// Apple Intelligence Siri Orb 3D Fluid Plasma Shader
// Colors: Cyan (#00f0ff), Magenta (#ff2d55), Purple (#8a2be2), Amber (#ff9f0a)
// Features: 3D Spherical projection, 3D fluid rotation curl, Fresnel rim glow, audio pulsation

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

const float PI = 3.14159265358979323846;

// Apple Intelligence Palette
const vec3 COLOR_CYAN    = vec3(0.000, 0.941, 1.000); // #00F0FF
const vec3 COLOR_PURPLE  = vec3(0.541, 0.169, 0.886); // #8A2BE2
const vec3 COLOR_MAGENTA = vec3(1.000, 0.176, 0.333); // #FF2D55
const vec3 COLOR_AMBER   = vec3(1.000, 0.624, 0.039); // #FF9F0A

// Rotation matrix around an axis
mat3 rotateY(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat3(
        c, 0.0, s,
        0.0, 1.0, 0.0,
        -s, 0.0, c
    );
}

mat3 rotateX(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat3(
        1.0, 0.0, 0.0,
        0.0, c, -s,
        0.0, s, c
    );
}

void main()
{
    if (qt_Opacity <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // Normalized coordinates from -1.0 to 1.0
    vec2 uv = (qt_TexCoord0 - 0.5) * 2.0;
    float r = length(uv);

    // Smooth circular boundary
    float circleAlpha = 1.0 - smoothstep(0.92, 1.0, r);
    if (circleAlpha <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Dynamic animation speed based on audio level and processing state
    float speedMultiplier = 1.0 + isProcessing * 2.2 + u_audioLevel * 1.8;
    float t = u_time * speedMultiplier;

    // 3D Spherical normal projection
    float z = sqrt(max(0.0, 1.0 - r * r));
    vec3 normal = vec3(uv.x, uv.y, z);

    // Apply fluid 3D spatial rotation to sample position
    mat3 rot = rotateY(t * 0.8) * rotateX(t * 0.5);
    vec3 p = rot * normal;

    // Multi-octave fluid plasma displacement
    float wave1 = sin(p.x * 3.5 + t * 1.4) * cos(p.y * 3.5 - t * 1.1) + sin(p.z * 3.5 + t);
    float wave2 = cos(p.y * 5.0 - t * 1.8) * sin(p.z * 5.0 + t * 1.5) + cos(p.x * 5.0 - t * 0.8);
    float wave3 = sin(p.z * 7.0 + t * 2.2) * cos(p.x * 7.0 - t * 1.6);

    float fluid = (wave1 * 0.5 + wave2 * 0.35 + wave3 * 0.15) * 0.5 + 0.5; // range ~0..1

    // Additional chromatic swirl angle
    float angle = atan(uv.y, uv.x) + t * 0.7 + fluid * 1.5;
    float colorPhase = fract((angle / (2.0 * PI)) + 0.5);

    // Blend between Apple Intelligence 4-color palette
    vec3 fluidColor;
    if (colorPhase < 0.25) {
        fluidColor = mix(COLOR_CYAN, COLOR_PURPLE, colorPhase / 0.25);
    } else if (colorPhase < 0.50) {
        fluidColor = mix(COLOR_PURPLE, COLOR_MAGENTA, (colorPhase - 0.25) / 0.25);
    } else if (colorPhase < 0.75) {
        fluidColor = mix(COLOR_MAGENTA, COLOR_AMBER, (colorPhase - 0.50) / 0.25);
    } else {
        fluidColor = mix(COLOR_AMBER, COLOR_CYAN, (colorPhase - 0.75) / 0.25);
    }

    // Enhance fluid luminosity
    fluidColor *= 0.85 + 0.35 * sin(fluid * PI);

    // Fresnel rim glow (glowing atmospheric edge of Siri orb)
    float fresnel = pow(1.0 - z, 2.2);
    vec3 rimColor = mix(COLOR_CYAN, COLOR_MAGENTA, 0.5 + 0.5 * sin(t + uv.x * 2.0));
    vec3 finalColor = mix(fluidColor, rimColor, fresnel * 0.75);

    // Hot central core (breathing nucleus)
    float coreRadius = 0.35 + (u_audioLevel * 0.2) + (isProcessing * 0.15);
    float coreGlow = smoothstep(coreRadius, 0.0, r);
    vec3 coreColor = vec3(1.0, 1.0, 1.0) * (0.55 + 0.45 * sin(t * 3.0));
    finalColor += coreColor * coreGlow * 0.85;

    // Outer edge aura
    float edgeBloom = smoothstep(0.7, 0.95, r) * (0.3 + 0.2 * u_audioLevel);
    finalColor += rimColor * edgeBloom;

    // Apply circular mask and Qt opacity
    float alpha = circleAlpha * (0.88 + 0.12 * fresnel) * qt_Opacity;
    fragColor = vec4(finalColor * alpha, alpha);
}

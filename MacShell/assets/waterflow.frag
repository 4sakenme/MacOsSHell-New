#version 440

// Apple Tahoe Liquid Waterflow Shader
// Flowing cyan-blue water caustics and fluid waves running horizontally across the card
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float u_time;
    float borderRadius;
};

float sdRoundedBox(vec2 p, vec2 b, float r)
{
    vec2 q = abs(p) - b + vec2(r);
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void main()
{
    if (qt_Opacity <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 pos = (qt_TexCoord0 - 0.5) * itemSize;
    vec2 halfSize = (itemSize * 0.5) - vec2(1.0);
    float r = min(borderRadius, min(halfSize.x, halfSize.y));
    float d = sdRoundedBox(pos, halfSize, r);

    // Smooth edge alpha
    float alpha = smoothstep(1.0, -1.0, d) * qt_Opacity;
    if (alpha <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 uv = qt_TexCoord0;
    float t = u_time * 0.75;

    // Fluid wave dynamics (horizontal flow left to right with undulating waves)
    float wave1 = sin(uv.x * 4.5 - t * 1.8 + cos(uv.y * 3.2 + t * 0.6)) * 0.5 + 0.5;
    float wave2 = sin(uv.x * 7.2 - t * 2.4 + sin(uv.y * 5.0 - t * 1.1)) * 0.5 + 0.5;
    float wave3 = cos(uv.x * 2.8 + t * 1.2 + sin(uv.y * 2.5 + t * 0.9)) * 0.5 + 0.5;

    // Caustic interference pattern
    float caustic = pow(wave1 * wave2, 1.8) * 1.4 + pow(wave2 * wave3, 2.2);

    // Water color gradient palette:
    // Deep ocean base (#0A1324) -> Apple Pacific Blue (#0066CC) -> Vibrant Aqua Cyan (#00D2FF) -> Specular White
    vec3 cDeep = vec3(0.04, 0.08, 0.16);
    vec3 cOcean = vec3(0.00, 0.40, 0.85);
    vec3 cAqua = vec3(0.00, 0.82, 1.00);
    vec3 cHighlight = vec3(0.70, 0.94, 1.00);

    // Gradient mix based on waves and vertical position
    float flowMix = wave1 * 0.45 + wave2 * 0.35 + wave3 * 0.20;
    vec3 col = mix(cDeep, cOcean, flowMix);
    col = mix(col, cAqua, caustic * 0.55);

    // Surface glimmer shimmer
    float shimmer = pow(sin(uv.x * 9.0 - t * 3.0 + uv.y * 6.0) * 0.5 + 0.5, 4.0) * 0.35;
    col += cHighlight * shimmer;

    // Delicate top specular rim highlight
    float topRim = smoothstep(0.08, 0.0, uv.y) * 0.25;
    col += vec3(topRim);

    // 1px subtle inner border glow
    float borderGlow = smoothstep(1.5, 0.0, abs(d)) * 0.35;
    col += cAqua * borderGlow;

    fragColor = vec4(col * alpha, alpha * 0.94);
}


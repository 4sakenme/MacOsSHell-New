#version 440
//  macOS Tahoe 26 - Liquid Glass Tube Fragment Shader
// Optics: Refraction normal distortion, chromatic dispersion, top specular glint, and bottom sapphire caustic shadow.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;       // Size of this shader item in pixels
    vec2 srcSize;        // Screen / wallpaper texture size in pixels
    vec2 srcOffset;      // Top-left coordinate of this item inside the screen, px
    vec2 lightDir;       // Direction the light arrives from (e.g. normalize(vec2(-0.5, -0.8)))
    float refractAmount; // Refraction shift scale (default 0.04)
    float specularPower; // Specular gloss exponent (default 16.0)
    float specularBoost; // Specular intensity (default 0.90)
    float fresnelBoost;  // Rim Fresnel intensity (default 0.45)
    float causticsBoost; // Bottom sapphire shadow intensity (default 0.50)
};

layout(binding = 1) uniform sampler2D src;  // Screen / wallpaper texture
layout(binding = 2) uniform sampler2D mask; // Progressive stroke mask (alpha 0..1)
layout(binding = 3) uniform sampler2D hmap; // Softened heightmap for surface slope calculation

void main()
{
    vec2 uv = qt_TexCoord0;
    float a = texture(mask, uv).a;
    if (a <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // ── 1. Calculate Surface Normal from Gradient of Heightmap ──
    vec2 step = 2.0 / itemSize;
    float hL = texture(hmap, uv - vec2(step.x, 0.0)).a;
    float hR = texture(hmap, uv + vec2(step.x, 0.0)).a;
    float hT = texture(hmap, uv - vec2(0.0, step.y)).a;
    float hB = texture(hmap, uv + vec2(0.0, step.y)).a;

    vec2 grad = vec2(hR - hL, hB - hT);
    float slope = length(grad);
    // 2D Normal vector pointing outward from stroke centerline towards edges
    vec2 normal = slope > 1e-5 ? grad / slope : vec2(0.0);

    // ── 2. Optical Refraction & Chromatic Dispersion ──
    vec2 screenPos = uv * itemSize + srcOffset;
    // Displace background sampling coordinate along surface normal
    vec2 shift = normal * (refractAmount * 32.0) * smoothstep(0.02, 0.65, slope);

    // Slight chromatic dispersion between red, green, and blue wavelengths
    vec2 uvR = clamp((screenPos - shift * 1.05) / srcSize, vec2(0.001), vec2(0.999));
    vec2 uvG = clamp((screenPos - shift) / srcSize, vec2(0.001), vec2(0.999));
    vec2 uvB = clamp((screenPos - shift * 0.95) / srcSize, vec2(0.001), vec2(0.999));

    vec3 bgRefract;
    bgRefract.r = texture(src, uvR).r;
    bgRefract.g = texture(src, uvG).g;
    bgRefract.b = texture(src, uvB).b;

    // ── 3. Specular Highlight & Fresnel Sheen ──
    vec2 L = normalize(lightDir);
    // Top ridge normal points upwards (-normal.y is positive when facing light)
    float nDotL = dot(-normal, -L);
    float spec = pow(max(nDotL, 0.0), specularPower) * specularBoost;

    // Rim Fresnel glint along grazing angles of the tube
    float fresnel = pow(clamp(slope * 1.8, 0.0, 1.0), 3.0) * fresnelBoost;

    // ── 4. Bottom Sapphire Caustic Shadow ──
    // Bottom edge has normal pointing downwards (normal.y > 0)
    float isBottom = clamp(normal.y * 1.5, 0.0, 1.0) * smoothstep(0.05, 0.60, slope);
    vec3 causticColor = vec3(0.01, 0.04, 0.22); // Deep sapphire ocean shadow

    // ── 5. Composite Translucent Liquid Glass Tube ──
    // Core body is 100% translucent glass showing the underlying blue ribbon
    vec3 glassCol = bgRefract * (1.02 + fresnel * 0.30);
    // Apply bottom shadow
    glassCol = mix(glassCol, causticColor, isBottom * causticsBoost);
    // Add specular white glint
    glassCol += vec3(1.0, 1.0, 1.0) * spec;
    // Add bright edge crest
    glassCol += vec3(0.90, 0.96, 1.0) * fresnel * 0.25;

    // Premultiplied alpha output
    fragColor = vec4(clamp(glassCol, 0.0, 1.0) * a, a) * qt_Opacity;
}

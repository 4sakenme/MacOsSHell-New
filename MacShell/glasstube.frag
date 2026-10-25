#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float refractScale;
    float specularBoost;
    float fresnelBoost;
    vec4 p00_p10;
    vec4 p01_p11;
    vec2 srcSize;
    vec2 itemSize;
};

layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D mask;
layout(binding = 3) uniform sampler2D hmap;

void main() {
    vec2 uv = qt_TexCoord0;
    float a = texture(mask, uv).a;
    if (a <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // 8-tap Sobel filter on blurred heightmap to calculate ultra-smooth outward normal
    vec2 s = 3.5 / itemSize;
    float h00 = texture(hmap, uv + vec2(-s.x, -s.y)).a;
    float h10 = texture(hmap, uv + vec2( 0.0, -s.y)).a;
    float h20 = texture(hmap, uv + vec2( s.x, -s.y)).a;
    float h01 = texture(hmap, uv + vec2(-s.x,  0.0)).a;
    float h21 = texture(hmap, uv + vec2( s.x,  0.0)).a;
    float h02 = texture(hmap, uv + vec2(-s.x,  s.y)).a;
    float h12 = texture(hmap, uv + vec2( 0.0,  s.y)).a;
    float h22 = texture(hmap, uv + vec2( s.x,  s.y)).a;

    float gx = (h00 + 2.0 * h01 + h02) - (h20 + 2.0 * h21 + h22);
    float gy = (h00 + 2.0 * h10 + h20) - (h02 + 2.0 * h12 + h22);
    vec2 grad = vec2(gx, gy);
    float slope = length(grad);
    vec2 normal2D = slope > 1e-5 ? grad / slope : vec2(0.0);

    // Height and normalized distance from centerline (0 = center, 1 = edge)
    float rawH = texture(hmap, uv).a;
    float h = clamp(rawH, 0.0, 1.0);
    float distFromCenter = clamp(1.0 - smoothstep(0.06, 0.94, h), 0.0, 1.0);

    // Screen-space background mapping
    vec2 p00 = p00_p10.xy;
    vec2 p10 = p00_p10.zw;
    vec2 p01 = p01_p11.xy;
    vec2 p11 = p01_p11.zw;
    vec2 screenPos = mix(mix(p00, p10, uv.x), mix(p01, p11, uv.x), uv.y);
    vec2 baseUV = screenPos / srcSize;

    // 1. Refraction Distortion
    vec2 refractionOffset = normal2D * refractScale * (1.0 - distFromCenter);

    // Sample background wallpaper with chromatic dispersion
    vec3 backgroundCol;
    backgroundCol.r = texture(src, clamp(baseUV + refractionOffset * 1.05, vec2(0.001), vec2(0.999))).r;
    backgroundCol.g = texture(src, clamp(baseUV + refractionOffset * 1.00, vec2(0.001), vec2(0.999))).g;
    backgroundCol.b = texture(src, clamp(baseUV + refractionOffset * 0.95, vec2(0.001), vec2(0.999))).b;

    // 2. 3D Specular Highlight & Fresnel Rim
    float nz = sqrt(max(1.0 - distFromCenter * distFromCenter, 0.0));
    vec3 normal3D = normalize(vec3(-normal2D * distFromCenter, nz));

    vec3 lightDir = normalize(vec3(-0.5, -0.8, 0.6));
    vec3 viewDir = vec3(0.0, 0.0, 1.0);

    vec3 refl = reflect(-lightDir, normal3D);
    float spec = pow(max(dot(refl, viewDir), 0.0), 32.0);
    vec3 specularColor = vec3(1.0, 1.0, 1.0) * spec * specularBoost;

    float fresnel = pow(1.0 - max(dot(normal3D, vec3(0.0, 0.0, 1.0)), 0.0), 3.0);
    vec3 rimGlow = vec3(0.85, 0.92, 1.0) * fresnel * fresnelBoost;

    // 3. Translucent Glass Tint
    vec3 tint = vec3(0.1, 0.3, 0.8) * 0.15;

    vec3 rgb = backgroundCol * 1.02 + tint + specularColor + rimGlow;
    fragColor = vec4(clamp(rgb, 0.0, 1.0) * a, a) * qt_Opacity;
}

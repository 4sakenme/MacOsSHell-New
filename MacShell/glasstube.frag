#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float refractScale;
    float specularBoost;
    float shadowBoost;
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

    // Normal points outwards from center to edge (left/top has higher h in gradient)
    float gx = (h00 + 2.0 * h01 + h02) - (h20 + 2.0 * h21 + h22);
    float gy = (h02 + 2.0 * h12 + h22) - (h00 + 2.0 * h10 + h20);
    vec2 grad = vec2(gx, gy);
    float slope = length(grad);
    vec2 normal = slope > 1e-5 ? grad / slope : vec2(0.0);

    // Height & normalized distance from center (0 = center, 1 = edge)
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

    // 1. Subtle Optical Refraction (Không kéo mảng màu xa vào lòng chữ)
    vec2 refractionOffset = normal * refractScale * (1.0 - distFromCenter);
    vec3 baseBg = texture(src, clamp(baseUV + refractionOffset, vec2(0.001), vec2(0.999))).rgb;

    // 2. Đổ bóng nhẹ dưới đáy ống (Drop Shadow / Depth)
    vec2 lightDir = normalize(vec2(-0.5, -0.85));
    float bottomFactor = smoothstep(0.45, 0.95, distFromCenter) * max(dot(normal, -lightDir), 0.0);
    float shadow = bottomFactor * shadowBoost;
    baseBg *= (1.0 - shadow);

    // 3. Chỉ tạo viền sáng phản quang mảnh ở gờ mép (Thin Rim Highlight)
    float edgeFactor = smoothstep(0.68, 0.94, distFromCenter);
    float spec = pow(max(dot(normal, lightDir), 0.0), 16.0);
    vec3 specularLine = vec3(1.0, 1.0, 1.0) * spec * edgeFactor * specularBoost;

    // 4. Kết quả hòa trộn (Final Composite)
    vec3 finalColor = baseBg + specularLine;
    fragColor = vec4(clamp(finalColor, 0.0, 1.0) * a, a) * qt_Opacity;
}

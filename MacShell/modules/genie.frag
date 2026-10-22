#version 440
// macOS Genie & Scale Minimize Effect Warp Shader for Quickshell / MacShell.
// Build: /usr/lib/qt6/bin/qsb --qt6 -o modules/genie.frag.qsb modules/genie.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 screenSize;      // Width and Height of the screen in px
    vec4 sourceRect;      // vec4(x, y, width, height) of original window in px
    vec2 targetPoint;     // vec2(x, y) target dock icon center in px
    float progress;       // 0.0 -> 1.0 (0.0 = full window, 1.0 = sucked into icon)
    float mode;           // 0.0 = genie, 1.0 = scale
};

layout(binding = 1) uniform sampler2D sourceTexture;

const float PI = 3.141592653589793;

void main()
{
    float p = clamp(progress, 0.0, 1.0);
    vec2 pixelPos = qt_TexCoord0 * screenSize;

    float Wx = sourceRect.x;
    float Wy = sourceRect.y;
    float Ww = max(sourceRect.z, 1.0);
    float Wh = max(sourceRect.w, 1.0);
    float Wcx = Wx + Ww * 0.5;

    float Tx = targetPoint.x;
    float Ty = targetPoint.y;

    // ─────────────────────────────────────────────────────────────
    // MODE 1: SCALE EFFECT (LINEAR UNIFORM RECT ZOOM INTO DOCK)
    // ─────────────────────────────────────────────────────────────
    if (mode >= 0.5) {
        float curW = mix(Ww, 48.0, p);
        float curH = mix(Wh, 48.0, p);
        float curCx = mix(Wcx, Tx, p);
        float curCy = mix(Wy + Wh * 0.5, Ty, p);

        float left = curCx - curW * 0.5;
        float right = curCx + curW * 0.5;
        float top = curCy - curH * 0.5;
        float bottom = curCy + curH * 0.5;

        if (pixelPos.x < left || pixelPos.x > right || pixelPos.y < top || pixelPos.y > bottom) {
            fragColor = vec4(0.0);
            return;
        }

        float u = (pixelPos.x - left) / curW;
        float v = (pixelPos.y - top) / curH;

        float edgeX = min(pixelPos.x - left, right - pixelPos.x);
        float edgeY = min(pixelPos.y - top, bottom - pixelPos.y);
        float edgeAlpha = clamp(edgeX / 1.5, 0.0, 1.0) * clamp(edgeY / 1.5, 0.0, 1.0);

        float fade = 1.0 - smoothstep(0.90, 1.0, p);
        vec4 texColor = texture(sourceTexture, vec2(u, v));
        fragColor = texColor * (edgeAlpha * fade * qt_Opacity);
        return;
    }

    // ─────────────────────────────────────────────────────────────
    // MODE 0: GENIE EFFECT (MACOS FLUID BEND & PINCH INTO DOCK)
    // ─────────────────────────────────────────────────────────────
    // 1. Dynamic Vertical Limits
    // The bottom descends fast to the dock icon, the top follows with lag
    float pBot = pow(p, 0.85);
    float pTop = pow(p, 1.85);

    float yBot = mix(Wy + Wh, Ty, pBot);
    float yTop = mix(Wy, Ty, pTop);
    float heightSpan = yBot - yTop;

    if (pixelPos.y < yTop || pixelPos.y > yBot || heightSpan <= 1.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Normalized vertical progression along the genie body [0.0 = top, 1.0 = bottom]
    float v = (pixelPos.y - yTop) / heightSpan;

    // 2. Spine Curve (Center X as a function of v)
    // Top center stays close to original center and curves toward Tx
    float xTop = mix(Wcx, Tx, pow(p, 2.2));
    float xBot = Tx;

    // Hermite S-curve connecting top to bottom
    float s = v * v * (3.0 - 2.0 * v);
    
    // Natural lateral sweep bulge when window is offset from dock icon
    float deltaX = Tx - Wcx;
    float lateralSweep = sin(v * PI) * deltaX * 0.16 * p * (1.0 - p);
    float xMid = mix(xTop, xBot, s) + lateralSweep;

    // 3. Width Profile (Tapering from wide top into narrow dock neck)
    // Top width stays wide early on
    float wTop = Ww * (1.0 - pow(p, 1.6) * 0.90);
    // Bottom width pinches into dock icon size
    float wBot = max(4.0, 48.0 * (1.0 - p) + 2.0);

    // Exponential funnel profile
    float funnel = mix(wTop, wBot, pow(v, mix(1.0, 0.40, p)));
    // Genie waist pinch (classic macOS magic lamp narrowing in the middle)
    float waistPinch = 1.0 - (0.40 * p * sin(v * PI));
    float halfW = max(1.0, (funnel * waistPinch) * 0.5);

    // 4. Horizontal Limits & Normalized U
    float distFromMid = pixelPos.x - xMid;
    if (abs(distFromMid) > halfW) {
        fragColor = vec4(0.0);
        return;
    }

    float u = (distFromMid / (2.0 * halfW)) + 0.5;
    u = clamp(u, 0.0, 1.0);

    // 5. Anti-aliasing along the deformed borders
    float edgeDistX = halfW - abs(distFromMid);
    float edgeDistY = min(pixelPos.y - yTop, yBot - pixelPos.y);
    float edgeAlpha = clamp(edgeDistX / 1.5, 0.0, 1.0) * clamp(edgeDistY / 1.5, 0.0, 1.0);

    // 6. 3D Specular Sheen along the curved contours
    float rim = pow(1.0 - abs(u * 2.0 - 1.0), 3.0) * 0.16 * (1.0 - p);

    // 7. Dissipation Fade when finishing
    float fade = 1.0 - smoothstep(0.88, 1.0, p);

    vec4 texColor = texture(sourceTexture, vec2(u, v));
    texColor.rgb += vec3(rim) * texColor.a;

    fragColor = texColor * (edgeAlpha * fade * qt_Opacity);
}


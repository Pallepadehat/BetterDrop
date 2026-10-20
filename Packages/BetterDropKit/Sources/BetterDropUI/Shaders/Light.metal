// BetterDrop's light, drawn on the GPU. Every effect is one pass of one of these functions; nothing is blurred.
//
// The colour functions take `bounds` (SwiftUI's .boundingRect: x, y, width, height) and a `time` in seconds, and
// return premultiplied colour. They're applied with .colorEffect to a plain Rectangle.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// MARK: - Building blocks

inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

inline float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

inline float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    const float2x2 rotate = float2x2(1.6, 1.2, -1.2, 1.6);
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p);
        p = rotate * p;
        amplitude *= 0.5;
    }
    return value;
}

/// BetterDrop's light, round the wheel: apricot, rose, orchid, violet, periwinkle and back to apricot. No greens.
inline float3 iridescent(float t) {
    const float3 stops[5] = {
        float3(1.00, 0.62, 0.38),   // apricot
        float3(1.00, 0.36, 0.52),   // rose
        float3(0.84, 0.36, 0.95),   // orchid
        float3(0.52, 0.42, 1.00),   // violet
        float3(0.40, 0.66, 1.00),   // periwinkle
    };
    float x = fract(t) * 5.0;
    int i = int(floor(x));
    float f = smoothstep(0.0, 1.0, fract(x));
    return mix(stops[i % 5], stops[(i + 1) % 5], f);
}

inline float smoothMin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

inline float roundedRectDistance(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// MARK: - The orb

/// A drop of liquid light. `energy` (0–1) is how awake it is, `lean` stretches it towards a point (the Mac) in
/// units of its radius, and `charge` (0–1) is how long you've held it: it swirls faster, swells and draws a ring.
[[ stitchable ]]
half4 Orb(float2 position, half4 color, float4 bounds, float time, float energy, float2 lean, float charge) {
    float2 size = bounds.zw;
    float scale = min(size.x, size.y) * 0.5;
    float2 uv = (position - size * 0.5) / scale;
    float t = time * (1.0 + 2.5 * charge);

    float radius = 0.40 * (1.0 + 0.025 * sin(time * 1.8)) * (1.0 + 0.14 * charge);
    float angle = atan2(uv.y, uv.x);
    // Noise around a circle rather than along the angle, so there's no seam where the angle wraps.
    float2 around = float2(cos(angle), sin(angle));
    float wobble = 0.018 * (noise(around * 1.3 + t * 0.35) - 0.5) * (1.0 + 2.0 * energy)
                 + 0.007 * sin(angle * 3.0 + t * 1.3);
    float distance = length(uv) - radius + wobble;

    // Reaching towards the Mac: a second, smaller drop pulled out of the first and melted into it.
    float reach = length(lean);
    if (reach > 0.001) {
        float2 tip = lean * 0.62;
        float tipDistance = length(uv - tip) - radius * (0.30 + 0.25 * reach);
        distance = smoothMin(distance, tipDistance, 0.28);
    }

    // Inside: two layers of drifting noise folded into each other.
    // Inside: silky bands of colour, folded by slow noise.
    float2 q = uv * 1.4;
    float2 warp = float2(fbm(q * 1.2 + t * 0.15), fbm(q * 1.2 + float2(5.2, 1.3) - t * 0.12));
    float f = fbm(q + 1.6 * warp + t * 0.05);
    float bands = f * 0.9 + dot(uv, float2(0.25, 0.45)) + t * 0.03;
    float3 inner = iridescent(bands);
    // Depth: darker folds and bright crests, rather than one flat colour.
    inner *= 0.5 + 0.75 * smoothstep(0.25, 0.7, f);
    inner = mix(inner, float3(1.0, 0.96, 0.98), smoothstep(0.7, 0.98, f) * 0.45);
    float core = smoothstep(radius * 0.9, 0.0, length(uv));
    inner += iridescent(t * 0.05 + 0.1) * core * core * (0.08 + 0.3 * energy);
    // A glassy rim, and a soft highlight up and to the left, like light on a bead.
    float rim = smoothstep(-0.09, 0.0, distance);
    inner = mix(inner, iridescent(angle / 6.28318 + t * 0.04) * 1.2, rim * 0.6);
    float highlight = exp(-length(uv - float2(-0.16, -0.18) * (radius / 0.4)) * 9.0) * 0.55;
    inner += highlight;
    float inside = 1.0 - smoothstep(-0.006, 0.006, distance);

    // Outside: a halo, and the ring that closes in as you hold.
    float glow = exp(-max(distance, 0.0) * (8.0 - 4.0 * energy)) * (0.18 + 0.55 * energy);
    float ringRadius = radius + 0.38 * (1.0 - charge);
    float ring = charge * exp(-abs(length(uv) - ringRadius) * 38.0) * (0.65 + 0.35 * sin(angle * 6.0 + t * 4.0));
    float3 halo = iridescent(angle / 6.28318 + t * 0.06) * glow + float3(ring);

    // The halo fades to nothing before the edge of the canvas, so its square never shows.
    float2 canvas = abs(position - size * 0.5) / (size * 0.5);
    float edgeFade = 1.0 - smoothstep(0.7, 1.0, max(canvas.x, canvas.y));
    glow *= edgeFade;
    ring *= edgeFade;
    halo *= edgeFade;
    float alpha = clamp(inside + (glow + ring) * (1.0 - inside), 0.0, 1.0);
    float3 rgb = inner * inside + halo * (1.0 - inside);
    return half4(half3(min(rgb, float3(alpha * 1.15))), half(alpha));
}

// MARK: - The edge of the phone's screen

/// Light hugging the rounded edge of the screen. `emphasis` leans it to one side (-1 left, 1 right, 0 even) and
/// `surge` (0–1) is a burst on top, when something arrives or leaves.
[[ stitchable ]]
half4 EdgeGlow(float2 position, half4 color, float4 bounds, float time, float intensity, float emphasis, float radius, float surge) {
    float2 size = bounds.zw;
    float2 center = size * 0.5;
    float inset = max(0.0, -roundedRectDistance(position - center, center, radius));
    float angle = atan2(position.y - center.y, position.x - center.x);
    float n = noise(float2(angle * 3.0 + time * 0.7, time * 0.4));

    float strength = intensity + surge;
    float width = 4.0 + 30.0 * intensity + 50.0 * surge;
    float glow = exp(-pow(inset / (width * (0.7 + 0.6 * n)), 1.3));
    float line = exp(-inset / 1.8);

    float side = (position.x / size.x) * 2.0 - 1.0;
    float lean = mix(1.0, clamp(0.2 + 1.3 * (side * emphasis * 0.5 + 0.5), 0.0, 1.5), abs(emphasis));

    float3 rgb = iridescent(angle / 6.28318 + time * 0.07 + n * 0.3);
    rgb = mix(rgb, float3(1.0), line * 0.5);
    float alpha = clamp((glow * 0.85 + line * 0.6) * strength * lean, 0.0, 1.0);
    return half4(half3(rgb * alpha), half(alpha));
}

// MARK: - The edge of the Mac's screen

/// A curtain of light flowing out of one edge of the Mac's screen (`side`: 0 left, 1 right). `intensity` is how
/// close the phone is, `waves` adds rings rolling out of the edge, `surge` (0–1) is a front of light crossing the
/// screen when a file passes through.
[[ stitchable ]]
half4 Portal(float2 position, half4 color, float4 bounds, float time, float intensity, float side, float waves, float surge) {
    float2 size = bounds.zw;
    float fromEdge = side > 0.5 ? size.x - position.x : position.x;
    float v = (position.y / size.y - 0.5) * 2.0;

    float spread = 0.05 + 0.55 * intensity;
    float envelope = exp(-(v * v) / spread);
    float n = fbm(float2(fromEdge * 0.006 - time * 0.15, position.y * 0.004 - time * 0.3));
    float depth = 20.0 + size.x * 0.75 * intensity * (0.75 + 0.5 * n);
    float body = envelope * exp(-fromEdge / depth) * intensity * 1.6;

    float3 rgb = iridescent(v * 0.5 + n * 0.9 + time * 0.04);
    float core = exp(-fromEdge / (8.0 + 80.0 * intensity)) * envelope;
    rgb = mix(rgb, float3(1.0), clamp(core * 0.85, 0.0, 1.0));

    float r = length(float2(fromEdge, position.y - size.y * 0.5));
    float phase = fract(r / 150.0 - time * (0.5 + 1.1 * waves));
    float rings = waves * smoothstep(0.0, 0.04, phase) * (1.0 - smoothstep(0.04, 0.16, phase))
                * exp(-r / (size.x * 0.6)) * smoothstep(30.0, 160.0, r) * 0.55;
    float front = surge > 0.0 ? exp(-pow((r - surge * size.x * 1.2) / 55.0, 2.0)) * (1.0 - surge) : 0.0;

    float3 ringColor = iridescent(r * 0.002 - time * 0.1);
    // The canvas ends somewhere inside the screen: be fully dark well before it, and at the top and bottom,
    // so there's never a hard line.
    float fade = (1.0 - smoothstep(size.x * 0.5, size.x * 0.97, fromEdge))
               * smoothstep(0.0, 40.0, position.y) * smoothstep(0.0, 40.0, size.y - position.y);
    float alpha = clamp((body + rings + front) * fade, 0.0, 1.0);
    float3 total = (rgb * body + ringColor * (rings + front)) * fade;
    return half4(half3(min(total, float3(alpha))), half(alpha));
}

// MARK: - Backgrounds

/// A slow, dark aurora that brightens with `intensity`.
[[ stitchable ]]
half4 Aurora(float2 position, half4 color, float4 bounds, float time, float intensity) {
    float2 size = bounds.zw;
    float2 uv = position / max(size.x, size.y) * 2.2;
    float2 warp = float2(fbm(uv + time * 0.03), fbm(uv + float2(3.1, 7.7) - time * 0.025));
    float f = fbm(uv + 1.8 * warp);
    float3 rgb = iridescent(f * 0.6 + 0.3 + time * 0.01) * pow(f, 1.5) * (0.12 + 0.75 * intensity);
    float vignette = smoothstep(1.25, 0.15, length(position / size - 0.5) * 1.6);
    return half4(half3(rgb * vignette), 1.0);
}

// MARK: - Effects on views

/// Burns a view away into light, starting from the side it's heading (`direction`), as `progress` goes 0 to 1.
/// Backwards (1 to 0) it condenses out of light.
[[ stitchable ]]
half4 Dissolve(float2 position, SwiftUI::Layer layer, float4 bounds, float progress, float2 direction) {
    half4 color = layer.sample(position);
    if (progress <= 0.0) { return color; }
    float2 uv = position / bounds.zw;
    float n = fbm(position * 0.035);
    float lead = dot(uv - 0.5, normalize(direction)) + 0.5;
    float value = n * 0.45 + (1.0 - lead) * 0.55;
    float threshold = progress * 1.25 - 0.1;
    if (value < threshold) { return half4(0.0); }
    float edge = 1.0 - smoothstep(threshold, threshold + 0.08, value);
    half3 glow = half3(iridescent(value * 2.0 + progress) * 1.6) * color.a;
    return half4(mix(color.rgb, glow, half(edge)), color.a);
}

/// A ring of displacement travelling out from `origin`, like a drop in water.
[[ stitchable ]]
half4 Ripple(float2 position, SwiftUI::Layer layer, float2 origin, float time,
             float amplitude, float frequency, float decay, float speed) {
    float distance = length(position - origin);
    float t = max(0.0, time - distance / speed);
    float amount = amplitude * sin(frequency * t) * exp(-decay * t);
    float2 direction = distance > 0.0 ? normalize(position - origin) : float2(0.0);
    half4 color = layer.sample(position + amount * direction);
    color.rgb += half(0.3 * (amount / amplitude)) * color.a;
    return color;
}

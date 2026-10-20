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

/// Pearl and petrol: apricot, rose, violet, periwinkle and back, slightly washed with white.
inline float3 iridescent(float t) {
    float3 color = 0.55 + 0.45 * cos(6.28318 * (t + float3(0.0, 0.18, 0.42)));
    return mix(color, float3(1.0), 0.12);
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
    float wobble = 0.03 * (noise(float2(angle * 2.0 + 10.0, t * 0.6)) - 0.5) * (1.0 + 2.0 * energy);
    float distance = length(uv) - radius + wobble;

    // Reaching towards the Mac: a second, smaller drop pulled out of the first and melted into it.
    float reach = length(lean);
    if (reach > 0.001) {
        float2 tip = lean * 0.62;
        float tipDistance = length(uv - tip) - radius * (0.30 + 0.25 * reach);
        distance = smoothMin(distance, tipDistance, 0.28);
    }

    // Inside: two layers of drifting noise folded into each other.
    float2 q = uv * 1.8;
    float2 warp = float2(fbm(q + t * 0.12), fbm(q + float2(5.2, 1.3) - t * 0.10));
    float f = fbm(q + 2.2 * warp + t * 0.05);
    float3 inner = iridescent(f * 1.3 + length(warp) * 0.6 + t * 0.03);
    inner = mix(inner, float3(1.0), smoothstep(0.55, 0.95, f) * 0.55);
    float core = smoothstep(radius, 0.0, length(uv));
    inner += core * core * (0.2 + 0.5 * energy);
    inner = mix(inner, float3(1.0), smoothstep(-0.10, 0.0, distance) * 0.55);
    float inside = 1.0 - smoothstep(-0.006, 0.006, distance);

    // Outside: a halo, and the ring that closes in as you hold.
    float glow = exp(-max(distance, 0.0) * (7.0 - 3.5 * energy)) * (0.22 + 0.6 * energy);
    float ringRadius = radius + 0.38 * (1.0 - charge);
    float ring = charge * exp(-abs(length(uv) - ringRadius) * 38.0) * (0.65 + 0.35 * sin(angle * 6.0 + t * 4.0));
    float3 halo = iridescent(angle / 6.28318 + t * 0.06) * glow + float3(ring);

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
    float glow = exp(-inset / (width * (0.7 + 0.6 * n)));
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
    rgb = mix(rgb, float3(1.0), clamp(core * 1.2, 0.0, 1.0));

    float r = length(float2(fromEdge, position.y - size.y * 0.5));
    float phase = fract(r / 150.0 - time * (0.5 + 1.1 * waves));
    float rings = waves * smoothstep(0.0, 0.04, phase) * (1.0 - smoothstep(0.04, 0.16, phase)) * exp(-r / (size.x * 0.6)) * 0.55;
    float front = surge > 0.0 ? exp(-pow((r - surge * size.x * 1.2) / 55.0, 2.0)) * (1.0 - surge) : 0.0;

    float3 ringColor = iridescent(r * 0.002 - time * 0.1);
    float alpha = clamp(body + rings + front, 0.0, 1.0);
    float3 total = rgb * body + ringColor * (rings + front);
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
    float3 rgb = iridescent(f * 0.9 + time * 0.01 + 0.6) * pow(f, 2.2) * (0.12 + 0.55 * intensity);
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

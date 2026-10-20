#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

/// A ring of displacement travelling out from `origin`, like a drop in water. Pixels in the ring are pushed along
/// the ring's radius and brightened a little, so it catches the light.
[[ stitchable ]]
half4 Ripple(float2 position, SwiftUI::Layer layer, float2 origin, float time,
             float amplitude, float frequency, float decay, float speed) {
    float distance = length(position - origin);
    float delay = distance / speed;
    float t = max(0.0, time - delay);
    float amount = amplitude * sin(frequency * t) * exp(-decay * t);
    float2 direction = distance > 0.0 ? normalize(position - origin) : float2(0.0);
    half4 color = layer.sample(position + amount * direction);
    color.rgb += half(0.3 * (amount / amplitude)) * color.a;
    return color;
}

/// The edge of the screen nearest the Mac, turned to liquid: the closer the Mac, the stronger and wider the waves.
/// `side` is 0 for the left edge, 1 for the right.
[[ stitchable ]]
half4 EdgeWarp(float2 position, SwiftUI::Layer layer, float2 size, float side, float closeness, float time) {
    float fromEdge = side < 0.5 ? position.x : size.x - position.x;
    float reach = 40.0 + 160.0 * closeness;
    float falloff = exp(-fromEdge / reach);
    float wave = sin(position.y * 0.045 - time * 5.0) + 0.5 * sin(position.y * 0.11 + time * 3.1);
    float push = closeness * 9.0 * falloff * wave;
    float2 offset = float2(side < 0.5 ? -push : push, push * 0.35);
    half4 color = layer.sample(position + offset);
    color.rgb += half(0.18 * closeness * falloff * (0.5 + 0.5 * wave)) * color.a;
    return color;
}

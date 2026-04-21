#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float4 fgColor  [[attribute(2)]];
    float4 bgColor  [[attribute(3)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 fgColor;
    float4 bgColor;
};

struct Uniforms {
    float2 viewportSize;
};

vertex VertexOut vertexShader(VertexIn in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    float2 clipPos = (in.position / uniforms.viewportSize) * 2.0 - 1.0;
    clipPos.y = -clipPos.y;
    out.position = float4(clipPos, 0.0, 1.0);
    out.texCoord = in.texCoord;
    out.fgColor = in.fgColor;
    out.bgColor = in.bgColor;
    return out;
}

// Fragment shader for a gamma-incorrect (sRGB-space) blending pipeline.
//
// The render target is `.bgra8Unorm` (no hardware sRGB encode), so the
// blending math happens directly in sRGB space. This matches Ghostty's
// macOS `native` alpha-blending mode and traditional AppKit text rendering,
// and is what the default CJK rendering we want to match does in practice.
// Blending uses premultiplied-alpha over-compositing (configured on the
// pipeline as src=one, dst=one_minus_source_alpha), so every quad type
// outputs genuinely premultiplied color.
//
// The glyph atlas texture is `.r8Unorm`: a single-channel coverage mask
// produced by CoreText in a linearGray alpha-only bitmap context (the
// colorspace on an alpha-only context does not affect the alpha values,
// so the coverage values are the same as any other grayscale rasterization).
//
// Three quad types flow through this shader:
//   1. Debug overlay:     fgColor.a == 0, bgColor.a == 0    → pre-rendered
//                                                              premultiplied RGBA
//   2. Glyph quads:       fgColor.a > 0                     → coverage * fg
//   3. Background/cursor: fgColor.a == 0, bgColor.a > 0     → solid or
//                                                              translucent bg
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler texSampler(mag_filter::nearest, min_filter::nearest);

    // Debug overlay: bg_color.a == 0 and fg_color.a == 0 signals a
    // pre-colored RGBA texture that should pass through directly.
    if (in.fgColor.a == 0.0 && in.bgColor.a == 0.0) {
        return atlas.sample(texSampler, in.texCoord);
    }

    // Glyph quad: the atlas's single-channel coverage mask multiplied by
    // the foreground color, output as premultiplied-alpha.
    if (in.fgColor.a > 0.0) {
        float coverage = atlas.sample(texSampler, in.texCoord).r;
        return float4(in.fgColor.rgb * coverage, coverage);
    }

    // Background or cursor quad: output the background color as
    // premultiplied-alpha. For opaque backgrounds (alpha=1) this overwrites
    // the destination; for translucent cursor quads it composites correctly.
    return float4(in.bgColor.rgb * in.bgColor.a, in.bgColor.a);
}

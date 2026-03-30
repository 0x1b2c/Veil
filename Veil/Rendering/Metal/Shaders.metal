#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float4 bgColor  [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
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
    out.bgColor = in.bgColor;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler texSampler(mag_filter::nearest, min_filter::nearest);
    float4 texColor = atlas.sample(texSampler, in.texCoord);
    return mix(in.bgColor, texColor, texColor.a);
}

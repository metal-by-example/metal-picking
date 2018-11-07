#include <metal_stdlib>

using namespace metal;

struct InstanceConstants {
    float4x4 modelViewProjectionMatrix;
    float4x4 normalMatrix;
    float4 color;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float4 color;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant InstanceConstants &instance [[buffer(1)]])
{
    VertexOut out;

    float4 position(in.position, 1);
    float4 normal(in.normal, 0);
    
    out.position = instance.modelViewProjectionMatrix * position;
    out.normal = (instance.normalMatrix * normal).xyz;
    out.color = instance.color;

    return out;
}

fragment half4 fragment_main(VertexOut in [[stage_in]])
{
    float3 L(0, 0, 1);
    float3 N = normalize(in.normal);
    float NdotL = saturate(dot(N, L));

    float intensity = saturate(0.1 + NdotL);
    
    return half4(intensity * in.color);
}

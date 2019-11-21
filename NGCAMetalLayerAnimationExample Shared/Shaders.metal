//
//  Shaders.metal
//  NGCAMetalLayerAnimationExample Shared
//
//  Created by Noah Gilmore on 11/21/19.
//  Copyright © 2019 Noah Gilmore. All rights reserved.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

typedef struct
{
    float3 position [[attribute(0)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
} ColorInOut;

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
} Uniforms;

vertex ColorInOut vertex_shader(device Vertex *vertices [[buffer(0)]],
                                uint vertexId [[vertex_id]],
                                constant Uniforms & uniforms [[ buffer(1) ]])
{
    ColorInOut out;
    Vertex in = vertices[vertexId];
    float4 position = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * position;

    return out;
}

fragment float4 fragment_shader(ColorInOut in [[stage_in]])
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    // Blue
    return float4(0, 0, 1, 1);
}

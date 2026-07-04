#include <metal_stdlib>
using namespace metal;

struct GooeyMetaballUniforms {
    float4 viewportSizeAndAlpha;
    float4 sourceRect;
    float4 menuRect;
    float4 contentRect;
    float4 lensControls;
    float4 bridgePoints;
    float4 radiiAndTime;
    float4 fillColor;
    float4 edgeColor;
    float4 targetControls;
};

struct GooeyVertexOut {
    float4 position [[position]];
    float2 point;
};

constant static float2 gooeyQuadVertices[6] = {
    float2(0.0, 0.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 1.0)
};

vertex GooeyVertexOut gooeyMetaballVertex(
    constant GooeyMetaballUniforms &uniforms [[ buffer(0) ]],
    uint vertexId [[ vertex_id ]]
) {
    float2 uv = gooeyQuadVertices[vertexId];

    GooeyVertexOut out;
    out.position = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);
    out.point = uv * uniforms.viewportSizeAndAlpha.xy;
    return out;
}

static float roundedRectSDF(float2 point, float4 rect, float radius) {
    float2 size = max(rect.zw, float2(0.001));
    float2 center = rect.xy + size * 0.5;
    float r = clamp(radius, 0.0, min(size.x, size.y) * 0.5);
    float2 q = abs(point - center) - size * 0.5 + float2(r);
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

static float capsuleSDF(float2 point, float2 a, float2 b, float radius) {
    float2 ab = b - a;
    float len2 = max(dot(ab, ab), 0.001);
    float h = clamp(dot(point - a, ab) / len2, 0.0, 1.0);
    return length(point - (a + ab * h)) - radius;
}

static float smoothMin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.001), 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

static float sceneSDF(float2 point, constant GooeyMetaballUniforms &uniforms, float smoothness) {
    float sourceDistance = roundedRectSDF(point, uniforms.sourceRect, uniforms.radiiAndTime.x);
    float menuDistance = roundedRectSDF(point, uniforms.menuRect, uniforms.radiiAndTime.y);
    float distanceField = smoothMin(sourceDistance, menuDistance, smoothness);

    float bridgeRadius = uniforms.radiiAndTime.z;
    if (bridgeRadius > 0.5) {
        float bridgeDistance = capsuleSDF(
            point,
            uniforms.bridgePoints.xy,
            uniforms.bridgePoints.zw,
            bridgeRadius
        );
        distanceField = smoothMin(distanceField, bridgeDistance, smoothness * 1.35);
    }

    return distanceField;
}

static float insideUnitRect(float2 uv) {
    float2 low = step(float2(0.0), uv);
    float2 high = step(uv, float2(1.0));
    return low.x * low.y * high.x * high.y;
}

static half4 sampleBlurredContent(texture2d<half, access::sample> texture, sampler s, float2 uv, float radius) {
    float2 texel = 1.0 / max(float2(texture.get_width(), texture.get_height()), float2(1.0));
    float2 r = texel * radius;

    half4 color = texture.sample(s, uv) * half(0.22);
    color += texture.sample(s, uv + float2( r.x, 0.0)) * half(0.12);
    color += texture.sample(s, uv + float2(-r.x, 0.0)) * half(0.12);
    color += texture.sample(s, uv + float2(0.0,  r.y)) * half(0.12);
    color += texture.sample(s, uv + float2(0.0, -r.y)) * half(0.12);
    color += texture.sample(s, uv + float2( r.x,  r.y) * 0.72) * half(0.075);
    color += texture.sample(s, uv + float2(-r.x,  r.y) * 0.72) * half(0.075);
    color += texture.sample(s, uv + float2( r.x, -r.y) * 0.72) * half(0.075);
    color += texture.sample(s, uv + float2(-r.x, -r.y) * 0.72) * half(0.075);
    return color;
}

fragment half4 gooeyMetaballFragment(
    GooeyVertexOut in [[ stage_in ]],
    constant GooeyMetaballUniforms &uniforms [[ buffer(0) ]],
    texture2d<half, access::sample> contentTexture [[ texture(0) ]],
    texture2d<half, access::sample> sourceTexture [[ texture(1) ]]
) {
    float alpha = clamp(uniforms.viewportSizeAndAlpha.z, 0.0, 1.0);
    if (alpha <= 0.001) {
        return half4(0.0);
    }

    float smoothness = max(uniforms.viewportSizeAndAlpha.w, 1.0);
    float sourceDistance = roundedRectSDF(in.point, uniforms.sourceRect, uniforms.radiiAndTime.x);
    float distanceField = sceneSDF(in.point, uniforms, smoothness);

    float edgeBand = max(1.0, smoothness * 0.22);
    float sourceMask = 1.0 - smoothstep(-edgeBand, edgeBand, sourceDistance);
    float lensMask = 1.0 - smoothstep(-edgeBand, edgeBand, distanceField);
    float targetDistance = roundedRectSDF(in.point, uniforms.contentRect, uniforms.targetControls.x);
    float targetMask = 1.0 - smoothstep(-edgeBand, edgeBand, targetDistance);
    float targetEdge = 1.0 - smoothstep(0.0, max(edgeBand * 1.7, 2.0), abs(targetDistance));

    float phase = uniforms.radiiAndTime.w;
    float bridgeRadius = uniforms.radiiAndTime.z;
    float bridgeEnergy = clamp(bridgeRadius / max(smoothness * 1.6, 1.0), 0.0, 1.0);
    float flow = sin((in.point.x * 0.030 + in.point.y * 0.018) + phase * 6.2831853) * 0.055 * bridgeEnergy;
    lensMask = clamp(lensMask + flow * (1.0 - smoothstep(0.0, 12.0, abs(distanceField))), 0.0, 1.0);

    float normalStep = max(1.0, edgeBand * 0.42);
    float2 sdfGradient = float2(
        sceneSDF(in.point + float2(normalStep, 0.0), uniforms, smoothness)
            - sceneSDF(in.point - float2(normalStep, 0.0), uniforms, smoothness),
        sceneSDF(in.point + float2(0.0, normalStep), uniforms, smoothness)
            - sceneSDF(in.point - float2(0.0, normalStep), uniforms, smoothness)
    );
    float2 sdfNormal = sdfGradient / max(length(sdfGradient), 0.001);
    float shapeEdge = 1.0 - smoothstep(0.0, max(edgeBand * 1.45, 2.0), abs(distanceField));
    float lensInfluence = clamp(max(lensMask, shapeEdge * 0.72) * targetMask, 0.0, 1.0);

    constexpr sampler contentSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float progress = clamp(uniforms.lensControls.x, 0.0, 1.0);
    float contentAlphaControl = clamp(uniforms.lensControls.y, 0.0, 1.0);
    float blurRadius = max(0.0, uniforms.lensControls.z);
    float warp = max(0.0, uniforms.lensControls.w);
    float shapeProgress = clamp(uniforms.radiiAndTime.w, 0.0, 1.0);
    float sourceAlphaControl = 1.0 - smoothstep(0.18, 0.76, shapeProgress);
    float isOpening = step(0.5, uniforms.targetControls.y);
    float openingTargetReveal = smoothstep(0.78, 0.98, progress);
    float closingTargetReveal = 1.0 - smoothstep(0.08, 0.40, progress);
    float finalReveal = mix(closingTargetReveal, openingTargetReveal, isOpening);
    float revealMask = targetMask * clamp(max(lensInfluence, finalReveal), 0.0, 1.0);

    float2 sourceUv = (in.point - uniforms.sourceRect.xy) / max(uniforms.sourceRect.zw, float2(1.0));
    float2 finalUv = (in.point - uniforms.contentRect.xy) / max(uniforms.contentRect.zw, float2(1.0));
    float2 contentUv = finalUv;

    float2 targetCentered = contentUv - float2(0.5);
    float2 lensCenter = uniforms.menuRect.xy + uniforms.menuRect.zw * 0.5;
    float2 lensCenterUv = (lensCenter - uniforms.contentRect.xy) / max(uniforms.contentRect.zw, float2(1.0));
    float2 lensVector = contentUv - lensCenterUv;
    float radial = dot(lensVector, lensVector);
    contentUv += lensVector * lensInfluence * warp * (0.034 - radial * 0.020);
    contentUv -= sdfNormal * lensInfluence * warp * 0.030;
    contentUv += targetCentered * shapeEdge * targetMask * warp * 0.004;

    float contentBounds = insideUnitRect(contentUv);
    half4 content = sampleBlurredContent(contentTexture, contentSampler, contentUv, blurRadius);
    float contentScale = revealMask * contentAlphaControl * contentBounds * alpha;
    float contentSampleAlpha = float(content.a) * contentScale;

    float sourceBounds = insideUnitRect(sourceUv);
    half4 sourceContent = sampleBlurredContent(sourceTexture, contentSampler, sourceUv, blurRadius * 0.36);
    float sourceScale = sourceMask * sourceAlphaControl * sourceBounds * alpha;
    float sourceSampleAlpha = float(sourceContent.a) * sourceScale * (1.0 - contentSampleAlpha);

    float sampledAlpha = clamp(contentSampleAlpha + sourceSampleAlpha, 0.0, 1.0);
    float materialAlpha = max(uniforms.fillColor.a, 0.76 + bridgeEnergy * 0.05);
    float targetMaterial = revealMask * contentAlphaControl;
    float lensMaterial = lensMask * (0.58 + bridgeEnergy * 0.06) * (1.0 - targetMask * 0.08);
    float fillAlpha = materialAlpha * max(targetMaterial, lensMaterial) * alpha * (1.0 - sampledAlpha * 0.02);
    float edgeAlpha = (targetEdge * targetMaterial * 0.045 + shapeEdge * lensMask * 0.040) * alpha;
    float baseAlpha = clamp(fillAlpha + edgeAlpha * (1.0 - fillAlpha), 0.0, 1.0);
    float outAlpha = clamp(sampledAlpha + baseAlpha * (1.0 - sampledAlpha), 0.0, 1.0);
    if (outAlpha <= 0.001) {
        return half4(0.0);
    }

    float3 basePremultiplied = uniforms.fillColor.rgb * fillAlpha
        + uniforms.edgeColor.rgb * edgeAlpha * (1.0 - fillAlpha);
    float3 sampledPremultiplied = float3(content.rgb) * contentScale
        + float3(sourceContent.rgb) * sourceScale * (1.0 - contentSampleAlpha);
    float3 premultipliedRgb = sampledPremultiplied + basePremultiplied * (1.0 - sampledAlpha);

    return half4(half3(premultipliedRgb), half(outAlpha));
}

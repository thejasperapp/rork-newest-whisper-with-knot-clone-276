#include <metal_stdlib>
using namespace metal;

struct WhisperFaceVertex {
    float4 position;
    float4 normal;
    float4 color;
    float4 surface;
};
struct WhisperFaceUniforms {
    float4x4 rotation;
    float4 canvas; // origin and size in Core Image coordinates
    float4 eyes; // center, neutral eye distance, depth
    float4 anchors; // nose xy, mouth xy
    float4 animation; // time, tongue activation, yaw, pitch
};
struct WhisperFaceVarying {
    float4 position [[position]];
    float3 normal;
    float3 local;
    float3 viewPosition;
    float4 color;
    float4 surface;
};

vertex WhisperFaceVarying whisperFace3DVertex(uint id [[vertex_id]],
    const device WhisperFaceVertex *vertices [[buffer(0)]],
    constant WhisperFaceUniforms &u [[buffer(1)]]) {
    WhisperFaceVertex v = vertices[id];
    float3 p = v.position.xyz;
    float3 n = v.normal.xyz;
    float group = v.normal.w;
    float visibility = 1.0;
    if (group == 1.0 || group == 2.0) {
        float side = group == 1.0 ? -1.0 : 1.0;
        float3 pivot = float3(side * 0.78, 1.05, -0.15);
        float angle = side * (u.animation.y * 0.10) - u.animation.z * 0.09;
        float c = cos(angle), s = sin(angle);
        float3 q = p - pivot;
        p = pivot + float3(c*q.x-s*q.y, s*q.x+c*q.y, q.z);
        n = float3(c*n.x-s*n.y, s*n.x+c*n.y, n.z);
    } else if (group == 3.0) {
        float extension = 0.10 + 0.90 * u.animation.y;
        p.y *= extension;
        p.z += 0.10 * u.animation.y * pow(clamp(-p.y, 0.0, 1.0), 2.0);
        n = normalize(float3(n.x, n.y / extension, n.z));
        visibility = smoothstep(0.01, 0.12, u.animation.y);
    } else if (group >= 4.0) {
        float a = (group - 4.0) * 1.25663706 + u.animation.x * 0.65;
        float spin = u.animation.x * 0.4 + group;
        float c = cos(spin), s = sin(spin);
        p = float3(c*p.x-s*p.y, s*p.x+c*p.y, p.z);
        n = float3(c*n.x-s*n.y, s*n.x+c*n.y, n.z);
        p += float3(1.38*cos(a), 1.67 + 0.27*sin(a*2.0), -0.28 + 0.83*sin(a));
    }
    float3 q = (u.rotation * float4(p, 0)).xyz;
    float3 normal = normalize((u.rotation * float4(n, 0)).xyz);
    float2 anchor = u.eyes.xy;
    float zOffset = 0;
    if (v.position.w == 1.0) { anchor = u.anchors.xy; zOffset = 0.34; }
    if (v.position.w == 2.0) { anchor = u.anchors.zw; zOffset = 0.22; }
    // Local perspective retains measured eye/nose/mouth anchors without requiring
    // ARSession ownership or persisting a biometric tracking timeline.
    float perspective = 8.0 / max(4.0, 8.0 - q.z);
    float2 pixel = anchor + q.xy * u.eyes.z * perspective;
    float2 ndc = (pixel - u.canvas.xy) / u.canvas.zw * 2.0 - 1.0;
    float depth = clamp(u.eyes.w - (q.z + zOffset) * 0.025, 0.01, 0.99);
    WhisperFaceVarying out;
    out.position = float4(ndc, depth, 1);
    out.normal = normal;
    out.local = v.position.xyz;
    out.viewPosition = q;
    out.color = float4(v.color.rgb, v.color.a * visibility);
    out.surface = v.surface;
    return out;
}

fragment float4 whisperFace3DFragment(WhisperFaceVarying in [[stage_in]]) {
    if (in.color.a < 0.01) { discard_fragment(); }
    float3 view = normalize(float3(0, 0, 8) - in.viewPosition);
    float3 n = normalize(in.normal);
    if (dot(n, view) < 0) { n = -n; }
    float3 light = normalize(float3(-0.45, 0.7, 1.0));
    float3 halfVector = normalize(light + view);
    float roughness = clamp(in.surface.x, 0.08, 1.0);
    float metalness = in.surface.y;
    float3 pigment = in.color.rgb;
    if (in.surface.w < -1.5) {
        float coating = pow(1.0 - max(dot(n, view), 0.0), 2.0);
        pigment = mix(pigment, float3(0.50, 0.32, 0.16), coating * 0.65);
    } else if (in.surface.w < -0.5) {
        float grain = sin(in.local.x*23.0 + sin(in.local.y*19.0)*1.7) * sin(in.local.z*31.0 + in.local.y*27.0);
        float fleck = smoothstep(0.15, 0.65, grain);
        pigment = mix(pigment * 0.38, float3(0.52, 0.29, 0.12), fleck);
    }
    float3 base = pow(max(pigment, float3(0)), float3(2.2));
    float ndl = max(dot(n, light), 0.0);
    float ndv = max(dot(n, view), 0.001);
    float ndh = max(dot(n, halfVector), 0.0);
    float a2 = pow(roughness, 4.0);
    float denominator = ndh*ndh*(a2-1.0)+1.0;
    float distribution = a2 / max(0.001, 3.14159265*denominator*denominator);
    float3 f0 = mix(float3(0.04), base, metalness);
    float3 fresnel = f0 + (1.0-f0)*pow(1.0-max(dot(view,halfVector),0.0),5.0);
    float k = pow(roughness+1.0,2.0)/8.0;
    float geometry = (ndl/(ndl*(1.0-k)+k)) * (ndv/(ndv*(1.0-k)+k));
    float3 specular = distribution * geometry * fresnel / max(0.02, 4.0*ndl*ndv);
    float fill = 0.22 * max(dot(n,normalize(float3(0.8,-0.2,0.6))),0.0);
    float3 color = base * (0.32 + 0.88*ndl + fill) * (1.0-metalness*0.55) + specular * ndl * 1.8;
    // Analytic studio softboxes: reflections change with the actual surface normal.
    float3 reflection = reflect(-view,n);
    float softbox = pow(max(dot(reflection,normalize(float3(-0.6,0.9,1.0))),0.0),32.0);
    float rim = pow(1.0-ndv,3.0);
    color += mix(float3(0.45),base,metalness) * softbox * (1.0-roughness) * 1.6;
    color += float3(0.34,0.48,0.60) * rim * (0.10 + metalness*0.32);
    if (in.surface.w > 0.0) {
        float fibers = sin(in.local.x*270.0 + sin(in.local.y*71.0)*2.0) * sin(in.local.y*310.0 + in.local.z*83.0);
        float aa = 1.0 - smoothstep(0.01,0.05,length(fwidth(in.local)));
        color *= 1.0 + fibers * 0.045 * aa;
        color += base * rim * 0.24;
    }
    color += base * in.surface.z;
    color = color / (1.0 + color*0.28);
    return float4(color * in.color.a, in.color.a);
}

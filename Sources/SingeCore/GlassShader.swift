import Foundation

/// The Singe glass: Sorph's orb flattened into a rounded bar. A refracting bevel,
/// a Fresnel rim in the ribbon hues, a specular glint, and three ribbons that are
/// ray-marched through the slab so they fold and turn in depth like the orb's.
/// Ported from mockups/singe-design.html; keep the two in step.
enum GlassShader {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 res;      // drawable size, pixels
        float scale;     // backing scale factor
        float t;         // seconds
        float flow;      // integrated ribbon phase
        float dark;      // 1 = dark glass
        float pulse;     // 1 on open, decays to 0
        float radius;    // corner radius, points
        float calm;      // ribbon strength behind a term
        float3 c1;
        float3 c2;
        float3 c3;
    };

    struct VOut { float4 pos [[position]]; };

    vertex VOut glass_vertex(uint vid [[vertex_id]]) {
        float2 p[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
        VOut o; o.pos = float4(p[vid], 0, 1); return o;
    }

    float sdBox(float2 p, float2 b, float r) {
        float2 q = abs(p) - b + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }
    float ph(float x, float k) { return fmod(x * k, 6.2831853); }
    float3x3 rotY(float a) { float c = cos(a), s = sin(a); return float3x3(float3(c, 0, -s), float3(0, 1, 0), float3(s, 0, c)); }
    float3x3 rotX(float a) { float c = cos(a), s = sin(a); return float3x3(float3(1, 0, 0), float3(0, c, s), float3(0, -s, c)); }
    float hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

    // Sorph's ribbon: a thin sheet in 3D, bent by two waves and cut to a strip.
    // `reach` widens the strip so the ribbons span a wide bar instead of a sphere.
    float ribbon(float3 p, float3 A, float3 B, float3 C, float3 D, float phs, float amp, float spd,
                 float width, float reach, float flow) {
        float f = dot(p, A) + amp * sin(dot(p, B) * 2.6 + ph(flow, 0.9 * spd) + phs)
                + amp * 0.55 * sin(dot(p, C) * 4.1 - ph(flow, 1.4 * spd));
        float g = (dot(p, D) + 0.35 * sin(dot(p, B) * 1.7 - ph(flow, 0.6 * spd) + phs * 0.5)) / reach;
        float core = exp(-f * f / (width * width));
        float halo = exp(-f * f / (width * width * 6.0)) * 0.035;
        return (core + halo) * exp(-g * g / 0.16);
    }

    fragment float4 glass_fragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float2 frag = float2(in.pos.x, u.res.y - in.pos.y);   // bottom-left origin, like the mock-up
        float dpr = u.scale;
        float2 p = frag - u.res * 0.5;
        float2 hb = u.res * 0.5 - float2(1.0 * dpr);
        float r = min(u.radius * dpr, hb.y);
        float d = sdBox(p, hb, r);
        float cover = clamp(0.5 - d, 0.0, 1.0);
        if (cover <= 0.0) { return float4(0); }
        float e = max(-d, 0.0);

        // glass bevel: steep at the rim, flat in the middle
        float bevel = min(hb.y * 0.8, 7.0 * dpr);
        float2 g = float2(sdBox(p + float2(1, 0), hb, r) - sdBox(p - float2(1, 0), hb, r),
                          sdBox(p + float2(0, 1), hb, r) - sdBox(p - float2(0, 1), hb, r)) * 0.5;
        float s = 1.0 - clamp(e / bevel, 0.0, 1.0);
        float2 wob = 0.05 * float2(sin(p.y / dpr * 0.35 + u.t * 1.3), cos(p.x / dpr * 0.12 - u.t * 0.9)) * s;
        float2 nxy = g * pow(s, 1.6) * 0.92 + wob;
        float nz = sqrt(max(0.0, 1.0 - dot(nxy, nxy)));
        float3 n = float3(nxy, nz);
        float fres = pow(1.0 - nz, 2.2);

        // march through the slab the way Sorph marches through its sphere
        float aspect = hb.x / hb.y;
        float lv = 0.18 + 0.6 * u.pulse;
        float amp = 0.16 + 0.26 * lv;
        float width = 0.05 + 0.012 * lv;
        float reach = 1.0 + 0.55 * aspect;
        float3x3 M = rotY(ph(u.t, 0.18)) * rotX(0.35 + 0.15 * sin(ph(u.t, 0.3)));
        float2 base = (p / hb.y) * 0.9 - nxy * 0.35;
        const int STEPS = 36;
        float depth = 0.75;
        float dt = 2.0 * depth / float(STEPS);
        float dither = hash(frag + fract(u.t) * 17.0);
        float3 inner = float3(0);
        for (int i = 0; i < STEPS; i++) {
            float z = -depth + (float(i) + dither) * dt;
            float3 q = M * float3(base, z);
            float r1 = ribbon(q, float3(0, 1, 0), float3(1, 0.2, 0.3), float3(0.4, 0, 1), float3(1, 0, 0), 0.0, amp, 1.0, width, reach, u.flow);
            float r2 = ribbon(q, float3(0.3, 0.8, 0.5), float3(0.2, 1, -0.4), float3(1, 0.3, 0), float3(0, 0, 1), 2.1, amp * 0.9, 0.85, width, reach, u.flow);
            float r3 = ribbon(q, float3(-0.6, 0.5, 0.6), float3(0.5, -0.3, 1), float3(0, 1, 0.4), float3(0.8, 0.6, 0), 4.2, amp * 1.1, 1.15, width * 0.9, reach, u.flow);
            float dz = clamp(abs(z) / depth, 0.0, 1.0);
            float3 tint = mix(float3(1), float3(0.92, 0.94, 1.0), dz);
            inner += ((u.c1 + 0.7 * r1) * r1 + (u.c2 + 0.7 * r2) * r2 + (u.c3 + 0.8 * r3) * r3) * tint * (1.0 - 0.35 * dz);
        }
        inner *= dt * (1.1 + 1.1 * lv + 0.9 * u.pulse) * 1.5 * u.calm;

        float3 L = normalize(float3(-0.5, 0.8, 0.6));
        float spec = pow(max(0.0, dot(n, normalize(L + float3(0, 0, 1)))), 70.0) * (0.6 + 0.6 * s);
        float3 rimCol = normalize(u.c1 + u.c3 + 0.001) * 1.15;
        float3 col; float alpha;
        if (u.dark > 0.5) {
            col = float3(0.025, 0.028, 0.05) + inner + rimCol * fres * 0.75 + float3(spec);
            col += float3(0.04, 0.045, 0.06) * smoothstep(0.55, 1.0, frag.y / u.res.y);
            col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);   // ACES, as in Sorph
            // solid enough to hide the original word and the app's own selection beneath
            alpha = 0.97;
        } else {
            float a = clamp(dot(inner, float3(0.5)), 0.0, 1.0);
            float3 hue = inner / (max(max(inner.r, inner.g), inner.b) + 1e-3);
            hue = clamp(mix(float3(dot(hue, float3(0.333))), hue, 2.4), 0.0, 1.0);
            // a pale lavender body so the bar reads on white pages
            float3 body = mix(float3(0.90, 0.91, 0.96), float3(0.96, 0.965, 0.985), smoothstep(0.0, 1.0, frag.y / u.res.y));
            col = mix(body, hue * 0.70, a * 0.85);
            col = mix(col, rimCol * 0.40, fres * 0.8) + float3(spec * 0.9);
            col *= 1.0 - 0.30 * smoothstep(1.6 * dpr, 0.0, e);   // a visible edge line
            alpha = 0.98;
        }
        col = clamp(col, 0.0, 1.0);
        alpha = clamp(alpha, 0.0, 1.0) * cover;
        return float4(col * alpha, alpha);
    }

    // ---- Sorph's orb: the same glass as a sphere (mockups/sorph-logo, variant B)
    struct OrbUniforms {
        float2 res;
        float t;
        float flow;
        float pulse;
        float calm;
        float curve;     // how much of the sphere's curvature the glass normal follows
        float rimK;
        float specK;
        float depthK;
        float widthK;
        float tilt;
        float3 c1;
        float3 c2;
        float3 c3;
    };

    fragment float4 orb_fragment(VOut in [[stage_in]], constant OrbUniforms &u [[buffer(0)]]) {
        float2 frag = float2(in.pos.x, u.res.y - in.pos.y);
        float dpr = u.res.x / 300.0;
        float2 p = frag - u.res * 0.5;
        float R = u.res.x * 0.5 - 1.0 * dpr;
        float d = length(p) - R;
        float cover = clamp(0.5 - d, 0.0, 1.0);
        if (cover <= 0.0) { return float4(0); }
        float2 q = p / R;
        float rr = min(dot(q, q), 1.0);
        float sz = sqrt(1.0 - rr);
        float3 n = normalize(mix(float3(0, 0, 1), float3(q, sz), u.curve));
        float2 nxy = n.xy;
        float fres = pow(1.0 - n.z, 2.2);
        float lv = 0.18 + 0.6 * u.pulse;
        float amp = 0.16 + 0.26 * lv;
        float width = (0.05 + 0.012 * lv) * u.widthK;
        float reach = 1.55;
        float3x3 M = rotY(ph(u.t, 0.18)) * rotX(0.35 + u.tilt + 0.15 * sin(ph(u.t, 0.3)));
        float2 base = q * 0.9 - nxy * 0.35;
        const int STEPS = 40;
        float depth = u.depthK * (0.35 + 0.65 * sz);
        float dt = 2.0 * depth / float(STEPS);
        float dither = hash(frag);
        float3 inner = float3(0);
        for (int i = 0; i < STEPS; i++) {
            float z = -depth + (float(i) + dither) * dt;
            float3 qq = M * float3(base, z);
            float r1 = ribbon(qq, float3(0, 1, 0), float3(1, 0.2, 0.3), float3(0.4, 0, 1), float3(1, 0, 0), 0.0, amp, 1.0, width, reach, u.flow);
            float r2 = ribbon(qq, float3(0.3, 0.8, 0.5), float3(0.2, 1, -0.4), float3(1, 0.3, 0), float3(0, 0, 1), 2.1, amp * 0.9, 0.85, width, reach, u.flow);
            float r3 = ribbon(qq, float3(-0.6, 0.5, 0.6), float3(0.5, -0.3, 1), float3(0, 1, 0.4), float3(0.8, 0.6, 0), 4.2, amp * 1.1, 1.15, width * 0.9, reach, u.flow);
            float dz = clamp(abs(z) / max(depth, 0.001), 0.0, 1.0);
            float3 tint = mix(float3(1), float3(0.92, 0.94, 1.0), dz);
            inner += ((u.c1 + 0.7 * r1) * r1 + (u.c2 + 0.7 * r2) * r2 + (u.c3 + 0.8 * r3) * r3) * tint * (1.0 - 0.35 * dz);
        }
        inner *= dt * (1.1 + 1.1 * lv + 0.9 * u.pulse) * 1.5 * u.calm;
        float3 L = normalize(float3(-0.5, 0.8, 0.6));
        float sp = max(0.0, dot(n, normalize(L + float3(0, 0, 1))));
        float spec = pow(sp, 70.0) * u.specK + pow(sp, 12.0) * 0.06 * u.specK;
        float3 rimCol = normalize(u.c1 + u.c3 + 0.001) * 1.15;
        float3 col = float3(0.025, 0.028, 0.05) + inner + rimCol * fres * 0.75 * u.rimK + float3(spec);
        col += float3(0.04, 0.045, 0.06) * smoothstep(0.1, 1.0, q.y) * 0.8;
        col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
        float alpha = 0.97 * cover;
        return float4(col * alpha, alpha);
    }
    """
}

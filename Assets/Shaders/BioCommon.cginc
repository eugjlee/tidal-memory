#ifndef BIO_COMMON_INCLUDED
#define BIO_COMMON_INCLUDED

float SurfHash21(float2 p)
{
    float3 q = frac(float3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return frac((q.x + q.y) * q.z);
}

float2 SurfHash22(float2 p)
{
    float3 q = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return frac((q.xx + q.yz) * q.zy);
}

float SurfVNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);

    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return lerp(
        lerp(SurfHash21(i), SurfHash21(i + float2(1, 0)), f.x),
        lerp(SurfHash21(i + float2(0, 1)), SurfHash21(i + float2(1, 1)), f.x), f.y);
}

float SurfFbm(float2 p)
{
    return 0.533 * SurfVNoise(p)
         + 0.300 * SurfVNoise(p * 2.13 + 7.7)
         + 0.167 * SurfVNoise(p * 4.71 + 13.1);
}

float SurfCells(float2 p)
{
    float2 ip = floor(p);
    float2 fr = frac(p);
    float f1 = 8.0;
    [unroll]
    for (int cy = -1; cy <= 1; cy++)
    [unroll]
    for (int cx = -1; cx <= 1; cx++)
    {
        float2 g = float2(cx, cy);
        float2 o = SurfHash22(ip + g);
        float2 r = g + o - fr;
        f1 = min(f1, dot(r, r));
    }
    return saturate(1.0 - sqrt(f1));
}

float SurfRipple(float2 uv, float t, float scale, float amp, float speed)
{
    float2 sq = float2(0.32, 1.0);
    float h;
    h  = 0.600 * (SurfVNoise(uv * scale * sq
                + float2(0.09, -0.31) * t * speed) - 0.5);
    h += 0.200 * (SurfVNoise(uv * scale * sq * 2.17 + 7.3
                + float2(-0.17, 0.23) * t * speed * 1.6) - 0.5);
    h += 0.070 * (SurfVNoise(uv * scale * sq * 4.63 + 19.1
                + float2(0.27, 0.11) * t * speed * 2.4) - 0.5);
    h += 0.025 * (SurfVNoise(uv * scale * sq * 9.11 + 41.7
                + float2(-0.07, -0.19) * t * speed * 3.1) - 0.5);
    return h * amp;
}

float2 SurfCellF1F2(float2 p)
{
    float2 ip = floor(p);
    float2 fr = frac(p);
    float f1 = 8.0;
    float f2 = 8.0;
    [unroll]
    for (int cy = -1; cy <= 1; cy++)
    [unroll]
    for (int cx = -1; cx <= 1; cx++)
    {
        float2 g = float2(cx, cy);
        float2 o = SurfHash22(ip + g);
        float d = length(g + o - fr);
        if (d < f1) { f2 = f1; f1 = d; }
        else if (d < f2) { f2 = d; }
    }
    return float2(f1, f2);
}

float SurfFoamWalls(float2 p, float thickness)
{
    float2 f = SurfCellF1F2(p);
    return 1.0 - smoothstep(0.0, max(thickness, 1e-3), f.y - f.x);
}

float SurfFoamRaft(float2 uv, float2 fl, float adv, float scale)
{
    float2 p = uv - fl * adv;

    float sv = 0.62 + 0.76 * SurfFbm(p * 9.0);

    float w = SurfFoamWalls(p * scale * sv * float2(0.85, 1.0), 0.16);
    w = max(w, SurfFoamWalls(p * scale * sv * 2.7 + 17.3, 0.13) * 0.80);
    w = max(w, SurfFoamWalls(p * scale * sv * 6.3 + 41.7, 0.10) * 0.55);

    w *= 0.35 + 0.85 * SurfFbm(p * scale * 0.55 + 71.3);

    float cover = smoothstep(0.28, 0.74, SurfFbm(p * 14.0 + 5.5));
    return saturate(w * (0.20 + 1.20 * cover));
}

#endif

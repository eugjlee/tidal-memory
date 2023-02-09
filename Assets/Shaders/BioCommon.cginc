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

float2 SurfLimit(float2 v, float vmax)
{
    float s = length(v);
    if (s < 1e-6 || vmax < 1e-6)
        return v;
    return v * (vmax * tanh(s / vmax) / s);
}

float SurfCapsule(float2 uv, float4 seg, float radius)
{
    float2 pa = uv - seg.xy;
    float2 ba = seg.zw - seg.xy;
    float k = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    float d = length(pa - ba * k);
    float m = saturate(1.0 - d / max(radius, 1e-4));
    return m * m;
}

float _SurfTime;

sampler2D _BioHeightTex;
sampler2D _BioFlowTex;
sampler2D _BioEnergyTex;
sampler2D _BioGlowTex;
sampler2D _CurrentDyeTex;
float4 _BioFloorSize;
float2 _BioTexel;

float _SpawnFilamentGain;
float _SpawnEnergyGain;
float _SpawnCrestGain;
float _SpawnCrestThreshold;
float _SpawnCurrentGain;

float4 _PigmentBlue;
float4 _PigmentViolet;
float4 _PigmentMagenta;
float4 _PigmentCrimson;
float4 _PigmentGold;
float _PigmentMix;
float _PigmentScale;
float _GoldAmount;

float3 BioPigment(float2 uv, float2 flow, out float gold)
{

    float2 q = uv * _BioFloorSize.xy / max(_PigmentScale, 1e-3) + flow * 4.0;

    float h = SurfFbm(q + float2(_SurfTime * 0.006, -_SurfTime * 0.004));

    h += (SurfFbm(q * 3.7 + 19.3) - 0.5) * 0.28;

    h = saturate(0.5 + (h - 0.55) * 2.6);

    h = pow(h, 1.70);
    h = lerp(0.18, h, _PigmentMix);

    float3 c = lerp(_PigmentBlue.rgb, _PigmentViolet.rgb, smoothstep(0.14, 0.46, h));
    c = lerp(c, _PigmentMagenta.rgb, smoothstep(0.44, 0.70, h));
    c = lerp(c, _PigmentCrimson.rgb, smoothstep(0.72, 0.94, h));

    float2 gp = uv * _BioFloorSize.xy + flow * 3.0;
    gp += (float2(SurfFbm(gp * 0.9 + 5.1), SurfFbm(gp * 0.9 + 27.3)) - 0.5) * 1.0;
    float cells = SurfCells(gp + float2(0.0, _SurfTime * 0.01));
    float fray = 0.85 + 0.30 * SurfFbm(gp * 4.5 + _SurfTime * 0.05);
    float rare = smoothstep(0.50, 0.62, SurfFbm(uv * _BioFloorSize.xy * 0.55 + 71.7));
    float dens = tex2Dlod(_CurrentDyeTex, float4(uv, 0, 0)).r;

    gold = smoothstep(0.74, 0.94 - _GoldAmount * 0.20, cells * fray)
         * rare
         * smoothstep(0.0, 0.04, _GoldAmount)
         * smoothstep(0.10, 0.35, dens);
    return lerp(c, _PigmentGold.rgb, gold);
}

float SurfSpawnDensity(float2 uv)
{
    float2 e = tex2Dlod(_BioEnergyTex, float4(uv, 0, 0)).rg;
    float2 tx = _BioTexel;

    float er = tex2Dlod(_BioEnergyTex, float4(uv + float2(tx.x, 0), 0, 0)).r;
    float el = tex2Dlod(_BioEnergyTex, float4(uv - float2(tx.x, 0), 0, 0)).r;
    float eu = tex2Dlod(_BioEnergyTex, float4(uv + float2(0, tx.y), 0, 0)).r;
    float ed = tex2Dlod(_BioEnergyTex, float4(uv - float2(0, tx.y), 0, 0)).r;
    float edge = saturate(length(float2(er - el, eu - ed)) * _SpawnFilamentGain);

    float2 hg = float2(
        tex2Dlod(_BioHeightTex, float4(uv + float2(tx.x, 0), 0, 0)).r
      - tex2Dlod(_BioHeightTex, float4(uv - float2(tx.x, 0), 0, 0)).r,
        tex2Dlod(_BioHeightTex, float4(uv + float2(0, tx.y), 0, 0)).r
      - tex2Dlod(_BioHeightTex, float4(uv - float2(0, tx.y), 0, 0)).r);

    float slope = length(hg) / max(tx.x, 1e-5);
    float crest = saturate((slope - _SpawnCrestThreshold) * 0.02);
    crest *= smoothstep(0.35, 0.85, SurfFbm(uv * 190.0 + _SurfTime * 0.07));
    crest *= crest;

    float corridor = tex2Dlod(_CurrentDyeTex, float4(uv, 0, 0)).r;

    float skirt = tex2Dlod(_BioGlowTex, float4(uv, 0, 0)).r;

    float drive = saturate(e.r * _SpawnEnergyGain
                         + crest * _SpawnCrestGain
                         + e.g * 0.12
                         + skirt * 0.55
                         + corridor * _SpawnCurrentGain);

    float dens = pow(drive, 1.7) * (0.45 + 1.5 * edge);

    float patch = SurfCells(uv * 55.0 + float2(0.0, -_SurfTime * 0.25));
    return saturate(dens * (0.82 + 0.30 * patch));
}

float SurfElevation(float2 uv, float depth)
{
    return 0.0;
}

#endif

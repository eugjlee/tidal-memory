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

#endif

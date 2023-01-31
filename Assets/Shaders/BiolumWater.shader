Shader "BioFloor/BiolumWater"
{
    Properties { _Exposure ("Exposure", Range(0, 4)) = 1 }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" }
        Pass
        {
            ZWrite On
            Cull Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            #include "BioCommon.cginc"

            float _Exposure;
            float4 _DeepColor;
            float4 _WaterColor;
            float4 _CyanColor;
            float4 _DimColor;
            float4 _HotColor;
            float _BaseDetail;
            float _SurfaceRelief;
            float _SurfaceSheen;
            float _MacroScale, _MacroSpeed;
            float _MediumScale, _MediumSpeed;
            float _MicroScale, _MicroSpeed;
            float _RippleGain;
            float _RippleWidth;
            float _CrestThreshold;
            float _CrestPower;
            float _PlanktonFloor;
            float _BioSurfaceDistortion;
            float _EdgeGain;
            float _HotspotGain;
            float _CurrentIntensity;
            float _MemoryGain;
            float _ScatterGain;
            float _SparkleGain;
            int _DebugView;

            struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                float2 uv = i.uv;
                float t = _SurfTime;
                float2 tx = _BioTexel;

                float2 h = tex2D(_BioHeightTex, uv).rg;
                float4 flow = tex2D(_BioFlowTex, uv);

                float2 hgD = float2(
                    tex2D(_BioHeightTex, uv + float2(tx.x, 0)).r - tex2D(_BioHeightTex, uv - float2(tx.x, 0)).r,
                    tex2D(_BioHeightTex, uv + float2(0, tx.y)).r - tex2D(_BioHeightTex, uv - float2(0, tx.y)).r);
                float2 bioUv = uv + hgD * _BioSurfaceDistortion;
                float2 en = tex2D(_BioEnergyTex, bioUv).rg;
                float scat = tex2D(_BioGlowTex, uv).r;

                if (_DebugView == 2) return float4(0.5 + h.r * 4.0, 0.5 + h.r * 4.0, 0.5 + h.r * 4.0, 1);
                if (_DebugView == 3) return float4(0.5 + flow.rg * 3.0, 0.5, 1);
                if (_DebugView == 4) return float4(en.rrr, 1);
                if (_DebugView == 5) return float4(en.ggg, 1);
                if (_DebugView == 6) return float4(tex2D(_CurrentDyeTex, uv).rrr, 1);
                if (_DebugView == 7) return float4(SurfSpawnDensity(uv).xxx, 1);

                float m1 = SurfFbm((uv + float2(0.80, -0.60) * t * _MacroSpeed) * _MacroScale);
                float detail = (m1 - 0.5) * 0.6;

                float2 fdir = float2(0.9397, 0.3420);
                float2 fperp = float2(-fdir.y, fdir.x);
                float2 fp = float2(dot(uv, fdir), dot(uv, fperp));

                fp += (float2(SurfFbm(uv * 1.7 + t * 0.008),
                              SurfFbm(uv * 1.7 + 31.7 - t * 0.006)) - 0.5) * 0.18;

                #define WHEIGHT(p) (SurfRipple((p), t, _MediumScale, 0.66, 0.9) \
                                  + SurfRipple((p) + 7.31, t, _MicroScale * 0.55, 0.34, 2.2))
                float de = 0.0016;
                float hL = WHEIGHT(fp - float2(de, 0));
                float hR = WHEIGHT(fp + float2(de, 0));
                float hD = WHEIGHT(fp - float2(0, de));
                float hU = WHEIGHT(fp + float2(0, de));

                float3 wn = normalize(float3(
                    (hL - hR) * _SurfaceRelief - hgD.x * _SurfaceRelief * 9.0,
                    1.0,
                    (hD - hU) * _SurfaceRelief - hgD.y * _SurfaceRelief * 9.0));

                float3 wl = normalize(float3(0.55, 0.28, 0.79));
                float wlit = saturate(dot(wn, wl));
                float wspec = pow(wlit, 22.0);

                float3 col = lerp(_DeepColor.rgb, _WaterColor.rgb, saturate(0.5 + detail * _BaseDetail));
                col *= 0.55 + 0.9 * wlit;
                col += _WaterColor.rgb * wspec * _SurfaceSheen;

                float2 hg = float2(
                    tex2D(_BioHeightTex, uv + float2(tx.x, 0)).r - tex2D(_BioHeightTex, uv - float2(tx.x, 0)).r,
                    tex2D(_BioHeightTex, uv + float2(0, tx.y)).r - tex2D(_BioHeightTex, uv - float2(0, tx.y)).r);
                float slope = length(hg) / max(tx.x, 1e-5);

                float crest = saturate((slope - _CrestThreshold) * _RippleWidth);

                crest = pow(crest, _CrestPower);

                float breakup = lerp(0.35, 1.0,
                    smoothstep(0.25, 0.85, SurfFbm(uv * _MicroScale * 1.15 + flow.rg * 6.0 + t * 0.05)));
                breakup *= lerp(0.5, 1.0, SurfFbm(uv * _MicroScale * 0.14 + 17.3));
                crest *= breakup;

                float fast = en.r;
                float mem = en.g;

                float er = tex2D(_BioEnergyTex, uv + float2(tx.x, 0)).r;
                float el = tex2D(_BioEnergyTex, uv - float2(tx.x, 0)).r;
                float eu = tex2D(_BioEnergyTex, uv + float2(0, tx.y)).r;
                float ed = tex2D(_BioEnergyTex, uv - float2(0, tx.y)).r;
                float edge = length(float2(er - el, eu - ed)) / max(tx.x, 1e-5) * 0.002;
                edge = saturate(edge) * _EdgeGain;
                edge *= smoothstep(0.25, 0.7, SurfFbm(uv * 26.0 + 11.7));

                float sparkle = SurfCells(uv * 260.0 + float2(0.0, -t * 0.2));
                sparkle = pow(saturate(sparkle), 6.0) * _SparkleGain * saturate(fast * 2.0 + flow.b);

                float curDye = tex2D(_CurrentDyeTex, bioUv).r;

                float bodyMed = 0.40 + 0.60 * SurfFbm(bioUv * 22.0 + flow.rg * 2.0 + _SurfTime * 0.02);
                float bodyFine = 0.55 + 0.45 * SurfFbm(bioUv * 110.0 - _SurfTime * 0.015);

                float grain = 0.52 + 0.68 * SurfCells(bioUv * 180.0 + flow.rg * 3.0);

                float body = pow(saturate(curDye), 1.35) * bodyMed * bodyFine * grain;

                float cR = tex2D(_CurrentDyeTex, bioUv + float2(tx.x, 0)).r;
                float cL = tex2D(_CurrentDyeTex, bioUv - float2(tx.x, 0)).r;
                float cU = tex2D(_CurrentDyeTex, bioUv + float2(0, tx.y)).r;
                float cD = tex2D(_CurrentDyeTex, bioUv - float2(0, tx.y)).r;
                float dyeEdge = saturate(length(float2(cR - cL, cU - cD)) / max(tx.x, 1e-5) * 0.0035);
                dyeEdge *= smoothstep(0.30, 0.72, SurfFbm(bioUv * 70.0 + flow.rg * 3.0 + 5.7));

                float plankton = saturate(_PlanktonFloor + curDye + fast * 0.4 + mem * 0.3);
                float visibleRipple = crest * plankton * _RippleGain;

                float wMean = (tex2D(_CurrentDyeTex, bioUv + float2( tx.x,  tx.y) * 6.0).r
                             + tex2D(_CurrentDyeTex, bioUv + float2(-tx.x,  tx.y) * 6.0).r
                             + tex2D(_CurrentDyeTex, bioUv + float2( tx.x, -tx.y) * 6.0).r
                             + tex2D(_CurrentDyeTex, bioUv + float2(-tx.x, -tx.y) * 6.0).r) * 0.25;
                float wMean2 = (tex2D(_CurrentDyeTex, bioUv + float2( tx.x, 0) * 2.5).r
                              + tex2D(_CurrentDyeTex, bioUv - float2( tx.x, 0) * 2.5).r
                              + tex2D(_CurrentDyeTex, bioUv + float2(0,  tx.y) * 2.5).r
                              + tex2D(_CurrentDyeTex, bioUv - float2(0,  tx.y) * 2.5).r) * 0.25;

                float spine = saturate((curDye - wMean) * 6.0) * 0.7
                            + saturate((curDye - wMean2) * 9.0) * 0.55;

                float shimmer = 0.25 + 0.95 * SurfFbm(bioUv * 90.0 + flow.rg * 8.0 + _SurfTime * 0.35);
                shimmer *= smoothstep(0.18, 0.80, SurfFbm(bioUv * 260.0 + float2(_SurfTime * 0.9, -_SurfTime * 0.6)));
                spine = pow(spine, 1.35) * shimmer;

                spine *= 1.0 + fast * 2.0;

                float e = fast + body * _CurrentIntensity + dyeEdge * _EdgeGain * 0.5
                        + spine * 1.7
                        + visibleRipple + edge + mem * _MemoryGain;
                float lowBand = smoothstep(0.02, 0.35, e);
                float hotBand = smoothstep(0.75, 1.6, e) * _HotspotGain;

                float dimBand = smoothstep(0.03, 0.28, e);
                float midBand = smoothstep(0.30, 0.72, e);

                float3 glow = _DimColor.rgb * dimBand * 0.85;
                glow += _CyanColor.rgb * midBand * (0.55 + 0.9 * e);
                glow += _HotColor.rgb * hotBand;
                glow += _CyanColor.rgb * sparkle;

                glow += _DimColor.rgb * scat * _ScatterGain;

                col += glow;
                return float4(col * _Exposure, 1.0);
            }
            ENDCG
        }
    }
}

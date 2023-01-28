Shader "Hidden/BioFloor/Sim"
{
    Properties { _MainTex ("Previous State", 2D) = "black" {} }
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        CGINCLUDE
        #include "UnityCG.cginc"
        #include "BioCommon.cginc"

        #define MAX_DISTURBANCE 32
        float4 _Disturb[MAX_DISTURBANCE];
        float4 _DisturbDir[MAX_DISTURBANCE];
        int _DisturbCount;

        float _Dt;
        float _FixedDt;
        float4 _TexelSize;

        struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; };
        struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };

        v2f vert(appdata v)
        {
            v2f o;
            o.pos = UnityObjectToClipPos(v.vertex);
            o.uv = v.uv;
            return o;
        }

        float DisturbFootprint(float2 uv, int k)
        {
            float4 D = _Disturb[k];
            float2 d = uv - D.xy;

            float2 dir = _DisturbDir[k].xy;
            float len = length(dir);
            if (len > 1e-4)
            {
                dir /= len;
                float2 perp = float2(-dir.y, dir.x);

                d = float2(dot(d, dir) / 1.8, dot(d, perp));
            }

            float r = length(d) / max(D.w, 1e-5);
            return exp(-r * r * 2.5);
        }
        ENDCG

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            sampler2D _MainTex;
            float _WaveSpeed;
            float _Damping;
            float _ImpulseStrength;
            float _SustainedPush;
            float _SustainedRate;

            float4 frag(v2f i) : SV_Target
            {
                float2 uv = i.uv;
                float2 tx = _TexelSize.xy;

                float2 s = tex2D(_MainTex, uv).rg;
                float h = s.r;
                float v = s.g;

                float hl = tex2D(_MainTex, uv - float2(tx.x, 0)).r;
                float hr = tex2D(_MainTex, uv + float2(tx.x, 0)).r;
                float hd = tex2D(_MainTex, uv - float2(0, tx.y)).r;
                float hu = tex2D(_MainTex, uv + float2(0, tx.y)).r;

                float lap = (hl + hr + hd + hu) - 4.0 * h;

                float dt = _FixedDt;

                float c = _WaveSpeed / dt;
                v += lap * (c * c) * dt;
                v *= exp(-dt / max(_Damping, 1e-3));
                h += v * dt;

                h *= exp(-dt / 3.5);

                [loop]
                for (int k = 0; k < _DisturbCount; k++)
                {
                    if (_Disturb[k].z <= 0.0)
                        continue;
                    float fp = DisturbFootprint(uv, k);
                    if (fp < 0.002)
                        continue;

                    if (_DisturbDir[k].z > 0.5)
                        v -= fp * _Disturb[k].z * _ImpulseStrength * dt
                           * _SustainedPush * sin(_SurfTime * _SustainedRate + _Disturb[k].x * 40.0);
                    else
                        v -= fp * _Disturb[k].z * _ImpulseStrength * 0.03;
                }

                h = clamp(h, -1.0, 1.0);
                v = clamp(v, -4.0, 4.0);
                return float4(h, v, 0, 1);
            }
            ENDCG
        }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            float _FlowScale;
            float _FlowSpeed;
            float _FlowDrift;
            float4 _FlowBias;
            float _SwirlRadius;
            float _SwirlStrength;
            float _SwirlInflow;
            float _CurrentCount;
            float _CurrentWidth;
            float _CurrentAnimSpeed;

            float Potential(float2 p, float t)
            {
                float d = t * _FlowDrift;
                float s = SurfFbm(p * _FlowScale + float2(0.0, d)) - 0.5;
                s += (SurfFbm(p * _FlowScale * 2.3 + float2(d * 0.7, 11.3)) - 0.5) * 0.22;
                s += (SurfFbm(p * _FlowScale * 5.1 + float2(-d * 0.4, 27.7)) - 0.5) * 0.055;

                s += (SurfFbm(p * _FlowScale * 11.7 + float2(d * 1.3, 53.1)) - 0.5) * 0.024;
                return s;
            }

            float4 frag(v2f i) : SV_Target
            {
                float2 uv = i.uv;
                float t = _SurfTime;

                float e = 0.02;
                float dx = Potential(uv + float2(e, 0), t) - Potential(uv - float2(e, 0), t);
                float dy = Potential(uv + float2(0, e), t) - Potential(uv - float2(0, e), t);
                float2 flow = float2(dy, -dx) * (0.5 / e) * _FlowSpeed;

                flow += _FlowBias.xy * _FlowSpeed;

                [loop]
                for (int k = 0; k < _DisturbCount; k++)
                {
                    if (_DisturbDir[k].z < 0.5 || _Disturb[k].z <= 0.0)
                        continue;
                    float2 dv = uv - _Disturb[k].xy;
                    float r = length(dv);
                    float R = max(_SwirlRadius, 1e-4);
                    if (r > R * 3.0) continue;
                    float2 tang = float2(-dv.y, dv.x) / max(r, 1e-4);

                    float fall = exp(-(r * r) / (R * R));
                    flow += tang * fall * _SwirlStrength * _Disturb[k].z;

                    flow -= (dv / max(r, 1e-4)) * fall * _SwirlInflow * _Disturb[k].z;
                }

                return float4(flow, 0.0, 1);
            }
            ENDCG
        }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            sampler2D _MainTex;
            float4 _DyeSource[12];
            int _DyeSourceCount;
            float _DyeDecay;
            float _DyeAdvect;
            float _DyeDiffuse;
            float _WebFeed;
            float _WebCell;
            float _WebThick;
            float _WebDrift;

            float4 frag(v2f i) : SV_Target
            {
                float2 uv = i.uv;
                float2 tx = _TexelSize.xy;
                float2 flow = tex2D(_BioFlowTex, uv).rg;

                float2 src = uv - flow * _Dt * _DyeAdvect;
                float d = tex2D(_MainTex, src).r;

                float b = (tex2D(_MainTex, src + float2(tx.x, 0)).r
                         + tex2D(_MainTex, src - float2(tx.x, 0)).r
                         + tex2D(_MainTex, src + float2(0, tx.y)).r
                         + tex2D(_MainTex, src - float2(0, tx.y)).r) * 0.25;

                d = lerp(d, b, saturate(1.0 - exp(-_DyeDiffuse * _Dt)));

                d *= exp(-_DyeDecay * _Dt);

                [loop]
                for (int k = 0; k < _DyeSourceCount; k++)
                {
                    float4 S = _DyeSource[k];

                    float2 fl = tex2D(_BioFlowTex, S.xy).rg;
                    float fm = length(fl);
                    float2 ax = fm > 1e-5 ? fl / fm : float2(1, 0);
                    float2 dv = uv - S.xy;
                    float2 q = float2(dot(dv, ax) / 3.5, dot(dv, float2(-ax.y, ax.x))) / max(S.z, 1e-5);
                    d += exp(-dot(q, q) * 2.0) * S.w * 0.55 * _Dt;
                }

                {
                    float t = _SurfTime * _WebDrift;
                    float2 pm = uv * _BioFloorSize.xy / max(_WebCell, 1e-3);
                    float2 warp = float2(SurfFbm(pm * 0.33 + float2(t, 3.1)),
                                         SurfFbm(pm * 0.33 + float2(-t * 0.8, 17.7))) - 0.5;
                    float2 pw = pm + warp * 0.9;
                    float web = SurfFoamWalls(pw, _WebThick);

                    web = max(web, SurfFoamWalls(pw * 2.15 + 23.7, _WebThick * 0.75) * 0.28);

                    web *= 0.30 + 0.70 * SurfFbm(pw * 1.9 + float2(t * 2.0, 41.3));
                    d += web * _WebFeed * _Dt;
                }

                d *= exp(-_Dt * 1.6 * saturate(d - 0.72));

                return float4(saturate(d), 0, 0, 1);
            }
            ENDCG
        }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            sampler2D _MainTex;
            float _FastHalfLife;
            float _MemoryHalfLife;
            float _Diffusion;
            float _AdvectStrength;
            float _FootstepGlow;
            float _CrestGlow;
            float _CrestGain;
            float _CrestThresholdSim;
            float _SlopeResponse;
            float _CurvatureResponse;
            float _VelocityResponse;
            float _ExcitationThreshold;
            float _ExcitationGain;
            float _EdgePlanktonBoost;
            float _MemoryDensity;
            float _AmbientPlankton;
            float _WaveBioActivation;
            float _WaveMemoryActivation;
            float _WaveAdvection;
            float _BioBreakupScale;
            float _BreakupLow;
            float _BreakupHigh;
            float _BreakupMin;
            float _CurrentFeed;

            float4 frag(v2f i) : SV_Target
            {
                float2 uv = i.uv;
                float2 tx = _TexelSize.xy;
                float4 flow = tex2D(_BioFlowTex, uv);

                float2 hgA = float2(
                    tex2D(_BioHeightTex, uv + float2(tx.x, 0)).r - tex2D(_BioHeightTex, uv - float2(tx.x, 0)).r,
                    tex2D(_BioHeightTex, uv + float2(0, tx.y)).r - tex2D(_BioHeightTex, uv - float2(0, tx.y)).r);
                float2 waveMotion = -hgA * _WaveAdvection;
                float2 totalFlow = flow.xy * _AdvectStrength + waveMotion;

                float2 src = uv - totalFlow * _Dt;
                float2 e = tex2D(_MainTex, src).rg;

                float2 b = (tex2D(_MainTex, src + float2(tx.x, 0)).rg
                          + tex2D(_MainTex, src - float2(tx.x, 0)).rg
                          + tex2D(_MainTex, src + float2(0, tx.y)).rg
                          + tex2D(_MainTex, src - float2(0, tx.y)).rg) * 0.25;

                e = lerp(e, b, saturate(1.0 - exp(-_Diffusion * _Dt)));

                e.r *= exp(-0.6931 * _Dt / max(_FastHalfLife, 1e-3));
                e.g *= exp(-0.6931 * _Dt / max(_MemoryHalfLife, 1e-3));

                float2 hg = float2(
                    tex2D(_BioHeightTex, uv + float2(tx.x, 0)).r - tex2D(_BioHeightTex, uv - float2(tx.x, 0)).r,
                    tex2D(_BioHeightTex, uv + float2(0, tx.y)).r - tex2D(_BioHeightTex, uv - float2(0, tx.y)).r);

                float slope = length(hg) / max(tx.x, 1e-5);
                float hC = tex2D(_BioHeightTex, uv).r;
                float curv = abs(
                      tex2D(_BioHeightTex, uv + float2(tx.x, 0)).r
                    + tex2D(_BioHeightTex, uv - float2(tx.x, 0)).r
                    + tex2D(_BioHeightTex, uv + float2(0, tx.y)).r
                    + tex2D(_BioHeightTex, uv - float2(0, tx.y)).r
                    - 4.0 * hC) / max(tx.x, 1e-5);
                float vvel = abs(tex2D(_BioHeightTex, uv).g);

                float excitation = slope * _SlopeResponse
                                 + curv * _CurvatureResponse
                                 + vvel * _VelocityResponse;
                excitation = saturate((excitation - _ExcitationThreshold) * _ExcitationGain);

                float curDye = tex2D(_CurrentDyeTex, uv).r;

                float2 cg = float2(
                    tex2D(_CurrentDyeTex, uv + float2(tx.x, 0)).r - tex2D(_CurrentDyeTex, uv - float2(tx.x, 0)).r,
                    tex2D(_CurrentDyeTex, uv + float2(0, tx.y)).r - tex2D(_CurrentDyeTex, uv - float2(0, tx.y)).r);
                float curEdge = saturate(length(cg) / max(tx.x, 1e-5) * 0.004);

                float plankton = curDye
                               + curEdge * _EdgePlanktonBoost
                               + e.g * _MemoryDensity
                               + _AmbientPlankton;

                float breakup = smoothstep(_BreakupLow, _BreakupHigh,
                    SurfFbm(uv * _BioBreakupScale + flow.xy * 4.0 + _SurfTime * 0.06));
                float excited = excitation * plankton * lerp(_BreakupMin, 1.0, breakup);

                e.r += excited * _WaveBioActivation * _Dt;
                e.g += excited * _WaveMemoryActivation * _Dt;

                e.r += curDye * _CurrentFeed * _Dt;

                float dyeM = (tex2D(_CurrentDyeTex, uv + float2( tx.x,  tx.y) * 6.0).r
                            + tex2D(_CurrentDyeTex, uv + float2(-tx.x,  tx.y) * 6.0).r
                            + tex2D(_CurrentDyeTex, uv + float2( tx.x, -tx.y) * 6.0).r
                            + tex2D(_CurrentDyeTex, uv + float2(-tx.x, -tx.y) * 6.0).r) * 0.25;
                float ridge = saturate((curDye - dyeM) * 5.0);
                e.r += ridge * 0.9 * _Dt;

                [loop]
                for (int k = 0; k < _DisturbCount; k++)
                {
                    if (_Disturb[k].z <= 0.0)
                        continue;
                    float fp = DisturbFootprint(uv, k);
                    if (fp < 0.002)
                        continue;

                    if (_DisturbDir[k].z > 0.5)
                    {
                        float rr = length(uv - _Disturb[k].xy) / max(_Disturb[k].w, 1e-5);
                        float rim = exp(-pow((rr - 0.85) * 2.4, 2.0));
                        float core = 0.5 * exp(-rr * rr * 3.0);
                        e.r += (rim + core) * _Disturb[k].z * _FootstepGlow * 0.03 * _Dt;
                    }
                    else
                        e.r += fp * _Disturb[k].z * _FootstepGlow * 0.09;
                }

                e.g = max(e.g, e.r * 0.28);

                return float4(saturate(e.r), saturate(e.g), 0, 1);
            }
            ENDCG
        }
    }
}

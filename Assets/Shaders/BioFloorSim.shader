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

                [loop]
                for (int k = 0; k < _DisturbCount; k++)
                {
                    if (_Disturb[k].z <= 0.0)
                        continue;
                    float fp = DisturbFootprint(uv, k);
                    if (fp < 0.002)
                        continue;

                    float scale = 1.0;
                    if (_DisturbDir[k].z > 0.5)
                        scale = _SustainedPush * (0.55 + 0.45 * sin(_SurfTime * _SustainedRate + _Disturb[k].x * 40.0));
                    v -= fp * _Disturb[k].z * _ImpulseStrength * scale * dt;
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
    }
}

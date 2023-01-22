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
    }
}

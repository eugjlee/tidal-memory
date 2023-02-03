Shader "BioFloor/Particles"
{
    Properties
    {
        _ParticleBrightness ("Particle Brightness", Range(0, 8)) = 1.6
        _ParticleSizeMin ("Particle Size Min", Range(0.0005, 0.05)) = 0.0035
        _ParticleSizeMax ("Particle Size Max", Range(0.0005, 0.12)) = 0.016
        _Stretch ("Flow Stretch", Range(0, 12)) = 2.5
        _SurfaceBand ("Surface Band", Range(0, 0.2)) = 0.012
        _SprayHeight ("Spray Height", Range(0, 1)) = 0.16
        _Attack ("Flash Attack", Range(0.002, 0.2)) = 0.03
    }
    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }

        Pass
        {
            Blend One One
            ZWrite Off
            Cull Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.5
            #include "UnityCG.cginc"
            #include "BioCommon.cginc"

            sampler2D _PosTex;
            float _ParticleBrightness;
            float _ParticleSizeMin;
            float _ParticleSizeMax;
            float _Stretch;
            float _SurfaceBand;
            float _SprayHeight;
            float _Attack;
            float _LifeMin;
            float _LifeMax;
            float _AirborneSprayFraction;

            float4 _BaseEmissionColor;
            float4 _HighlightColor;
            float _BloomContribution;
            float _SurfaceAttachStrength;
            float _BioEnabled;
            int _DebugView;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 corner : TEXCOORD0;
                float2 seed : TEXCOORD1;
                float2 lookup : TEXCOORD2;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 corner : TEXCOORD0;
                float3 color : TEXCOORD1;
            };

            v2f vert(appdata v)
            {
                v2f o;
                float4 state = tex2Dlod(_PosTex, float4(v.lookup, 0, 0));
                float2 p = state.xy;
                float life = state.z;
                float seed = state.w;

                bool hidden = _DebugView >= 1
                            || life <= 0.0 || _BioEnabled < 0.5;

                float lifeTotal = max(lerp(_LifeMin, _LifeMax, seed), 1e-3);
                float age = lifeTotal - life;
                float f = saturate(age / lifeTotal);

                float env = saturate(age / _Attack)
                          * exp(-age / (lifeTotal * 0.45))
                          * saturate((lifeTotal - age) / (lifeTotal * 0.3));

                float2 flow = tex2Dlod(_BioFlowTex, float4(p, 0, 0)).rg;
                float hist = tex2Dlod(_BioEnergyTex, float4(p, 0, 0)).r;

                float s1 = v.seed.x;
                float s2 = v.seed.y;

                float b = _ParticleBrightness * env
                        * (0.30 + 0.70 * s1)
                        * (0.28 + 0.90 * saturate(hist));

                float sz = lerp(_ParticleSizeMin, _ParticleSizeMax, seed * seed * seed);

                float2 world2 = (p - 0.5) * _BioFloorSize.xy;
                float baseY = mul(unity_ObjectToWorld, float4(0, 0, 0, 1)).y;
                float eta = 0.0;

                float y = baseY + (s2 - 0.5) * _SurfaceBand;

                float air = step(seed, _AirborneSprayFraction);
                y += air * 4.0 * f * (1.0 - f) * _SprayHeight;

                float mlen = length(flow);
                float2 dir = mlen > 1e-5 ? flow / mlen : float2(1, 0);
                float2 perp = float2(-dir.y, dir.x);
                float len = 1.0 + _Stretch * saturate(mlen * 3.0) * (0.3 + 0.7 * s2);

                float2 offs = dir * v.corner.x * sz * len + perp * v.corner.y * sz;
                float3 world = float3(world2.x + offs.x, y, world2.y + offs.y);

                if (hidden)
                {
                    world = float3(world2.x, y, world2.y);
                    b = 0.0;
                }

                o.pos = mul(UNITY_MATRIX_VP, float4(world, 1.0));
                o.corner = v.corner * 2.0;
                o.color = lerp(_BaseEmissionColor.rgb, _HighlightColor.rgb, saturate(b * 0.55))
                        * b * _BloomContribution;
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                float d = saturate(1.0 - length(i.corner));
                float m = d * d * d;
                m += pow(d, 9.0) * 0.6;
                return float4(i.color * m, 1.0);
            }
            ENDCG
        }
    }
}

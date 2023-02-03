Shader "Hidden/BioFloor/ParticlesAdvect"
{
    Properties
    {
        _MainTex ("Particle State", 2D) = "black" {}
    }
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            #include "BioCommon.cginc"

            sampler2D _MainTex;
            float _Dt;
            float _Advect;
            float _ParticleDensity;
            float _LifeMin;
            float _LifeMax;
            float _ClusterScale;
            float _ClusterGrid;

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
                float4 s = tex2D(_MainTex, i.uv);
                float2 pos = s.xy;
                float life = s.z;
                float seed = s.w;
                float2 id = i.uv;
                float t = _SurfTime;

                if (life > 0.0)
                {
                    float2 flow = tex2Dlod(_BioFlowTex, float4(pos, 0, 0)).rg;
                    pos += flow * _Dt * _Advect;
                    life -= _Dt;

                    if (pos.x < 0.002 || pos.x > 0.998 || pos.y < 0.002 || pos.y > 0.998)
                        life = 0.0;

                    return float4(saturate(pos), life, seed);
                }

                float bucket = fmod(floor(t * 7.0), 8192.0);
                float2 bs = SurfHash22(float2(bucket, 17.0)) * 64.0;

                float2 raw = float2(SurfHash21(id * 91.7 + bs.x * 3.13),
                                    SurfHash21(id * 47.3 + bs.y * 7.71));

                float grid = max(_ClusterGrid, 1.0);
                float2 cell = floor(raw * grid);
                float2 centre = (cell + 0.5) / grid;
                centre += (SurfHash22(cell + bs.x * 0.37) - 0.5) / grid;

                float2 j = float2(SurfHash21(id * 13.1 + bs.x * 1.7)
                                + SurfHash21(id * 29.3 + bs.y * 5.1) - 1.0,
                                  SurfHash21(id * 61.7 + bs.y * 2.3)
                                + SurfHash21(id * 83.9 + bs.x * 9.7) - 1.0);
                float2 cand = centre + j * _ClusterScale;

                if (cand.x < 0.002 || cand.x > 0.998 || cand.y < 0.002 || cand.y > 0.998)
                    return float4(pos, 0.0, seed);

                float accept = SurfSpawnDensity(cand) * _ParticleDensity;
                float roll = SurfHash21(id * 7.77 + bs.y * 11.31);

                if (roll < accept)
                {
                    float ns = SurfHash21(id * 3.71 + bs.x * 17.3);
                    return float4(cand, lerp(_LifeMin, _LifeMax, ns), ns);
                }

                return float4(pos, 0.0, seed);
            }
            ENDCG
        }
    }
}

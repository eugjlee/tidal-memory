using UnityEngine;
using UnityEngine.Rendering;

namespace BioFloor
{

    [RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
    public class BioParticles : MonoBehaviour
    {
        [Header("Population")]
        [SerializeField] int count = 320000;
        [SerializeField] int seed = 1234;
        [SerializeField, Tooltip("Field UV drift applied from the water velocity")]
        float advectSpeed = 1f;

        [Header("Particles")]
        [SerializeField, Range(0f, 4f), Tooltip("Spawn acceptance scale")]
        float particleDensity = 0.5f;
        [SerializeField, Range(0f, 8f)] float particleBrightness = 1.6f;
        [SerializeField] float particleLifetimeMin = 0.12f;
        [SerializeField] float particleLifetimeMax = 0.55f;
        [SerializeField] float particleSizeMin = 0.0035f;
        [SerializeField] float particleSizeMax = 0.016f;
        [SerializeField, Range(0f, 0.2f)] float airborneSprayFraction = 0.02f;
        [SerializeField, Tooltip("Radius of a spawn clump in field UV")]
        float clusterScale = 0.035f;
        [SerializeField, Tooltip("Number of clump sites across the field")]
        float clusterGrid = 26f;

        [Header("Look")]
        [SerializeField] float stretch = 2.5f;
        [SerializeField] float surfaceBand = 0.012f;
        [SerializeField] float sprayHeight = 0.16f;
        [SerializeField] float flashAttack = 0.03f;

        RenderTexture _stateA;
        RenderTexture _stateB;
        Texture2D _init;
        Material _updateMat;
        MaterialPropertyBlock _mpb;
        MeshRenderer _renderer;
        int _texW;
        int _texH;

        static readonly int PosTexId = Shader.PropertyToID("_PosTex");

        void OnEnable()
        {
            _texW = 1024;
            _texH = Mathf.Max(1, Mathf.CeilToInt(count / (float)_texW));

            var mf = GetComponent<MeshFilter>();
            if (mf.sharedMesh == null || mf.sharedMesh.vertexCount != count * 4)
                mf.sharedMesh = BuildMesh();

            BuildInitTexture();

            _stateA = MakeStateRt();
            _stateB = MakeStateRt();
            Graphics.Blit(_init, _stateA);
            Graphics.Blit(_init, _stateB);

            _updateMat = new Material(Shader.Find("Hidden/BioFloor/ParticlesAdvect"));
            _mpb = new MaterialPropertyBlock();
            _renderer = GetComponent<MeshRenderer>();
        }

        void OnDisable()
        {
            if (_stateA != null) _stateA.Release();
            if (_stateB != null) _stateB.Release();
            if (_updateMat != null) DestroyImmediate(_updateMat);
            if (_init != null) DestroyImmediate(_init);
        }

        void Update()
        {
            float dt = Mathf.Clamp(Time.deltaTime, 1e-4f, 0.1f);

            _updateMat.SetFloat("_Dt", dt);
            _updateMat.SetFloat("_Advect", advectSpeed);
            _updateMat.SetFloat("_ParticleDensity", particleDensity);
            _updateMat.SetFloat("_LifeMin", particleLifetimeMin);
            _updateMat.SetFloat("_LifeMax", particleLifetimeMax);
            _updateMat.SetFloat("_ClusterScale", clusterScale);
            _updateMat.SetFloat("_ClusterGrid", clusterGrid);

            Graphics.Blit(_stateA, _stateB, _updateMat);
            (_stateA, _stateB) = (_stateB, _stateA);

            _mpb.SetTexture(PosTexId, _stateA);
            _mpb.SetFloat("_ParticleBrightness", particleBrightness);
            _mpb.SetFloat("_ParticleSizeMin", particleSizeMin);
            _mpb.SetFloat("_ParticleSizeMax", particleSizeMax);
            _mpb.SetFloat("_LifeMin", particleLifetimeMin);
            _mpb.SetFloat("_LifeMax", particleLifetimeMax);
            _mpb.SetFloat("_AirborneSprayFraction", airborneSprayFraction);
            _mpb.SetFloat("_Stretch", stretch);
            _mpb.SetFloat("_SurfaceBand", surfaceBand);
            _mpb.SetFloat("_SprayHeight", sprayHeight);
            _mpb.SetFloat("_Attack", flashAttack);
            _renderer.SetPropertyBlock(_mpb);
        }

        RenderTexture MakeStateRt()
        {
            var rt = new RenderTexture(_texW, _texH, 0, RenderTextureFormat.ARGBFloat)
            {
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Point
            };
            rt.Create();
            return rt;
        }

        void BuildInitTexture()
        {
            var rng = new System.Random(seed);
            _init = new Texture2D(_texW, _texH, TextureFormat.RGBAFloat, false, true)
            {
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Point
            };
            var pixels = new Color[_texW * _texH];
            for (int i = 0; i < pixels.Length; i++)
            {
                pixels[i] = new Color(
                    (float)rng.NextDouble(),
                    (float)rng.NextDouble(),
                    0f,
                    (float)rng.NextDouble());
            }
            _init.SetPixels(pixels);
            _init.Apply(false, false);
        }

        Mesh BuildMesh()
        {
            var rng = new System.Random(seed + 1);
            var verts = new Vector3[count * 4];
            var corners = new Vector2[count * 4];
            var seeds = new Vector2[count * 4];
            var lookups = new Vector2[count * 4];
            var indices = new int[count * 6];

            var cornerLut = new[]
            {
                new Vector2(-0.5f, -0.5f), new Vector2(0.5f, -0.5f),
                new Vector2(0.5f, 0.5f), new Vector2(-0.5f, 0.5f)
            };

            for (int i = 0; i < count; i++)
            {
                var s = new Vector2((float)rng.NextDouble(), (float)rng.NextDouble());
                var lookup = new Vector2(
                    ((i % _texW) + 0.5f) / _texW,
                    ((i / _texW) + 0.5f) / _texH);

                int v = i * 4;
                for (int c = 0; c < 4; c++)
                {
                    verts[v + c] = Vector3.zero;
                    corners[v + c] = cornerLut[c];
                    seeds[v + c] = s;
                    lookups[v + c] = lookup;
                }

                int t = i * 6;
                indices[t] = v; indices[t + 1] = v + 2; indices[t + 2] = v + 1;
                indices[t + 3] = v; indices[t + 4] = v + 3; indices[t + 5] = v + 2;
            }

            var mesh = new Mesh
            {
                name = "PlanktonParticles",
                indexFormat = IndexFormat.UInt32
            };
            mesh.SetVertices(verts);
            mesh.SetUVs(0, corners);
            mesh.SetUVs(1, seeds);
            mesh.SetUVs(2, lookups);
            mesh.SetIndices(indices, MeshTopology.Triangles, 0);
            mesh.bounds = new Bounds(Vector3.zero, new Vector3(20f, 6f, 20f));
            mesh.UploadMeshData(true);
            return mesh;
        }
    }
}

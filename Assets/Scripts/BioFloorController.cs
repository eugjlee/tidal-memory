using System.Collections.Generic;
using UnityEngine;

namespace BioFloor
{

    [ExecuteAlways]
    [RequireComponent(typeof(FloorCoordinateMapper))]
    public class BioFloorController : MonoBehaviour
    {
        [Header("Simulation")]
        [SerializeField, Tooltip("Simulation texture size. The fluid does not need projector resolution; 1024 is plenty for waves metres across")]
        int simResolution = 512;
        [SerializeField, Range(30f, 120f), Tooltip("Fixed solver rate. The stencil's stability is tied to the step, so this must not follow the frame rate")]
        float simRate = 120f;
        [SerializeField, Range(1, 8), Tooltip("Ceiling on catch-up steps after a hitch, so a stall cannot cascade into a spiral")]
        int maxSubSteps = 8;

        [Header("Water")]
        [SerializeField, Range(0.05f, 0.70f), Tooltip("Courant number, not a speed. The explicit stencil is stable only below about 0.707, so this is expressed as the ratio that governs stability; the resulting speed in metres per second is reported below and follows from floor size, resolution and step rate")]
        float courant = 0.60f;
        [SerializeField, Range(0.2f, 12f), Tooltip("Seconds for a ripple to die away")]
        float waterDamping = 2.6f;
        [SerializeField, Range(0f, 40f)] float rippleStrength = 9f;

        [Header("Bioluminescence")]
        [SerializeField, Range(0f, 12f)] float footstepGlow = 4.5f;
        [SerializeField, Range(0.1f, 4f), Tooltip("Half life of the bright immediate reaction")]
        float bioDecay = 1.0f;
        [SerializeField, Range(1f, 30f), Tooltip("Half life of the soft residual path")]
        float memoryDecay = 8f;
        [SerializeField, Range(0f, 8f), Tooltip("Diffusion rate per second, not per frame. Keep low: fast activation is the sparkle, and blurring it is what turns every footfall into a soft pad")]
        float diffusion = 0.35f;
        [SerializeField, Range(0f, 4f)] float advectStrength = 1.0f;
        [SerializeField, Range(0f, 8f), Tooltip("How hard a moving wave crest lights the water it passes through")]
        float crestGlow = 2.2f;
        [SerializeField, Range(0f, 4f), Tooltip("Scales wave slope into a 0..1 crest response before the glow is applied")]
        float crestGain = 0.5f;
        [SerializeField, Range(0f, 2f), Tooltip("Trickle of light into the corridors, so the floor lives before anyone walks on it")]
        float currentFeed = 0.35f;

        [Header("Water / Bio Coupling")]
        [Tooltip("How hard the tilt of the surface excites plankton")]
        [SerializeField, Range(0f, 0.2f)] float slopeResponse = 0.02f;
        [Tooltip("Curvature response. Catches the moment a crest passes through its own peak, where the surface is momentarily flat but moving hardest")]
        [SerializeField, Range(0f, 0.05f)] float curvatureResponse = 0.004f;
        [SerializeField, Range(0f, 4f)] float velocityResponse = 0.9f;
        [SerializeField, Range(0f, 2f)] float excitationThreshold = 0.22f;
        [SerializeField, Range(0f, 8f)] float excitationGain = 2.2f;
        [Tooltip("How strongly a wave lights the plankton it passes through. This is the coupling that stops water and glow reading as two layers")]
        [SerializeField, Range(0f, 20f)] float waveBioActivation = 7f;
        [SerializeField, Range(0f, 4f), Tooltip("Afterglow left behind the wave. Brief suggests 5-20 percent of the fast activation")]
        float waveMemoryActivation = 0.8f;
        [SerializeField, Range(0f, 6f), Tooltip("How much more the edges of a current react than its body")]
        float edgePlanktonBoost = 2.2f;
        [SerializeField, Range(0f, 2f)] float memoryDensity = 0.4f;
        [SerializeField, Range(0f, 0.3f), Tooltip("Plankton in otherwise empty water. At 0 a wave in open water is completely dark")]
        float ambientPlankton = 0.03f;
        [SerializeField, Range(0f, 2f), Tooltip("How much the wave's own surface motion carries the glow, on top of the slow current")]
        float waveAdvection = 0.35f;
        [SerializeField, Range(10f, 500f)] float bioBreakupScale = 150f;
        [SerializeField, Range(0f, 1f)] float breakupLow = 0.30f;
        [SerializeField, Range(0f, 1f)] float breakupHigh = 0.72f;
        [SerializeField, Range(0f, 1f), Tooltip("Never zero: some faint continuity should survive between the bright fragments")]
        float breakupMin = 0.12f;

        [Header("Flow")]
        [SerializeField, Range(0f, 0.6f)] float flowSpeed = 0.09f;
        [SerializeField, Range(0.5f, 8f), Tooltip("Meander scale. Low values give a few broad rivers across the whole floor")]
        float flowScale = 2.2f;
        [SerializeField, Range(0f, 0.3f), Tooltip("How fast the current itself reshapes. At 0 the rivers are fixed and the floor becomes a painting")]
        float flowDrift = 0.02f;
        [SerializeField, Range(0f, 90f), Tooltip("Direction of the prevailing drift, degrees")]
        float flowBiasAngle = 20f;
        [SerializeField, Range(0f, 3f), Tooltip("Strength of the prevailing drift, relative to the curl. A little turns eddies into currents that cross the room; too much flattens them into a conveyor belt")]
        float flowBias = 0.9f;

        [Header("Currents")]
        [SerializeField, Range(2, 12), Tooltip("Soft source patches feeding the current. The flow stretches these into ribbons; drawing the ribbons directly is what produced contour lines")]
        int currentSources = 9;
        [SerializeField, Range(0.05f, 1.2f), Tooltip("Source patch radius in metres. Brief: 0.15 to 0.60")]
        float currentSourceRadius = 0.38f;
        [SerializeField, Range(0f, 4f)] float currentSourceStrength = 0.9f;

        [Header("Web")]
        [SerializeField, Range(0f, 0.3f), Tooltip("How fast the connected network feeds the current density. The web is a continuous lattice of filaments across the whole floor, so nothing starts or ends anywhere")]
        float webFeed = 0.04f;
        [SerializeField, Range(0.8f, 6f), Tooltip("Cell size of the network in metres")]
        float webCellMetres = 2.6f;
        [SerializeField, Range(0.03f, 0.5f), Tooltip("Filament thickness, as a fraction of a cell")]
        float webThickness = 0.13f;
        [SerializeField, Range(0f, 0.1f), Tooltip("How fast the lattice itself deforms and reconnects")]
        float webDrift = 0.012f;

        [Header("People")]
        [SerializeField, Range(0.01f, 0.5f), Tooltip("Radius of the swirl a standing person makes, in field widths")]
        float swirlRadius = 0.085f;
        [SerializeField, Range(0f, 3f), Tooltip("How hard the water turns around someone. This is what winds the current into a spiral")]
        float swirlStrength = 0.55f;
        [SerializeField, Range(0f, 2f), Tooltip("How strongly the current is drawn inward, so the ribbon spirals in rather than orbiting at a fixed radius")]
        float swirlInflow = 0.22f;
        [SerializeField, Range(0f, 1f), Tooltip("How hard a standing person keeps disturbing the surface. This is what sustains the train of rings")]
        float sustainedPush = 0.16f;
        [SerializeField, Range(0f, 40f), Tooltip("How fast that disturbance pulses, which sets the ring spacing")]
        float sustainedRate = 9f;
        [SerializeField, Range(0.01f, 2f), Tooltip("How fast current density fades. Long lives let ribbons grow across the whole floor")]
        float currentDecay = 0.10f;
        [SerializeField, Range(0f, 8f)] float currentDyeAdvect = 1.0f;
        [SerializeField, Range(0f, 8f), Tooltip("Diffusion rate per second for the current density")]
        float currentDyeDiffuse = 0.5f;
        [SerializeField, Range(0f, 30f), Tooltip("Seconds of simulation run at startup, so the floor opens with mature currents instead of an empty room")]
        float prewarmSeconds = 10f;
        [SerializeField, Range(0f, 0.1f), Tooltip("How fast the sources wander")]
        float sourceDrift = 0.012f;

        [Header("Particles")]
        [SerializeField, Range(0f, 20f)] float spawnFilamentGain = 6f;
        [SerializeField, Range(0f, 8f)] float spawnEnergyGain = 2.2f;
        [SerializeField, Range(0f, 8f)] float spawnCrestGain = 3f;
        [SerializeField, Range(0f, 8f), Tooltip("How densely the current corridors are filled with particles. In the reference the currents are made of particles rather than lit by them")]
        float spawnCurrentGain = 2.6f;

        [Header("Scatter")]
        [SerializeField, Range(1, 6)] int scatterIterations = 4;
        [SerializeField, Range(0.5f, 6f)] float scatterRadius = 1.5f;

        [Header("Appearance")]
        [Tooltip("The floor at rest. A projector cannot emit black, so this is really the darkest the room will get")]
        [SerializeField] Color deepColor = new Color(0.020f, 0.008f, 0.045f, 1f);
        [SerializeField] Color waterColor = new Color(0.055f, 0.030f, 0.160f, 1f);

        [SerializeField, ColorUsage(false, true)] Color dimColor = new Color(0.035f, 0.020f, 0.200f);
        [SerializeField, ColorUsage(false, true)] Color hotColor = new Color(0.850f, 0.600f, 0.800f);

        [Header("Pigment")]
        [Tooltip("The species living in this water. Each patch of the floor keeps its own pigment as the current carries it, so the room is a mixture rather than one hue graded by brightness")]
        [SerializeField, ColorUsage(false, true)] Color pigmentBlue = new Color(0.030f, 0.100f, 1.000f);
        [SerializeField, ColorUsage(false, true)] Color pigmentViolet = new Color(0.300f, 0.030f, 1.000f);
        [SerializeField, ColorUsage(false, true)] Color pigmentMagenta = new Color(1.000f, 0.020f, 0.550f);
        [SerializeField, ColorUsage(false, true)] Color pigmentCrimson = new Color(1.000f, 0.020f, 0.100f);
        [Tooltip("The rare warm species. It does not blend: these arrive as whole discrete blooms inside the cool field")]
        [SerializeField, ColorUsage(false, true)] Color pigmentGold = new Color(1.000f, 0.420f, 0.020f);
        [SerializeField, Range(0f, 1f), Tooltip("0 holds the whole floor to one hue, 1 opens the full spread")]
        float pigmentMix = 1f;
        [SerializeField, Range(0.5f, 12f), Tooltip("Size of a single-species patch, in metres")]
        float pigmentScaleMetres = 3.4f;
        [SerializeField, Range(0f, 0.6f), Tooltip("How much of the floor the warm species holds")]
        float goldAmount = 0.18f;
        [SerializeField, Range(0f, 3f)] float baseDetail = 1.1f;
        [SerializeField, Range(0f, 60f), Tooltip("How steeply the ripple field is shaded. This is what makes the fine surface texture visible at all")]
        float surfaceRelief = 14f;
        [SerializeField, Range(0f, 8f), Tooltip("Sheen off the ripple faces")]
        float surfaceSheen = 2.2f;

        [SerializeField, Range(1f, 12f), Tooltip("Macro swell, metres. Brief: 3 to 7")]
        float macroMetres = 5f;
        [SerializeField, Range(0f, 0.1f), Tooltip("Metres per second. Brief: 0.01 to 0.04")]
        float macroSpeedMs = 0.025f;
        [SerializeField, Range(0.1f, 3f), Tooltip("Medium wave texture, metres. Brief: 0.5 to 1.5")]
        float mediumMetres = 0.9f;
        [SerializeField, Range(0f, 0.2f), Tooltip("Metres per second. Brief: 0.03 to 0.10")]
        float mediumSpeedMs = 0.06f;
        [SerializeField, Range(0.01f, 0.5f), Tooltip("Micro ripples, metres. Brief: 0.04 to 0.20. This is the fine skin the whole floor is covered in")]
        float microMetres = 0.09f;
        [SerializeField, Range(0f, 0.6f), Tooltip("Metres per second. Brief: 0.10 to 0.35")]
        float microSpeedMs = 0.2f;
        [SerializeField, Range(0f, 6f)] float rippleGain = 1.6f;
        [SerializeField, Range(0f, 20f), Tooltip("How strongly the wave slope turns into light. The slope arrives in height per texel, so this is a gain, not a width")]
        float rippleWidth = 0.6f;
        [SerializeField, Range(0f, 200f), Tooltip("Slope a wave must exceed before it lights at all. Without it the whole circumference glows and the ripple reads as a sonar ring")]
        float crestThreshold = 22f;
        [SerializeField, Range(0.5f, 6f), Tooltip("Higher values leave only the strongest fragments of a crest visible. Brief wants 25 to 60 percent of a ring showing")]
        float crestPower = 2.2f;
        [SerializeField, Range(0f, 0.5f), Tooltip("Plankton present in otherwise empty water. At 0 a ripple crossing dark water is completely invisible")]
        float planktonFloor = 0.06f;
        [SerializeField, Range(0f, 0.02f), Tooltip("How much the water surface bends where the glow is sampled. Small: enough that filaments wobble as a wave passes, not enough to warp the image")]
        float bioSurfaceDistortion = 0.0035f;
        [SerializeField, Range(0f, 6f)] float edgeGain = 2.0f;
        [SerializeField, Range(0f, 4f), Tooltip("Only a very small share of pixels should ever reach the hot core")]
        float hotspotGain = 1.0f;
        [SerializeField, Range(0f, 3f)] float currentIntensity = 0.55f;
        [SerializeField, Range(0f, 2f)] float memoryGain = 0.45f;
        [SerializeField, Range(0f, 3f)] float scatterGain = 0.35f;
        [SerializeField, Range(0f, 3f)] float sparkleGain = 0.8f;
        [SerializeField, Range(0f, 4f)] float exposure = 1f;
        [SerializeField, Range(0f, 4f), Tooltip("Overall gain on the particle layer")]
        float bloomContribution = 1f;
        [SerializeField, ColorUsage(false, true), Tooltip("Core of a spark. The body colour comes from the pigment of the bloom it sits in; only the core goes pale")]
        Color particleHighlightColor = new Color(0.80f, 0.55f, 0.85f);

        [Header("Input")]
        [SerializeField] MonoBehaviour disturbanceSource;

        const int MaxDisturbance = 32;
        static readonly Vector4[] _dA = new Vector4[MaxDisturbance];
        static readonly Vector4[] _dB = new Vector4[MaxDisturbance];

        RenderTexture _heightA, _heightB, _flow, _energyA, _energyB, _glowA, _glowB, _dyeA, _dyeB;
        static readonly Vector4[] _srcArr = new Vector4[12];
        Material _mat;
        FloorCoordinateMapper _map;
        IBioDisturbanceSource _source;
        readonly List<BioDisturbance> _pending = new List<BioDisturbance>();
        float _accum;

        public float WaveSpeedMetresPerSecond
        {
            get
            {
                float metresPerTexel = Map.FloorWidth / Mathf.Max(simResolution, 1);
                float texelsPerSecond = courant * Mathf.Max(simRate, 1f);
                return texelsPerSecond * metresPerTexel;
            }
        }

        public FloorCoordinateMapper Map => _map != null ? _map : (_map = GetComponent<FloorCoordinateMapper>());

        public void AddDisturbance(BioDisturbance d)
        {
            if (_pending.Count < MaxDisturbance)
                _pending.Add(d);
        }

        public void AddFootstep(Vector3 world, Vector2 direction, float pressure = 1f)
        {
            Vector2 uv = Map.WorldToUv(world);
            if (!FloorCoordinateMapper.InBounds(uv))
                return;
            AddDisturbance(new BioDisturbance
            {
                Uv = uv, Direction = direction, Strength = pressure,
                Radius = 0.15f, Sustained = false
            });
        }

        void OnEnable()
        {
            _map = GetComponent<FloorCoordinateMapper>();
            _heightA = Rt(RenderTextureFormat.RGHalf);
            _heightB = Rt(RenderTextureFormat.RGHalf);
            _flow = Rt(RenderTextureFormat.ARGBHalf);
            _energyA = Rt(RenderTextureFormat.RGHalf);
            _energyB = Rt(RenderTextureFormat.RGHalf);
            _glowA = Rt(RenderTextureFormat.RHalf, simResolution / 2);
            _glowB = Rt(RenderTextureFormat.RHalf, simResolution / 2);
            _dyeA = Rt(RenderTextureFormat.RHalf);
            _dyeB = Rt(RenderTextureFormat.RHalf);
            foreach (var rt in All()) Clear(rt);

            _mat = new Material(Shader.Find("Hidden/BioFloor/Sim"));
            _source = disturbanceSource as IBioDisturbanceSource;
            _accum = 0f;
            Push();
            Prewarm();
        }

        void OnDisable()
        {
            foreach (var rt in All()) if (rt != null) rt.Release();
            if (_mat != null) DestroyImmediate(_mat);
        }

        IEnumerable<RenderTexture> All()
        {
            yield return _heightA; yield return _heightB; yield return _flow;
            yield return _energyA; yield return _energyB; yield return _glowA; yield return _glowB;
            yield return _dyeA; yield return _dyeB;
        }

        public void ResetSimulation()
        {
            foreach (var rt in All()) Clear(rt);
        }

        public void ResetAndPrewarm()
        {
            ResetSimulation();
            Push();
            Prewarm();
        }

        void Update()
        {
            if (_mat == null) return;
            float dt = Mathf.Clamp(Time.deltaTime, 1e-4f, 0.1f);

            _pending.Clear();
            if (_source != null) _source.CollectDisturbances(AddDisturbance);

            Push();
            PushDisturbances();

            Graphics.Blit(null, _flow, _mat, 1);
            Shader.SetGlobalTexture("_BioFlowTex", _flow);

            StepDye(dt);

            float fixedDt = 1f / Mathf.Max(simRate, 1f);
            _mat.SetFloat("_FixedDt", fixedDt);
            _accum += dt;
            int steps = Mathf.Min(Mathf.FloorToInt(_accum / fixedDt), maxSubSteps);
            _accum -= steps * fixedDt;
            for (int i = 0; i < steps; i++)
            {
                Graphics.Blit(_heightA, _heightB, _mat, 0);
                (_heightA, _heightB) = (_heightB, _heightA);
            }
            Shader.SetGlobalTexture("_BioHeightTex", _heightA);

            _mat.SetFloat("_Dt", dt);
            Graphics.Blit(_energyA, _energyB, _mat, 3);
            (_energyA, _energyB) = (_energyB, _energyA);
            Shader.SetGlobalTexture("_BioEnergyTex", _energyA);

            Graphics.Blit(null, _glowA, _mat, 4);
            float texel = 1f / Mathf.Max(_glowA.width, 1);
            for (int k = 0; k < scatterIterations; k++)
            {
                float step = scatterRadius * texel * (1 << k);
                _mat.SetVector("_BlurStep", new Vector4(step, 0, 0, 0));
                Graphics.Blit(_glowA, _glowB, _mat, 5);
                _mat.SetVector("_BlurStep", new Vector4(0, step, 0, 0));
                Graphics.Blit(_glowB, _glowA, _mat, 5);
            }
            Shader.SetGlobalTexture("_BioGlowTex", _glowA);
        }

        void StepDye(float dt)
        {
            PushSources();
            _mat.SetFloat("_Dt", dt);
            _mat.SetFloat("_DyeDecay", currentDecay);
            _mat.SetFloat("_DyeAdvect", currentDyeAdvect);
            _mat.SetFloat("_DyeDiffuse", currentDyeDiffuse);
            Graphics.Blit(_dyeA, _dyeB, _mat, 2);
            (_dyeA, _dyeB) = (_dyeB, _dyeA);
            Shader.SetGlobalTexture("_CurrentDyeTex", _dyeA);
        }

        void PushSources()
        {
            int n = Mathf.Min(currentSources, 12);
            float t = Application.isPlaying ? Time.time : Now();
            for (int i = 0; i < n; i++)
            {

                float a = i * 2.3999632f;
                float bx = Mathf.PerlinNoise(i * 5.13f, t * sourceDrift) - 0.5f;
                float by = Mathf.PerlinNoise(i * 9.71f + 31f, t * sourceDrift) - 0.5f;

                float rad = Mathf.Sqrt((i + 0.5f) / n) * 0.46f;
                Vector2 uv = new Vector2(0.42f, 0.5f)
                    + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * rad
                    + new Vector2(bx, by) * 0.30f;

                uv.x = Mathf.Clamp(uv.x, 0.08f, 0.92f);
                uv.y = Mathf.Clamp(uv.y, 0.08f, 0.92f);
                float ruv = currentSourceRadius / Mathf.Max(Map.FloorWidth, 1e-3f);
                _srcArr[i] = new Vector4(uv.x, uv.y, ruv, currentSourceStrength);
            }
            for (int i = n; i < 12; i++) _srcArr[i] = Vector4.zero;
            _mat.SetVectorArray("_DyeSource", _srcArr);
            _mat.SetInt("_DyeSourceCount", n);
        }

        void Prewarm()
        {
            if (prewarmSeconds <= 0f) return;
            const float step = 1f / 30f;
            int steps = Mathf.Min(Mathf.CeilToInt(prewarmSeconds / step), 900);
            Graphics.Blit(null, _flow, _mat, 1);
            Shader.SetGlobalTexture("_BioFlowTex", _flow);
            for (int i = 0; i < steps; i++) StepDye(step);
        }

        void PushDisturbances()
        {
            Vector2 size = Map.FloorSize;
            int n = Mathf.Min(_pending.Count, MaxDisturbance);
            for (int i = 0; i < n; i++)
            {
                BioDisturbance d = _pending[i];

                float ruv = d.Radius / Mathf.Max(size.x, 1e-3f);
                _dA[i] = new Vector4(d.Uv.x, d.Uv.y, d.Strength, ruv);
                _dB[i] = new Vector4(d.Direction.x, d.Direction.y, d.Sustained ? 1f : 0f, 0f);
            }
            for (int i = n; i < MaxDisturbance; i++) { _dA[i] = Vector4.zero; _dB[i] = Vector4.zero; }
            _mat.SetVectorArray("_Disturb", _dA);
            _mat.SetVectorArray("_DisturbDir", _dB);
            _mat.SetInt("_DisturbCount", n);
        }

        void Push()
        {
            float t = Application.isPlaying ? Time.time : Now();
            Shader.SetGlobalFloat("_SurfTime", t);
            Shader.SetGlobalVector("_BioFloorSize", new Vector4(Map.FloorWidth, Map.FloorLength, 0, 0));
            Shader.SetGlobalVector("_BioTexel", new Vector4(1f / simResolution, 1f / simResolution, 0, 0));
            Shader.SetGlobalFloat("_SpawnFilamentGain", spawnFilamentGain);
            Shader.SetGlobalFloat("_SpawnEnergyGain", spawnEnergyGain);
            Shader.SetGlobalFloat("_SpawnCrestGain", spawnCrestGain);
            Shader.SetGlobalFloat("_SpawnCrestThreshold", crestThreshold);
            Shader.SetGlobalFloat("_SpawnCurrentGain", spawnCurrentGain);

            if (_mat == null) return;
            _mat.SetVector("_TexelSize", new Vector4(1f / simResolution, 1f / simResolution, simResolution, simResolution));
            _mat.SetFloat("_WaveSpeed", courant);
            _mat.SetFloat("_Damping", waterDamping);
            _mat.SetFloat("_ImpulseStrength", rippleStrength);
            _mat.SetFloat("_SustainedPush", sustainedPush);
            _mat.SetFloat("_SustainedRate", sustainedRate);
            _mat.SetFloat("_SwirlRadius", swirlRadius);
            _mat.SetFloat("_SwirlStrength", swirlStrength);
            _mat.SetFloat("_SwirlInflow", swirlInflow);
            _mat.SetFloat("_FastHalfLife", bioDecay);
            _mat.SetFloat("_MemoryHalfLife", memoryDecay);
            _mat.SetFloat("_Diffusion", diffusion);
            _mat.SetFloat("_AdvectStrength", advectStrength);
            _mat.SetFloat("_FootstepGlow", footstepGlow);
            _mat.SetFloat("_CrestGlow", crestGlow);
            _mat.SetFloat("_CrestGain", crestGain);
            _mat.SetFloat("_CrestThresholdSim", crestThreshold);
            _mat.SetFloat("_SlopeResponse", slopeResponse);
            _mat.SetFloat("_CurvatureResponse", curvatureResponse);
            _mat.SetFloat("_VelocityResponse", velocityResponse);
            _mat.SetFloat("_ExcitationThreshold", excitationThreshold);
            _mat.SetFloat("_ExcitationGain", excitationGain);
            _mat.SetFloat("_WaveBioActivation", waveBioActivation);
            _mat.SetFloat("_WaveMemoryActivation", waveMemoryActivation);
            _mat.SetFloat("_EdgePlanktonBoost", edgePlanktonBoost);
            _mat.SetFloat("_MemoryDensity", memoryDensity);
            _mat.SetFloat("_AmbientPlankton", ambientPlankton);
            _mat.SetFloat("_WaveAdvection", waveAdvection);
            _mat.SetFloat("_BioBreakupScale", bioBreakupScale);
            _mat.SetFloat("_BreakupLow", breakupLow);
            _mat.SetFloat("_BreakupHigh", breakupHigh);
            _mat.SetFloat("_BreakupMin", breakupMin);
            _mat.SetFloat("_CurrentFeed", currentFeed);
            _mat.SetFloat("_WebFeed", webFeed);
            _mat.SetFloat("_WebCell", webCellMetres);
            _mat.SetFloat("_WebThick", webThickness);
            _mat.SetFloat("_WebDrift", webDrift);
            _mat.SetFloat("_FlowScale", flowScale);
            _mat.SetFloat("_FlowSpeed", flowSpeed);
            _mat.SetFloat("_FlowDrift", flowDrift);
            float fb = flowBiasAngle * Mathf.Deg2Rad;
            _mat.SetVector("_FlowBias", new Vector4(Mathf.Cos(fb) * flowBias, Mathf.Sin(fb) * flowBias, 0, 0));

            Shader.SetGlobalColor("_DeepColor", deepColor.linear);
            Shader.SetGlobalColor("_WaterColor", waterColor.linear);
            Shader.SetGlobalColor("_DimColor", dimColor);
            Shader.SetGlobalColor("_PigmentBlue", pigmentBlue);
            Shader.SetGlobalColor("_PigmentViolet", pigmentViolet);
            Shader.SetGlobalColor("_PigmentMagenta", pigmentMagenta);
            Shader.SetGlobalColor("_PigmentCrimson", pigmentCrimson);
            Shader.SetGlobalColor("_PigmentGold", pigmentGold);
            Shader.SetGlobalFloat("_PigmentMix", pigmentMix);
            Shader.SetGlobalFloat("_PigmentScale", pigmentScaleMetres);
            Shader.SetGlobalFloat("_GoldAmount", goldAmount);

            Shader.SetGlobalFloat("_BioEnabled", 1f);
            Shader.SetGlobalFloat("_BloomContribution", bloomContribution);
            Shader.SetGlobalFloat("_SurfaceAttachStrength", 0f);
            Shader.SetGlobalInt("_BioDebug", 0);
            Shader.SetGlobalColor("_HighlightColor", particleHighlightColor);
            Shader.SetGlobalColor("_HotColor", hotColor);
            Shader.SetGlobalFloat("_BaseDetail", baseDetail);
            Shader.SetGlobalFloat("_SurfaceRelief", surfaceRelief);
            Shader.SetGlobalFloat("_SurfaceSheen", surfaceSheen);

            float w = Mathf.Max(Map.FloorWidth, 1e-3f);
            Shader.SetGlobalFloat("_MacroScale", w / Mathf.Max(macroMetres, 1e-3f));
            Shader.SetGlobalFloat("_MediumScale", w / Mathf.Max(mediumMetres, 1e-3f));
            Shader.SetGlobalFloat("_MicroScale", w / Mathf.Max(microMetres, 1e-3f));

            Shader.SetGlobalFloat("_MacroSpeed", macroSpeedMs / w);
            Shader.SetGlobalFloat("_MediumSpeed", mediumSpeedMs / w);
            Shader.SetGlobalFloat("_MicroSpeed", microSpeedMs / w);
            Shader.SetGlobalFloat("_RippleGain", rippleGain);
            Shader.SetGlobalFloat("_RippleWidth", rippleWidth);
            Shader.SetGlobalFloat("_CrestThreshold", crestThreshold);
            Shader.SetGlobalFloat("_CrestPower", crestPower);
            Shader.SetGlobalFloat("_PlanktonFloor", planktonFloor);
            Shader.SetGlobalFloat("_BioSurfaceDistortion", bioSurfaceDistortion);
            Shader.SetGlobalFloat("_EdgeGain", edgeGain);
            Shader.SetGlobalFloat("_HotspotGain", hotspotGain);
            Shader.SetGlobalFloat("_CurrentIntensity", currentIntensity);
            Shader.SetGlobalFloat("_MemoryGain", memoryGain);
            Shader.SetGlobalFloat("_ScatterGain", scatterGain);
            Shader.SetGlobalFloat("_SparkleGain", sparkleGain);
            Shader.SetGlobalFloat("_Exposure", exposure);
        }

        static float Now()
        {
#if UNITY_EDITOR
            return (float)UnityEditor.EditorApplication.timeSinceStartup;
#else
            return Time.time;
#endif
        }

        RenderTexture Rt(RenderTextureFormat fmt, int res = 0)
        {
            var rt = new RenderTexture(res > 0 ? res : simResolution, res > 0 ? res : simResolution, 0, fmt)
            { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            rt.Create();
            return rt;
        }

        static void Clear(RenderTexture rt)
        {
            if (rt == null) return;
            var prev = RenderTexture.active;
            RenderTexture.active = rt;
            GL.Clear(false, true, Color.clear);
            RenderTexture.active = prev;
        }
    }
}

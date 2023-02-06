using System;
using UnityEngine;
using UnityEngine.InputSystem;

namespace BioFloor
{

    [RequireComponent(typeof(BioFloorController))]
    public class FootstepInputSimulator : MonoBehaviour, IBioDisturbanceSource
    {
        [SerializeField] Camera view;

        [Header("Footstep")]
        [SerializeField, Range(0.02f, 0.6f), Tooltip("Contact radius in metres. A foot, not a puddle")]
        float footRadius = 0.15f;
        [SerializeField, Range(0f, 4f)] float pressure = 1f;
        [Tooltip("A real step lands on the heel and then rolls onto the forefoot. Two impulses a fraction apart read as a foot; one reads as a stamp")]
        [SerializeField, Range(0f, 0.3f)] float forefootDelay = 0.085f;
        [SerializeField, Range(0f, 1f)] float forefootStrength = 0.45f;

        [Header("Walk simulation")]
        [SerializeField, Tooltip("Hold the button and move to lay down a walking path")]
        bool dragWalks = true;
        [SerializeField, Range(0.1f, 1.5f)] float stepInterval = 0.45f;
        [SerializeField, Range(0.05f, 1.5f)] float stepDistance = 0.4f;
        [SerializeField, Range(0f, 0.3f), Tooltip("Feet do not land on the centre line, they land either side of it")]
        float strideOffset = 0.09f;

        [Header("Reference test")]
        [SerializeField, Tooltip("F9. Deterministic comparison scene: reset, prewarm, then hold three fixed standing disturbances so every screenshot shows the same state")]
        bool referenceTest = false;

        [Tooltip("Set to a floor UV to fire one synthetic footstep there on the next frame; clears itself. Lets automated tests click without a mouse")]
        [SerializeField] Vector2 testStepUv = Vector2.zero;

        [Header("Synthetic walkers")]
        [Tooltip("Walks figures across the floor with no input. For checking the water without a hand on the mouse, and for leaving the piece running unattended")]
        [SerializeField] int demoWalkers = 0;
        [SerializeField, Range(0.2f, 3f)] float demoSpeed = 1.1f;

        BioFloorController _floor;
        float[] _demoPhase;
        Vector3[] _demoLast;
        float[] _demoTimer;
        Vector3 _lastStep;
        Vector2 _lastDir = Vector2.up;
        float _stepTimer;
        bool _leftFoot;
        bool _hasLast;

        struct Pending { public Vector3 World; public Vector2 Dir; public float Due; public float Strength; }
        Pending _pending;
        bool _hasPending;

        void Awake() => _floor = GetComponent<BioFloorController>();
        void Reset() { view = Camera.main; }

        static readonly Vector2[] RefPoints =
        {
            new Vector2(0.35f, 0.68f),
            new Vector2(0.78f, 0.52f),
            new Vector2(0.45f, 0.20f),
        };

        public void CollectDisturbances(Action<BioDisturbance> sink)
        {
            if (_floor == null) _floor = GetComponent<BioFloorController>();

            var kb = Keyboard.current;
            if (kb != null && kb.f9Key.wasPressedThisFrame)
            {
                referenceTest = !referenceTest;
                if (referenceTest) _floor.ResetAndPrewarm();
            }
            if (referenceTest)
            {

                for (int i = 0; i < RefPoints.Length; i++)
                    sink(new BioDisturbance
                    {
                        Uv = RefPoints[i], Direction = Vector2.up, Strength = pressure,
                        Radius = footRadius * 1.5f, Sustained = true
                    });
            }

            if (testStepUv != Vector2.zero)
            {
                sink(new BioDisturbance
                {
                    Uv = testStepUv, Direction = Vector2.up, Strength = pressure,
                    Radius = footRadius, Sustained = false
                });
                testStepUv = Vector2.zero;
            }

            DriveDemoWalkers(sink);
            if (view == null) view = Camera.main;
            if (view == null || Mouse.current == null) return;

            if (_hasPending && Time.time >= _pending.Due)
            {
                Emit(sink, _pending.World, _pending.Dir, _pending.Strength);
                _hasPending = false;
            }

            bool down = Mouse.current.leftButton.wasPressedThisFrame;
            bool held = Mouse.current.leftButton.isPressed;

            if (!TryFloorPoint(out Vector3 world))
            {
                if (!held) _hasLast = false;
                return;
            }

            if (down)
            {
                Step(sink, world);
                _stepTimer = 0f;
            }

            if (held)
            {

                Vector2 suv = _floor.Map.WorldToUv(world);
                if (FloorCoordinateMapper.InBounds(suv))
                    sink(new BioDisturbance
                    {
                        Uv = suv, Direction = _lastDir, Strength = pressure,
                        Radius = footRadius * 1.5f, Sustained = true
                    });

                if (dragWalks && !down)
                {
                    _stepTimer += Time.deltaTime;
                    float moved = _hasLast ? Vector3.Distance(world, _lastStep) : 999f;
                    if (_stepTimer >= stepInterval && moved >= stepDistance)
                        Step(sink, world);
                }
            }
            else
            {
                _hasLast = false;
            }
        }

        void DriveDemoWalkers(Action<BioDisturbance> sink)
        {
            if (demoWalkers <= 0) return;
            if (_demoPhase == null || _demoPhase.Length != demoWalkers)
            {
                _demoPhase = new float[demoWalkers];
                _demoLast = new Vector3[demoWalkers];
                _demoTimer = new float[demoWalkers];
                for (int i = 0; i < demoWalkers; i++) _demoPhase[i] = i * 2.399f;
            }

            Vector2 size = _floor.Map.FloorSize;
            for (int i = 0; i < demoWalkers; i++)
            {
                _demoPhase[i] += Time.deltaTime * demoSpeed * 0.16f;
                float p = _demoPhase[i];
                Vector2 uv = new Vector2(
                    0.5f + 0.36f * Mathf.Sin(p * 1.00f + i),
                    0.5f + 0.34f * Mathf.Sin(p * 1.37f + i * 2.1f));
                Vector3 world = _floor.Map.UvToWorld(uv);

                Vector2 puv = _floor.Map.WorldToUv(world);
                if (FloorCoordinateMapper.InBounds(puv))
                    sink(new BioDisturbance
                    {
                        Uv = puv, Direction = Vector2.up, Strength = pressure,
                        Radius = footRadius * 1.5f, Sustained = true
                    });

                _demoTimer[i] += Time.deltaTime;
                if (_demoTimer[i] < stepInterval) continue;
                _demoTimer[i] = 0f;

                Vector3 delta = world - _demoLast[i];
                Vector2 dir = new Vector2(delta.x, delta.z);
                dir = dir.sqrMagnitude > 1e-6f ? dir.normalized : Vector2.up;
                _demoLast[i] = world;

                Emit(sink, world, dir, pressure);

                Vector2 suv = _floor.Map.WorldToUv(world);
                if (FloorCoordinateMapper.InBounds(suv))
                    sink(new BioDisturbance
                    {
                        Uv = suv, Direction = dir, Strength = pressure,
                        Radius = footRadius * 1.5f, Sustained = true
                    });
            }
        }

        void Step(Action<BioDisturbance> sink, Vector3 world)
        {
            Vector2 dir = _lastDir;
            if (_hasLast)
            {
                Vector3 delta = world - _lastStep;
                Vector2 d = new Vector2(delta.x, delta.z);
                if (d.sqrMagnitude > 1e-6f) dir = d.normalized;
            }
            _lastDir = dir;

            Vector2 perp = new Vector2(-dir.y, dir.x);
            float side = _leftFoot ? 1f : -1f;
            _leftFoot = !_leftFoot;
            Vector3 placed = world + new Vector3(perp.x, 0f, perp.y) * strideOffset * side;

            Emit(sink, placed, dir, pressure);

            if (forefootStrength > 0f)
            {
                _pending = new Pending
                {
                    World = placed + new Vector3(dir.x, 0f, dir.y) * footRadius * 0.9f,
                    Dir = dir,
                    Due = Time.time + forefootDelay,
                    Strength = pressure * forefootStrength
                };
                _hasPending = true;
            }

            _lastStep = world;
            _hasLast = true;
            _stepTimer = 0f;
        }

        void Emit(Action<BioDisturbance> sink, Vector3 world, Vector2 dir, float strength)
        {
            Vector2 uv = _floor.Map.WorldToUv(world);
            if (!FloorCoordinateMapper.InBounds(uv)) return;
            sink(new BioDisturbance
            {
                Uv = uv, Direction = dir, Strength = strength,
                Radius = footRadius, Sustained = false
            });
        }

        bool TryFloorPoint(out Vector3 world)
        {
            world = default;
            Ray ray = view.ScreenPointToRay(Mouse.current.position.ReadValue());
            Plane floor = new Plane(_floor.transform.up, _floor.transform.position);
            if (!floor.Raycast(ray, out float d)) return false;
            world = ray.GetPoint(d);
            return true;
        }
    }
}

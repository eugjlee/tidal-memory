using UnityEngine;
using UnityEngine.InputSystem;

namespace BioFloor
{

    public class BioFloorDebug : MonoBehaviour
    {
        public enum View { Composite = 1, Height = 2, Flow = 3, Energy = 4, Memory = 5, Currents = 6, SpawnDensity = 7 }

        [SerializeField] BioFloorController floor;
        [SerializeField] View view = View.Composite;
        [SerializeField] bool paused;

        void Reset() => floor = FindFirstObjectByType<BioFloorController>();

        void Update()
        {
            var kb = Keyboard.current;
            if (kb != null)
            {
                if (kb.digit1Key.wasPressedThisFrame) view = View.Composite;
                if (kb.digit2Key.wasPressedThisFrame) view = View.Height;
                if (kb.digit3Key.wasPressedThisFrame) view = View.Flow;
                if (kb.digit4Key.wasPressedThisFrame) view = View.Energy;
                if (kb.digit5Key.wasPressedThisFrame) view = View.Memory;
                if (kb.digit6Key.wasPressedThisFrame) view = View.Currents;
                if (kb.digit7Key.wasPressedThisFrame) view = View.SpawnDensity;
                if (kb.rKey.wasPressedThisFrame && floor != null) floor.ResetSimulation();
                if (kb.spaceKey.wasPressedThisFrame) paused = !paused;
            }
            Shader.SetGlobalInt("_DebugView", view == View.Composite ? 0 : (int)view);
            Time.timeScale = paused ? 0f : 1f;
        }

        void OnDisable() => Shader.SetGlobalInt("_DebugView", 0);
    }
}

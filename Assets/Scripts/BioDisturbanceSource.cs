using UnityEngine;

namespace BioFloor
{

    public struct BioDisturbance
    {
        public Vector2 Uv;
        public Vector2 Direction;
        public float Strength;
        public float Radius;
        public bool Sustained;
    }

    public interface IBioDisturbanceSource
    {

        void CollectDisturbances(System.Action<BioDisturbance> sink);
    }
}

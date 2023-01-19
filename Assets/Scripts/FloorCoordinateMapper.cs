using UnityEngine;

namespace BioFloor
{

    [ExecuteAlways]
    public class FloorCoordinateMapper : MonoBehaviour
    {
        [SerializeField, Tooltip("Floor width in metres, along X")]
        float floorWidth = 12f;
        [SerializeField, Tooltip("Floor length in metres, along Z")]
        float floorLength = 8f;

        public float FloorWidth => floorWidth;
        public float FloorLength => floorLength;
        public Vector2 FloorSize => new Vector2(floorWidth, floorLength);

        public Vector2 WorldToUv(Vector3 world)
        {
            Vector3 local = transform.InverseTransformPoint(world);
            return new Vector2(local.x / floorWidth + 0.5f, local.z / floorLength + 0.5f);
        }

        public Vector3 UvToWorld(Vector2 uv)
        {
            Vector3 local = new Vector3((uv.x - 0.5f) * floorWidth, 0f, (uv.y - 0.5f) * floorLength);
            return transform.TransformPoint(local);
        }

        public Vector2 MetresToUv(float metres)
        {
            return new Vector2(metres / floorWidth, metres / floorLength);
        }

        public static bool InBounds(Vector2 uv)
        {
            return uv.x >= 0f && uv.x <= 1f && uv.y >= 0f && uv.y <= 1f;
        }

        void OnDrawGizmosSelected()
        {
            Gizmos.matrix = transform.localToWorldMatrix;
            Gizmos.color = new Color(0f, 0.7f, 1f, 0.6f);
            Gizmos.DrawWireCube(Vector3.zero, new Vector3(floorWidth, 0f, floorLength));
        }
    }
}

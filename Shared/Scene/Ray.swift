
import simd

struct Ray {
    var origin: float3
    var direction: float3
    
    static func *(transform: float4x4, ray: Ray) -> Ray {
        let originT = (transform * float4(ray.origin, 1)).xyz
        let directionT = (transform * float4(ray.direction, 0)).xyz
        return Ray(origin: originT, direction: directionT)
    }
    
    /// Determine the point along this ray at the given parameter
    func extrapolate(_ parameter: Float) -> float4 {
        return float4(origin + parameter * direction, 1)
    }
    
    /// Determine the parameter corresponding to the point,
    /// assuming it lies on this ray
    func interpolate(_ point: float4) -> Float {
        return length(point.xyz - origin) / length(direction)
    }
}

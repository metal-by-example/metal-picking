
import simd

struct HitResult {
    var node: Node
    var ray: Ray
    var parameter: Float
    
    var intersectionPoint: float3 {
        return ray.origin + parameter * ray.direction
    }
    
    // Test whether one result is closer than another.
    // Only results originating from the same ray can be compared.
    static func < (lhs: HitResult, rhs: HitResult) -> Bool {
        return lhs.parameter < rhs.parameter
    }
}


import simd

struct HitResult {
    var node: Node
    var ray: Ray
    var parameter: Float
    
    var intersectionPoint: float4 {
        return float4(ray.origin + parameter * ray.direction, 1)
    }
    
    static func < (_ lhs: HitResult, _ rhs: HitResult) -> Bool {
        return lhs.parameter < rhs.parameter
    }
}

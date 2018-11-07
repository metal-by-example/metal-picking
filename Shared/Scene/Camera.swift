
import simd

class Camera {
    var fieldOfView: Float = 65.0
    var nearZ: Float = 0.1
    var farZ: Float = 100.0
    
    func projectionMatrix(aspectRatio: Float) -> float4x4 {
        return float4x4(perspectiveProjectionRHFovY: radians_from_degrees(fieldOfView),
                        aspectRatio: aspectRatio,
                        nearZ: nearZ,
                        farZ: farZ)
    }
}

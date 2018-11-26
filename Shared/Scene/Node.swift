
import simd
import MetalKit

class Material {
    var color = float4(x: 1, y: 1, z: 1, w: 1)
    var highlighted = false
}

class Node: Equatable, CustomDebugStringConvertible {
    let identifier = UUID()
    
    var name: String?
    
    weak var parent: Node?
    var children = [Node]()
    
    var camera: Camera?
    
    var mesh: MTKMesh?
    
    var material = Material()
    
    var transform: float4x4
    
    var worldTransform: float4x4 {
        if let parent = parent {
            return parent.worldTransform * transform
        } else {
            return transform
        }
    }
    
    var boundingSphere = BoundingSphere(center: float3(x: 0, y: 0, z: 0), radius: 0)
    
    init() {
        transform = matrix_identity_float4x4
    }
    
    func addChildNode(_ node: Node) {
        if node.parent != nil {
            node.removeFromParent()
        }
        children.append(node)
    }
    
    private func removeChildNode(_ node: Node) {
        children = children.filter { $0 != node } //  In Swift 4.2, this could be written with removeAll(where:)
    }
    
    func removeFromParent() {
        parent?.removeChildNode(self)
    }
    
    func hitTest(_ ray: Ray) -> HitResult? {
        let modelToWorld = worldTransform
        let localRay = modelToWorld.inverse * ray
        
        var nearest: HitResult?
        if let modelPoint = boundingSphere.intersect(localRay) {
            let worldPoint = modelToWorld * modelPoint
            let worldParameter = ray.interpolate(worldPoint)
            nearest = HitResult(node: self, ray: ray, parameter: worldParameter)
        }
        
        var nearestChildHit: HitResult?
        for child in children {
            if let childHit = child.hitTest(ray) {
                if let nearestActualChildHit = nearestChildHit {
                    if childHit < nearestActualChildHit {
                        nearestChildHit = childHit
                    }
                } else {
                    nearestChildHit = childHit
                }
            }
        }
        
        if let nearestActualChildHit = nearestChildHit {
            if let nearestActual = nearest {
                if nearestActualChildHit < nearestActual {
                    return nearestActualChildHit
                }
            } else {
                return nearestActualChildHit
            }
        }
        
        return nearest
    }
    
    static func == (lhs: Node, rhs: Node) -> Bool {
        return lhs.identifier == rhs.identifier
    }
    
    var debugDescription: String { return "<Node>: \(name ?? "unnamed")" }
}


#if os(OSX)
import Cocoa
typealias NSUIViewController = NSViewController
#elseif os(iOS)
import UIKit
typealias NSUIViewController = UIViewController
#endif

import MetalKit

let GridSideCount = 5

class ViewController: NSUIViewController, MTKViewDelegate {
    var mtkView: MTKView {
        return view as! MTKView
    }

    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    let frameSemaphore = DispatchSemaphore(value: MaxInFlightFrameCount)
    var renderer: Renderer!
    var scene = Scene()
    var pointOfView: Node?
    var cameraAngle: Float = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device.makeCommandQueue()
        
        mtkView.device = device
        mtkView.sampleCount = 4
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.delegate = self

        makeScene()

        do {
            renderer = try Renderer(view: mtkView, vertexDescriptor: vertexDescriptor)
        } catch {
            print("\(error)")
        }
    }
    
    lazy var vertexDescriptor: MDLVertexDescriptor = {
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.vertexAttributes[0].name = MDLVertexAttributePosition
        vertexDescriptor.vertexAttributes[0].format = .float3
        vertexDescriptor.vertexAttributes[0].offset = 0
        vertexDescriptor.vertexAttributes[0].bufferIndex = 0
        vertexDescriptor.vertexAttributes[1].name = MDLVertexAttributeNormal
        vertexDescriptor.vertexAttributes[1].format = .float3
        vertexDescriptor.vertexAttributes[1].offset = MemoryLayout<Float>.size * 3
        vertexDescriptor.vertexAttributes[1].bufferIndex = 0
        vertexDescriptor.bufferLayouts[0].stride = MemoryLayout<Float>.size * 6
        return vertexDescriptor
    }()
    
    func makeScene() {
        let sphereRadius: Float = 1
        let spherePadding: Float = 1
        let meshAllocator = MTKMeshBufferAllocator(device: device)
        let mdlMesh = MDLMesh.init(sphereWithExtent: float3(sphereRadius, sphereRadius, sphereRadius),
                                   segments: uint2(20, 20),
                                   inwardNormals: false,
                                   geometryType: .triangles,
                                   allocator: meshAllocator)
        mdlMesh.vertexDescriptor = vertexDescriptor
        
        guard let sphereMesh = try? MTKMesh(mesh: mdlMesh, device: device) else {
            print("Could not create MetalKit mesh from ModelIO mesh"); return
        }
        
        let gridSideLength = (sphereRadius * 2 * Float(GridSideCount)) + (spherePadding * Float(GridSideCount - 1))
        for j in 0..<GridSideCount {
            for i in 0..<GridSideCount {
                let node = Node()
                node.mesh = sphereMesh
                node.material.color = float4(hue: Float(drand48()), saturation: 1.0, brightness: 1.0)
                let position = float3(
                    sphereRadius + Float(i) * (2 * sphereRadius + spherePadding) - (Float(gridSideLength) / 2),
                    sphereRadius + Float(j) * (2 * sphereRadius + spherePadding) - (Float(gridSideLength) / 2),
                    0)
                node.transform = float4x4(translationBy: position)
                node.boundingSphere.radius = sphereRadius
                node.name = "(\(i), \(j))"
                scene.rootNode.addChildNode(node)
            }
        }
        
        let cameraNode = Node()
        cameraNode.transform = float4x4(translationBy: float3(0, 0, 15))
        cameraNode.camera = Camera()
        pointOfView = cameraNode
        scene.rootNode.addChildNode(cameraNode)
    }

    func handleInteraction(at point: CGPoint) {
        guard let cameraNode = pointOfView, let camera = cameraNode.camera else { return }
        
        let viewport = mtkView.bounds // Assume viewport matches window; if not, apply additional inverse viewport xform
        let width = Float(viewport.size.width)
        let height = Float(viewport.size.height)
        let aspectRatio = width / height
        
        let projectionMatrix = camera.projectionMatrix(aspectRatio: aspectRatio)
        let inverseProjectionMatrix = projectionMatrix.inverse

        let viewMatrix = cameraNode.worldTransform.inverse
        let inverseViewMatrix = viewMatrix.inverse

        let clipX = (2 * Float(point.x)) / width - 1
        let clipY = 1 - (2 * Float(point.y)) / height
        let clipCoords = float4(clipX, clipY, 0, 1) // Assume clip space is hemicube, -Z is into the screen

        var eyeRayDir = inverseProjectionMatrix * clipCoords
        eyeRayDir.z = -1
        eyeRayDir.w = 0

        var worldRayDir = (inverseViewMatrix * eyeRayDir).xyz
        worldRayDir = normalize(worldRayDir)

        let eyeRayOrigin = float4(x: 0, y: 0, z: 0, w: 1)
        let worldRayOrigin = (inverseViewMatrix * eyeRayOrigin).xyz

        let ray = Ray(origin: worldRayOrigin, direction: worldRayDir)
        if let hit = scene.hitTest(ray) {
            hit.node.material.highlighted = !hit.node.material.highlighted // In Swift 4.2, this could be written with toggle()
            print("Hit \(hit.node) at \(hit.intersectionPoint)")
        }
    }

    func draw(in view: MTKView) {
        frameSemaphore.wait()
        
        cameraAngle += 0.01
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        guard let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        pointOfView?.transform = float4x4(rotationAroundAxis: float3(x: 0, y: 1, z: 0), by: cameraAngle) *
                                 float4x4(translationBy: float3(0, 0, 15))

        renderer.draw(scene, from: pointOfView, in: renderCommandEncoder)
        
        renderCommandEncoder.endEncoding()
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        
        commandBuffer.addCompletedHandler { _ in
            self.frameSemaphore.signal()
        }
        
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
}

#if os(OSX)
extension ViewController {
    override func mouseDown(with event: NSEvent) {
        var location = view.convert(event.locationInWindow, from: nil)
        location.y = view.bounds.height - location.y // Flip from AppKit default window coordinates to Metal viewport coordinates
        handleInteraction(at: location)
    }
}
#endif

#if os(iOS)
extension ViewController {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let location = touches.first?.location(in: view) {
            handleInteraction(at: location)
        }
    }
}
#endif


import Metal
import MetalKit
import simd

struct RendererInitError: Error {
    var description: String
}

struct InstanceConstants {
    var modelViewProjectionMatrix: float4x4
    var normalMatrix: float4x4
    var color: float4
}

let MaxInFlightFrameCount = 3

let ConstantBufferLength = 65_536 // Adjust this if you need to draw more objects
let ConstantAlignment = 256 // Adjust this if the size of the instance constants struct changes

class Renderer {
    let view: MTKView
    let device: MTLDevice
    let renderPipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    
    var constantBuffers = [MTLBuffer]()
    var frameIndex = 0

    init?(view: MTKView, vertexDescriptor: MDLVertexDescriptor) throws {
        guard let device = view.device else { throw RendererInitError(description: "View device cannot be nil") }
        
        self.device = device
        self.view = view
        
        depthStencilState = Renderer.makeDepthStencilState(device: device)
        
        for _ in 0..<MaxInFlightFrameCount {
            constantBuffers.append(device.makeBuffer(length: ConstantBufferLength, options: [.storageModeShared])!)
        }
        
        do {
            renderPipelineState = try Renderer.makeRenderPipelineState(view: view, vertexDescriptor: vertexDescriptor)
        } catch {
            return nil
        }
    }
    
    class func makeDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = .less
        depthStateDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor:depthStateDescriptor)!
    }
    
    class func makeRenderPipelineState(view: MTKView, vertexDescriptor: MDLVertexDescriptor) throws -> MTLRenderPipelineState {
        guard let device = view.device else { throw RendererInitError(description: "View device cannot be nil") }
        
        guard let library = device.makeDefaultLibrary() else { throw RendererInitError(description: "Failed to create default Metal library") }
        
        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")
        
        let mtlVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
        pipelineDescriptor.sampleCount = view.sampleCount
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat

        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    func draw(_ scene: Scene, from pointOfView: Node?, in renderCommandEncoder: MTLRenderCommandEncoder) {
        guard let cameraNode = pointOfView, let camera = cameraNode.camera else { return }
        
        frameIndex = (frameIndex + 1) % MaxInFlightFrameCount
        
        renderCommandEncoder.setRenderPipelineState(renderPipelineState)
        renderCommandEncoder.setDepthStencilState(depthStencilState)
        
        let viewMatrix = cameraNode.worldTransform.inverse

        let viewport = view.bounds
        let width = Float(viewport.size.width)
        let height = Float(viewport.size.height)
        let aspectRatio = width / height

        let projectionMatrix = camera.projectionMatrix(aspectRatio: aspectRatio)
        
        let worldMatrix = matrix_identity_float4x4
        
        let constantBuffer = constantBuffers[frameIndex]
        renderCommandEncoder.setVertexBuffer(constantBuffer, offset:0, index: 1)
        
        var constantOffset = 0
        draw(scene.rootNode,
             worldTransform: worldMatrix,
             viewMatrix: viewMatrix,
             projectionMatrix: projectionMatrix,
             constantOffset: &constantOffset,
             in: renderCommandEncoder)
    }
    
    func draw(_ node: Node, worldTransform: float4x4, viewMatrix: float4x4, projectionMatrix: float4x4,
              constantOffset: inout Int, in renderCommandEncoder: MTLRenderCommandEncoder)
    {
        let worldMatrix = worldTransform * node.transform
        
        var constants = InstanceConstants(modelViewProjectionMatrix: projectionMatrix * viewMatrix * worldMatrix,
                                          normalMatrix: viewMatrix * worldMatrix,
                                          color: node.material.color)
        
        let constantBuffer = constantBuffers[frameIndex]
        memcpy(constantBuffer.contents() + constantOffset, &constants, MemoryLayout<InstanceConstants>.size)
        
        renderCommandEncoder.setVertexBufferOffset(constantOffset, index: 1)
        
        if let mesh = node.mesh {
            for (index, vertexBuffer) in mesh.vertexBuffers.enumerated() {
                renderCommandEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: index)
            }
            
            for submesh in mesh.submeshes {
                let fillMode: MTLTriangleFillMode = node.material.highlighted ? .lines : .fill
                renderCommandEncoder.setTriangleFillMode(fillMode)
                renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                           indexCount: submesh.indexCount,
                                                           indexType: submesh.indexType,
                                                           indexBuffer: submesh.indexBuffer.buffer,
                                                           indexBufferOffset: submesh.indexBuffer.offset)
            }
        }
        
        constantOffset += ConstantAlignment
        
        for child in node.children {
            draw(child,
                 worldTransform: worldTransform,
                 viewMatrix: viewMatrix,
                 projectionMatrix: projectionMatrix,
                 constantOffset: &constantOffset,
                 in: renderCommandEncoder)
        }
    }
}

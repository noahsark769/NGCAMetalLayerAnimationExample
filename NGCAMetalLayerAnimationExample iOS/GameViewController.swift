//
//  GameViewController.swift
//  NGCAMetalLayerAnimationExample iOS
//
//  Created by Noah Gilmore on 11/21/19.
//  Copyright © 2019 Noah Gilmore. All rights reserved.
//

import UIKit
import MetalKit

extension matrix_float4x4 {
    static func identity() -> matrix_float4x4 {
        return matrix_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
    }

    static func scale(x: Float, y: Float) -> matrix_float4x4 {
        return matrix_float4x4.init(columns:(vector_float4(x, 0, 0, 0),
                                             vector_float4(0, y, 0, 0),
                                             vector_float4(0, 0, 1, 0),
                                             vector_float4(0, 0, 0, 1)))
    }

    static func scale(xy: Float) -> matrix_float4x4 {
        return self.scale(x: xy, y: xy)
    }

//    static func ortographic_projection(left: Float, right: Float, top: Float, bottom: Float, near: Float, far: Float) -> matrix_float4x4 {
//        let xs = 2.0 / (right - left)
//        let ys = 2.0 / (top - bottom)
//        let zs = -2.0 / (far - near)
//        let tx = -((right + left) / (right - left))
//        let ty = -((top + bottom) / (top - bottom))
//        let tz = -((far + near) / (far - near))
//
//        return matrix_float4x4.init(
//            rows: [
//                vector_float4(xs,  0,  0, tx),
//                vector_float4( 0, ys,  0, ty),
//                vector_float4( 0,  0, zs, tz),
//                vector_float4( 0,  0,  0,  1)
//            ]
//        )
//    }
}

class CustomCAMetalLayer: CAMetalLayer {
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var uniforms = Uniforms(projectionMatrix: .identity(), modelViewMatrix: .identity())

    private var vertices: [Vertex]!
    private var vertexBuffer: MTLBuffer!
    private var uniformsBuffer: MTLBuffer!

    var ngScale: CGFloat = 1 {
        didSet {
            self.setNeedsDisplay()
        }
    }

    override init() {
        super.init()

        self.needsDisplayOnBoundsChange = true

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("This sytem doesn't have a GPU mate")
        }
        self.device = device
        self.pixelFormat = .bgra8Unorm

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Could not create command queue, something's wrong")
        }

        guard let shaderLibrary = device.makeDefaultLibrary() else {
            fatalError("Unable to find device library. Maybe bundle issue?")
        }
        guard let vertexFunction = shaderLibrary.makeFunction(name: "vertex_shader") else {
            fatalError("Unable to find vertex function. Are you sure you defined it and spelled the name right?")
        }
        guard let fragmentFunction = shaderLibrary.makeFunction(name: "fragment_shader") else {
            fatalError("Unable to find fragment function. Are you sure you defined it and spelled the name right?")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        let pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        self.commandQueue = commandQueue
        self.pipelineState = pipelineState

        self.vertices = [
            Vertex(position: SIMD3<Float>(0, 0, 0)),
            Vertex(position: SIMD3<Float>(0.5, 0, 0)),
            Vertex(position: SIMD3<Float>(0, 0.5, 0)),
        ]
        guard let vertexBuffer = device.makeBuffer(
            bytes: UnsafeMutablePointer(mutating: vertices),
            length: MemoryLayout<Vertex>.size * vertices.count,
            options: [.cpuCacheModeWriteCombined]
        ) else {
            fatalError("Unable to allocate vertex buffer")
        }
        self.vertexBuffer = vertexBuffer

        guard let uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<Uniforms>.size * 1,
            options: [.cpuCacheModeWriteCombined]
        ) else {
            fatalError("Unable to allocate uniforms buffer")
        }
        self.uniformsBuffer = uniformsBuffer

        self.setNeedsDisplay()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func blockRequestingNextDrawable() -> CAMetalDrawable {
        var drawable: CAMetalDrawable? = nil
        while (drawable == nil) {
            drawable = self.nextDrawable()
        }
        return drawable!
    }

    private func renderPassDescriptor(texture: MTLTexture) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        descriptor.colorAttachments[0].storeAction = .store
        return descriptor
    }

    private func update() {
        self.uniforms.modelViewMatrix = matrix_float4x4.scale(xy: Float(self.ngScale))
        let uniforms = [
            self.uniforms
        ]
        memcpy(self.uniformsBuffer.contents(), UnsafeRawPointer(uniforms), MemoryLayout<Uniforms>.size)
    }

    override func display() {
        self.update()

        guard let commandBuffer = self.commandQueue.makeCommandBuffer() else {
            fatalError("Unable to create command buffer, maybe the GPU is fubar'd")
        }
        let drawable = self.blockRequestingNextDrawable()
        let renderPassDescriptor = self.renderPassDescriptor(texture: drawable.texture)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            fatalError("Unable to create command encoder, possible something is screwed up")
        }

        encoder.setRenderPipelineState(self.pipelineState)

        encoder.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(self.uniformsBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

class MetalView: UIView {
    override class var layerClass: AnyClass {
        return CustomCAMetalLayer.self
    }
}

// Our iOS specific view controller
class GameViewController: UIViewController {
    private let metalView = MetalView()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addSubview(metalView)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        metalView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        metalView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        metalView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true

        let button = UIButton()
        button.setTitle("Expand!", for: .normal)
        button.setTitleColor(.red, for: .normal)
        button.addTarget(self, action: #selector(didTapButton), for: .touchUpInside)
        self.view.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20).isActive = true
        button.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -20).isActive = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    @objc private func didTapButton() {
        guard let layer = self.metalView.layer as? CustomCAMetalLayer else {
            return
        }
        layer.ngScale = 2
    }
}

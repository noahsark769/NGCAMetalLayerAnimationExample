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
}

final class Renderer {
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var uniforms = Uniforms(projectionMatrix: .identity(), modelViewMatrix: .identity())

    private var vertices: [Vertex]!
    private var vertexBuffer: MTLBuffer!
    private var uniformsBuffer: MTLBuffer!

    var scale: Float = 0

    init(device: MTLDevice) {
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
    }

    private func update() {
        self.uniforms.modelViewMatrix = matrix_float4x4.scale(xy: self.scale)
        let uniforms = [
            self.uniforms
        ]
        memcpy(self.uniformsBuffer.contents(), UnsafeRawPointer(uniforms), MemoryLayout<Uniforms>.size)
    }

    private func renderPassDescriptor(texture: MTLTexture) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        descriptor.colorAttachments[0].storeAction = .store
        return descriptor
    }

    func draw(drawable: CAMetalDrawable) {
        print("Calling display() with scale: \(self.scale)")
        self.update()

        guard let commandBuffer = self.commandQueue.makeCommandBuffer() else {
            fatalError("Unable to create command buffer, maybe the GPU is fubar'd")
        }
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

class CustomCAMetalLayer: CAMetalLayer {
    private var renderer: Renderer!
    @NSManaged var ngScale: CGFloat

    override class func needsDisplay(forKey key: String) -> Bool {
        if key == "ngScale" {
            return true
        }
        return super.needsDisplay(forKey: key)
    }

    override func action(forKey key: String) -> CAAction? {
        if key == "ngScale" {
            let animation = CABasicAnimation(keyPath: key)
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.fromValue = self.presentation()?.ngScale
            return animation
        }
        return super.action(forKey: key)
    }

    override init() {
        super.init()
        self.device = MTLCreateSystemDefaultDevice()!
        self.renderer = Renderer(device: self.device!)
        self.ngScale = 1
        self.setNeedsDisplay()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        guard let layer = layer as? CustomCAMetalLayer else {
            return
        }
        self.renderer = layer.renderer
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

    override func display() {
        guard let scale = self.presentation()?.ngScale else {
            return
        }
        self.renderer.scale = Float(scale)
        let drawable = self.blockRequestingNextDrawable()
        self.renderer.draw(drawable: drawable)
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
    private let button = UIButton()
    private let keyFrameButton = UIButton()
    private var isAnimating = false {
        didSet {
            self.button.isEnabled = !self.isAnimating
            self.keyFrameButton.isEnabled = !self.isAnimating
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addSubview(metalView)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        metalView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        metalView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        metalView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true

        button.setTitle("Expand!", for: .normal)
        button.setTitleColor(.red, for: .normal)
        button.setTitleColor(UIColor.red.withAlphaComponent(0.5), for: .disabled)
        button.addTarget(self, action: #selector(didTapButton), for: .touchUpInside)
        self.view.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -80).isActive = true
        button.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 80).isActive = true

        keyFrameButton.setTitle("Keyframe!", for: .normal)
        keyFrameButton.setTitleColor(.red, for: .normal)
        keyFrameButton.setTitleColor(UIColor.red.withAlphaComponent(0.5), for: .disabled)
        keyFrameButton.addTarget(self, action: #selector(didTapKeyframeButton), for: .touchUpInside)
        self.view.addSubview(keyFrameButton)
        keyFrameButton.translatesAutoresizingMaskIntoConstraints = false
        keyFrameButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -80).isActive = true
        keyFrameButton.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 120).isActive = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    @objc private func didTapButton() {
        guard !self.isAnimating else { return }
        guard let layer = self.metalView.layer as? CustomCAMetalLayer else {
            return
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(2)
        CATransaction.setAnimationTimingFunction(.init(name: .easeInEaseOut))
        CATransaction.setCompletionBlock {
            self.isAnimating = false
        }

        if layer.ngScale > 1 {
            layer.ngScale = 1
        } else {
            layer.ngScale = 1.9
        }
        CATransaction.commit()
        self.isAnimating = true
    }

    @objc private func didTapKeyframeButton() {
        guard !self.isAnimating else { return }

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            self.isAnimating = false
        }
        let animation = CAKeyframeAnimation()
        animation.keyPath = "ngScale"
        animation.values = [(self.metalView.layer as! CustomCAMetalLayer).ngScale, -1, 1.9, -1.9, (self.metalView.layer as! CustomCAMetalLayer).ngScale]
        animation.keyTimes = [0, 0.2, 0.5, 0.8, 1]
        animation.timingFunctions = [.init(name: .easeInEaseOut), .init(name: .easeInEaseOut), .init(name: .easeInEaseOut), .init(name: .easeInEaseOut)]
        animation.duration = 8

//        animation.isAdditive = true
        self.metalView.layer.add(animation, forKey: "expandScale")

        CATransaction.commit()
        self.isAnimating = true
    }
}

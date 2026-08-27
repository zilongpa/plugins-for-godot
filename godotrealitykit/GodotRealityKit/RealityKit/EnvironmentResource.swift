//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc.
//
// Licensed under the MIT license (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// LICENSE
//
//===----------------------------------------------------------------------===//

import RealityKit

public struct EnvironmentResource: @unchecked Sendable {
    var value: RealityKit.EnvironmentResource?

    public init() {
        self.value = nil
    }

    public func isSome() -> Bool {
        return value != nil
    }

    public mutating func loadFromEquirectangularMTLTextureSync(_ mtlTexture: sending MTLTexture) {
        MainActor.assumeIsolated {
            do {
                var textureToCopy: MTLTexture = mtlTexture
                if textureToCopy.storageMode == .private {
                    let desc = MTLTextureDescriptor()
                    desc.width = mtlTexture.width
                    desc.height = mtlTexture.height
                    desc.pixelFormat = .rgba32Float
                    desc.usage = [.shaderRead, .shaderWrite]
                    let device = mtlTexture.device
                    guard let newTex = device.makeTexture(descriptor: desc) else {
                        throw GenericError.value("cannot make new MTLTexture")
                    }
                    guard let cmdBuffer = device.makeCommandQueue()?.makeCommandBuffer() else {
                        throw GenericError.value("cannot make command queue")
                    }

                    class BundleMarker {}
                    let library = try device.makeDefaultLibrary(bundle: Bundle(for: BundleMarker.self))
                    guard let function = library.makeFunction(name: "decompress") else {
                        throw GenericError.value("cannot get decompress function")
                    }
                    let pipelineState = try device.makeComputePipelineState(function: function)

                    guard let encoder = cmdBuffer.makeComputeCommandEncoder() else {
                        throw GenericError.value("cannot make compute shader")
                    }
                    encoder.label = "Decompress BC6H"
                    encoder.setComputePipelineState(pipelineState)
                    encoder.setTexture(mtlTexture, index: 0)
                    encoder.setTexture(newTex, index: 1)

                    let w = pipelineState.threadExecutionWidth
                    let h = pipelineState.maxTotalThreadsPerThreadgroup / w
                    let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)

                    let threadgroupsPerGrid = MTLSize(
                        width: (newTex.width + w - 1) / w,
                        height: (newTex.height + h - 1) / h,
                        depth: 1
                    )

                    encoder.dispatchThreadgroups(
                        threadgroupsPerGrid,
                        threadsPerThreadgroup: threadsPerThreadgroup
                    )
                    encoder.endEncoding()

                    cmdBuffer.commit()
                    cmdBuffer.waitUntilCompleted()
                    textureToCopy = newTex
                }

                let height = textureToCopy.height
                let width = textureToCopy.width
                guard let bitsPerComp: Int = {
                    switch textureToCopy.pixelFormat {
                    case .rgba32Float:
                        return 32
                    default:
                        assertionFailure("Unhandled pixel format \(textureToCopy.pixelFormat)")
                        return nil
                    }
                }() else {
                    return
                }
                let bytesPerRow = 4 * bitsPerComp * width
                guard let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: bitsPerComp,
                    bytesPerRow: bytesPerRow,
                    space: .init(name: CGColorSpace.genericRGBLinear)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                ) else {
                    throw GenericError.value("cannot make CGContext")
                }
                guard let data = context.data else {
                    throw GenericError.value("cannot get CGContext data")
                }
                textureToCopy.getBytes(
                    data,
                    bytesPerRow: bytesPerRow,
                    from: .init(origin: .init(), size: .init(width: width, height: height, depth: 1)),
                    mipmapLevel: 0
                )

                guard let cgImage = context.makeImage() else {
                    throw GenericError.value("cannot get CGImage from CGContext")
                }

                loadFromEquirectangularCGImageSync(cgImage)
            } catch {
                print("Error loading EnvironmentResource from MTLTexture: \(error)")
            }
        }
    }

    public mutating func loadFromEquirectangularCGImageSync(_ cgImage: CGImage) {
        MainActor.assumeIsolated {
            do {
                let cube = try RealityKit.TextureResource(
                    cubeFromEquirectangular: cgImage,
                    options: .init(
                        semantic: .hdrColor,
                        compression: .default,
                        mipmapsMode: .allocateAndGenerateAll
                    )
                )
                let env = try RealityKit.EnvironmentResource(
                    cube: cube,
                    options: .init(
                        samplingQuality: .normal,
                        compression: .default
                    )
                )
                self.value = env
            } catch {
                print("Error loading EnvironmentResource from CGImage: \(error)")
            }
        }
    }
}

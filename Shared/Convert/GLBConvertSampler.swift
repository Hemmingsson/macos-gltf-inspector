import GLTFKit2
import Metal

enum GLBTextureFilter {
    static func minMip(from filter: GLTFMinMipFilter) -> (MTLSamplerMinMagFilter, MTLSamplerMipFilter) {
        switch filter {
        case .linear:
            return (.linear, .notMipmapped)
        case .nearest:
            return (.nearest, .notMipmapped)
        case .nearestNearest:
            return (.nearest, .nearest)
        case .linearNearest:
            return (.linear, .nearest)
        case .nearestLinear:
            return (.nearest, .linear)
        default:
            return (.linear, .linear)
        }
    }

    static func mag(from filter: GLTFMagFilter) -> MTLSamplerMinMagFilter {
        switch filter {
        case .nearest:
            return .nearest
        default:
            return .linear
        }
    }

    static func addressMode(from addressMode: GLTFAddressMode) -> MTLSamplerAddressMode {
        switch addressMode {
        case .repeat:
            return .repeat
        case .mirroredRepeat:
            return .mirrorRepeat
        default:
            return .clampToEdge
        }
    }
}

extension MTLSamplerDescriptor {
    convenience init(from sampler: GLTFTextureSampler) {
        self.init()
        self.normalizedCoordinates = true
        let (minFilter, mipFilter) = GLBTextureFilter.minMip(from: sampler.minMipFilter)
        self.minFilter = minFilter
        self.mipFilter = mipFilter
        self.magFilter = GLBTextureFilter.mag(from: sampler.magFilter)
        self.sAddressMode = GLBTextureFilter.addressMode(from: sampler.wrapS)
        self.tAddressMode = GLBTextureFilter.addressMode(from: sampler.wrapT)
    }
}

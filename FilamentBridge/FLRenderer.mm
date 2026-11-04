#import "FLRenderer.h"

#import <ImageIO/ImageIO.h>

#include <filament/Box.h>
#include <filament/Camera.h>
#include <filament/ColorGrading.h>
#include <filament/Engine.h>
#include <filament/IndirectLight.h>
#include <filament/Options.h>
#include <filament/RenderableManager.h>
#include <filament/RenderTarget.h>
#include <filament/Renderer.h>
#include <filament/Scene.h>
#include <filament/SwapChain.h>
#include <filament/Texture.h>
#include <filament/ToneMapper.h>
#include <filament/View.h>
#include <filament/Viewport.h>

#include <filament-iblprefilter/IBLPrefilterContext.h>

#include <gltfio/Animator.h>
#include <gltfio/AssetLoader.h>
#include <gltfio/FilamentAsset.h>
#include <gltfio/FilamentInstance.h>
#include <gltfio/MaterialProvider.h>
#include <gltfio/ResourceLoader.h>
#include <gltfio/TextureProvider.h>
#include <gltfio/materials/uberarchive.h>

#include <backend/PixelBufferDescriptor.h>
#include <math/mat3.h>
#include <utils/EntityManager.h>

#include <cmath>
#include <string>
#include <unordered_map>
#include <vector>

using namespace filament;
using namespace filament::gltfio;
using namespace filament::math;
using utils::Entity;
using utils::EntityManager;

static NSString* const FLErrorDomain = @"FilamentBridge";

static BOOL fail(NSError** error, NSInteger code, NSString* message) {
    if (error) {
        *error = [NSError errorWithDomain:FLErrorDomain code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

namespace {

struct Environment {
    Texture* reflections = nullptr;
    Texture* irradiance = nullptr;
};

/// One Metal engine per process with the gltfio ubershader materials, the texture decoders, the
/// IBL prefilter and every environment prefiltered so far. Never torn down: extensions and the
/// app keep it for their lifetime.
struct Shared {
    Engine* engine = nullptr;
    MaterialProvider* materials = nullptr;
    AssetLoader* loader = nullptr;
    TextureProvider* stb = nullptr;
    TextureProvider* ktx = nullptr;
    IBLPrefilterContext* prefilter = nullptr;
    std::unordered_map<std::string, Environment> environments;

    static Shared* get() {
        static Shared* shared = [] {
            auto* s = new Shared();
            s->engine = Engine::Builder()
                .backend(Engine::Backend::METAL)
                .featureLevel(Engine::FeatureLevel::FEATURE_LEVEL_3)
                .build();
            if (!s->engine) return s;
            s->materials = createUbershaderProvider(
                s->engine, UBERARCHIVE_DEFAULT_DATA, UBERARCHIVE_DEFAULT_SIZE);
            s->loader = AssetLoader::create({s->engine, s->materials});
            s->stb = createStbProvider(s->engine);
            s->ktx = createKtx2Provider(s->engine);
            s->prefilter = new IBLPrefilterContext(*s->engine);
            return s;
        }();
        return shared;
    }

    /// Decodes the Radiance `.hdr` with ImageIO (float, linear), uploads it as RGBA16F with
    /// mips, then cubemap → specular + irradiance on the GPU.
    const Environment* environment(NSString* path, NSError** error) {
        std::string key = path.UTF8String;
        if (auto it = environments.find(key); it != environments.end()) return &it->second;

        NSURL* url = [NSURL fileURLWithPath:path];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
        if (!source) { fail(error, 10, @"Environment unreadable"); return nullptr; }
        NSDictionary* options = @{(id)kCGImageSourceShouldAllowFloat: @YES};
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)options);
        CFRelease(source);
        if (!image) { fail(error, 11, @"Environment undecodable"); return nullptr; }

        const size_t width = CGImageGetWidth(image);
        const size_t height = CGImageGetHeight(image);
        std::vector<float> rgba(width * height * 4);
        CGColorSpaceRef linear = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
        CGContextRef context = CGBitmapContextCreate(
            rgba.data(), width, height, 32, width * 16, linear,
            CGBitmapInfo(kCGImageAlphaPremultipliedLast) | kCGBitmapFloatComponents | kCGBitmapByteOrder32Little);
        CGColorSpaceRelease(linear);
        if (!context) { CGImageRelease(image); fail(error, 12, @"Environment context"); return nullptr; }
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
        CGContextRelease(context);
        CGImageRelease(image);

        auto* half4 = new std::vector<_Float16>(rgba.size());
        for (size_t i = 0; i < rgba.size(); ++i) {
            (*half4)[i] = static_cast<_Float16>(std::min(rgba[i], 65000.0f));
        }

        Texture* equirect = Texture::Builder()
            .width(uint32_t(width))
            .height(uint32_t(height))
            .levels(uint8_t(std::floor(std::log2(double(std::max(width, height)))) + 1))
            .format(Texture::InternalFormat::RGBA16F)
            .sampler(Texture::Sampler::SAMPLER_2D)
            .usage(Texture::Usage::DEFAULT | Texture::Usage::GEN_MIPMAPPABLE)
            .build(*engine);
        Texture::PixelBufferDescriptor buffer(
            half4->data(), half4->size() * sizeof(_Float16),
            Texture::Format::RGBA, Texture::Type::HALF,
            [](void*, size_t, void* user) { delete static_cast<std::vector<_Float16>*>(user); },
            half4);
        equirect->setImage(*engine, 0, std::move(buffer));
        equirect->generateMipmaps(*engine);

        IBLPrefilterContext::EquirectangularToCubemap toCubemap(*prefilter);
        Texture* cubemap = toCubemap(equirect);
        IBLPrefilterContext::SpecularFilter specular(*prefilter);
        IBLPrefilterContext::IrradianceFilter irradiance(*prefilter);
        Environment made;
        made.reflections = specular(cubemap);
        made.irradiance = irradiance(cubemap);
        engine->destroy(equirect);
        engine->destroy(cubemap);
        return &(environments[key] = made);
    }
};

} // namespace

@interface FLRenderer ()
- (nullable instancetype)initWithError:(NSError**)error;
@end

@implementation FLRenderer {
    Shared* _shared;
    Renderer* _renderer;
    View* _view;
    Scene* _scene;
    Entity _cameraEntity;
    Camera* _camera;
    SwapChain* _liveSwap;
    RenderTarget* _stillTarget;
    Texture* _stillColor;
    Texture* _stillDepth;
    NSInteger _stillWidth;
    NSInteger _stillHeight;
    FilamentAsset* _asset;
    IndirectLight* _light;
    const Environment* _environment;
    ColorGrading* _grading;
    float _iblIntensity;
    float _yawDegrees;
    double4 _clear;
    BOOL _ortho;
    double _fov;
    double _orthoHeight;
    double _near;
    double _far;
}

+ (nullable FLRenderer*)makeRendererWithError:(NSError**)error {
    return [[FLRenderer alloc] initWithError:error];
}

- (nullable instancetype)initWithError:(NSError**)error {
    NSAssert(NSThread.isMainThread, @"FLRenderer is main-thread only");
    self = [super init];
    if (!self) return nil;
    _shared = Shared::get();
    if (!_shared->engine) {
        fail(error, 1, @"Filament couldn't create a Metal engine");
        return nil;
    }
    Engine* engine = _shared->engine;
    _renderer = engine->createRenderer();
    _view = engine->createView();
    _scene = engine->createScene();
    _cameraEntity = EntityManager::get().create();
    _camera = engine->createCamera(_cameraEntity);
    _view->setScene(_scene);
    _view->setCamera(_camera);
    _view->setBlendMode(BlendMode::TRANSLUCENT);
    MultiSampleAntiAliasingOptions msaa;
    msaa.enabled = true;
    msaa.sampleCount = 4;
    _view->setMultiSampleAntiAliasingOptions(msaa);
    _iblIntensity = 1;
    _fov = 45;
    _near = 0.01;
    _far = 100;
    _camera->setExposure(1.0f);
    [self setToneMapper:FLToneMapperPBRNeutral];
    [self setBackgroundRed:0 green:0 blue:0 alpha:0];
    return self;
}

- (void)dealloc {
    Engine* engine = _shared->engine;
    [self removeAsset];
    if (_light) engine->destroy(_light);
    if (_grading) engine->destroy(_grading);
    if (_liveSwap) engine->destroy(_liveSwap);
    [self destroyStillTarget];
    engine->destroyCameraComponent(_cameraEntity);
    EntityManager::get().destroy(_cameraEntity);
    engine->destroy(_view);
    engine->destroy(_scene);
    engine->destroy(_renderer);
}

// MARK: Model

- (void)removeAsset {
    if (!_asset) return;
    _scene->removeEntities(_asset->getEntities(), _asset->getEntityCount());
    _shared->loader->destroyAsset(_asset);
    _asset = nullptr;
}

- (BOOL)loadModelAtPath:(NSString*)path error:(NSError**)error {
    NSData* data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
    if (!data) return NO;
    [self removeAsset];
    FilamentAsset* asset = _shared->loader->createAsset(
        static_cast<const uint8_t*>(data.bytes), uint32_t(data.length));
    if (!asset) return fail(error, 2, @"Filament couldn't parse the file");

    ResourceConfiguration config;
    config.engine = _shared->engine;
    config.gltfPath = path.fileSystemRepresentation;
    config.normalizeSkinningWeights = true;
    ResourceLoader resources(config);
    resources.addTextureProvider("image/png", _shared->stb);
    resources.addTextureProvider("image/jpeg", _shared->stb);
    resources.addTextureProvider("image/ktx2", _shared->ktx);
    if (!resources.loadResources(asset)) {
        _shared->loader->destroyAsset(asset);
        return fail(error, 3, @"Filament couldn't load the file's buffers or textures");
    }
    asset->releaseSourceData();
    _asset = asset;
    _scene->addEntities(asset->getEntities(), asset->getEntityCount());
    return YES;
}

- (BOOL)hasModel { return _asset != nullptr; }

- (simd_float3)boundsMin {
    if (!_asset) return simd_make_float3(0, 0, 0);
    float3 v = _asset->getBoundingBox().min;
    return simd_make_float3(v.x, v.y, v.z);
}

- (simd_float3)boundsMax {
    if (!_asset) return simd_make_float3(0, 0, 0);
    float3 v = _asset->getBoundingBox().max;
    return simd_make_float3(v.x, v.y, v.z);
}

- (NSInteger)renderableCount { return _asset ? NSInteger(_asset->getRenderableEntityCount()) : 0; }

- (NSInteger)materialVariantCount {
    return _asset ? NSInteger(_asset->getInstance()->getMaterialVariantCount()) : 0;
}

- (void)applyMaterialVariant:(NSInteger)index {
    if (!_asset) return;
    FilamentInstance* instance = _asset->getInstance();
    if (index < 0 || size_t(index) >= instance->getMaterialVariantCount()) index = 0;
    if (instance->getMaterialVariantCount() > 0) instance->applyMaterialVariant(size_t(index));
}

// MARK: Look

- (BOOL)setEnvironmentPath:(nullable NSString*)path error:(NSError**)error {
    if (!path) {
        _environment = nullptr;
    } else {
        const Environment* environment = _shared->environment(path, error);
        if (!environment) return NO;
        _environment = environment;
    }
    [self rebuildLight];
    return YES;
}

- (void)setEnvironmentIntensity:(float)intensity yawDegrees:(float)yaw {
    _iblIntensity = intensity;
    _yawDegrees = yaw;
    if (_light) {
        _light->setIntensity(intensity);
        _light->setRotation(mat3f::rotation(yaw * float(M_PI) / 180.0f, float3{0, 1, 0}));
    }
}

- (void)rebuildLight {
    Engine* engine = _shared->engine;
    _scene->setIndirectLight(nullptr);
    if (_light) {
        engine->destroy(_light);
        _light = nullptr;
    }
    if (!_environment) return;
    _light = IndirectLight::Builder()
        .reflections(_environment->reflections)
        .irradiance(_environment->irradiance)
        .intensity(_iblIntensity)
        .rotation(mat3f::rotation(_yawDegrees * float(M_PI) / 180.0f, float3{0, 1, 0}))
        .build(*engine);
    _scene->setIndirectLight(_light);
}

- (void)setExposure:(float)multiplier {
    _camera->setExposure(multiplier);
}

- (void)setToneMapper:(FLToneMapper)toneMapper {
    Engine* engine = _shared->engine;
    ColorGrading* grading = nullptr;
    switch (toneMapper) {
        case FLToneMapperACES: {
            ACESToneMapper mapper;
            grading = ColorGrading::Builder().toneMapper(&mapper).build(*engine);
            break;
        }
        case FLToneMapperACESLegacy: {
            ACESLegacyToneMapper mapper;
            grading = ColorGrading::Builder().toneMapper(&mapper).build(*engine);
            break;
        }
        case FLToneMapperLinear: {
            LinearToneMapper mapper;
            grading = ColorGrading::Builder().toneMapper(&mapper).build(*engine);
            break;
        }
        case FLToneMapperPBRNeutral:
        default: {
            PBRNeutralToneMapper mapper;
            grading = ColorGrading::Builder().toneMapper(&mapper).build(*engine);
            break;
        }
    }
    _view->setColorGrading(grading);
    if (_grading) engine->destroy(_grading);
    _grading = grading;
}

- (void)setBackgroundRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha {
    _clear = double4{red * alpha, green * alpha, blue * alpha, alpha};
    Renderer::ClearOptions options;
    options.clearColor = _clear;
    options.clear = true;
    options.discard = true;
    _renderer->setClearOptions(options);
}

// MARK: Camera

- (void)lookFromEye:(simd_double3)eye target:(simd_double3)target {
    _camera->lookAt(double3{eye.x, eye.y, eye.z}, double3{target.x, target.y, target.z}, double3{0, 1, 0});
}

- (void)setPerspectiveFieldOfView:(double)degrees near:(double)near far:(double)far {
    _ortho = NO;
    _fov = degrees;
    _near = near;
    _far = far;
}

- (void)setOrthographicHeight:(double)height near:(double)near far:(double)far {
    _ortho = YES;
    _orthoHeight = height;
    _near = near;
    _far = far;
}

- (void)prepareWithWidth:(NSInteger)width height:(NSInteger)height time:(double)time {
    _view->setViewport({0, 0, uint32_t(width), uint32_t(height)});
    const double aspect = double(width) / double(std::max<NSInteger>(height, 1));
    if (_ortho) {
        const double h = _orthoHeight / 2;
        _camera->setProjection(Camera::Projection::ORTHO, -h * aspect, h * aspect, -h, h, _near, _far);
    } else {
        _camera->setProjection(_fov, aspect, _near, _far, Camera::Fov::VERTICAL);
    }
    if (_asset && self.playsAnimation) {
        Animator* animator = _asset->getInstance()->getAnimator();
        if (animator->getAnimationCount() > 0) {
            const double duration = std::max(double(animator->getAnimationDuration(0)), 1e-3);
            animator->applyAnimation(0, float(std::fmod(time, duration)));
            animator->updateBoneMatrices();
        }
    }
}

// MARK: Live

- (void)attachLayer:(CAMetalLayer*)layer {
    [self detachLayer];
    layer.opaque = NO;
    _liveSwap = _shared->engine->createSwapChain((__bridge void*)layer, SwapChain::CONFIG_TRANSPARENT);
}

- (void)detachLayer {
    if (!_liveSwap) return;
    _shared->engine->destroy(_liveSwap);
    _liveSwap = nullptr;
    _shared->engine->flushAndWait();
}

- (void)renderFrameWithWidth:(NSInteger)width height:(NSInteger)height time:(double)time {
    if (!_liveSwap || width <= 0 || height <= 0) return;
    [self prepareWithWidth:width height:height time:time];
    if (_renderer->beginFrame(_liveSwap)) {
        _renderer->render(_view);
        _renderer->endFrame();
    }
}

// MARK: Still

- (void)destroyStillTarget {
    Engine* engine = _shared->engine;
    if (_stillTarget) engine->destroy(_stillTarget);
    if (_stillColor) engine->destroy(_stillColor);
    if (_stillDepth) engine->destroy(_stillDepth);
    _stillTarget = nullptr;
    _stillColor = nullptr;
    _stillDepth = nullptr;
}

/// Renders the view once into its own render target (`renderStandaloneView`), so a still never
/// waits on the swap-chain frame pacing that `beginFrame` applies.
- (nullable CGImageRef)copyStillWithWidth:(NSInteger)width height:(NSInteger)height error:(NSError**)error {
    Engine* engine = _shared->engine;
    if (width <= 0 || height <= 0) {
        fail(error, 4, @"Still size is empty");
        return nullptr;
    }
    if (!_stillTarget || _stillWidth != width || _stillHeight != height) {
        [self destroyStillTarget];
        _stillColor = Texture::Builder()
            .width(uint32_t(width)).height(uint32_t(height)).levels(1)
            .format(Texture::InternalFormat::RGBA8)
            .usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE | Texture::Usage::BLIT_SRC)
            .build(*engine);
        _stillDepth = Texture::Builder()
            .width(uint32_t(width)).height(uint32_t(height)).levels(1)
            .format(Texture::InternalFormat::DEPTH32F)
            .usage(Texture::Usage::DEPTH_ATTACHMENT)
            .build(*engine);
        _stillTarget = RenderTarget::Builder()
            .texture(RenderTarget::AttachmentPoint::COLOR, _stillColor)
            .texture(RenderTarget::AttachmentPoint::DEPTH, _stillDepth)
            .build(*engine);
        _stillWidth = width;
        _stillHeight = height;
    }
    [self prepareWithWidth:width height:height time:0];

    const size_t rowBytes = size_t(width) * 4;
    auto* pixels = static_cast<uint8_t*>(calloc(rowBytes * size_t(height), 1));
    _view->setRenderTarget(_stillTarget);
    _renderer->renderStandaloneView(_view);
    _renderer->readPixels(_stillTarget, 0, 0, uint32_t(width), uint32_t(height),
        backend::PixelBufferDescriptor(pixels, rowBytes * size_t(height),
            backend::PixelDataFormat::RGBA, backend::PixelDataType::UBYTE));
    _view->setRenderTarget(nullptr);
    engine->flushAndWait();

    // A standalone view ignores the renderer's clear color: composite the background here.
    if (_clear.w > 0) {
        for (size_t i = 0; i < rowBytes * size_t(height); i += 4) {
            const double keep = 1.0 - pixels[i + 3] / 255.0;
            for (int c = 0; c < 4; ++c) {
                pixels[i + c] = uint8_t(std::min(255.0, pixels[i + c] + _clear[c] * 255.0 * keep + 0.5));
            }
        }
    }

    // Metal's readPixels is already top-down, which is what CGImage wants.
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef provider = CGDataProviderCreateWithData(
        nullptr, pixels, rowBytes * size_t(height),
        [](void*, const void* data, size_t) { free(const_cast<void*>(data)); });
    CGImageRef image = CGImageCreate(
        size_t(width), size_t(height), 8, 32, rowBytes, srgb,
        CGBitmapInfo(kCGImageAlphaPremultipliedLast) | kCGBitmapByteOrderDefault,
        provider, nullptr, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(srgb);
    return image;
}

@end

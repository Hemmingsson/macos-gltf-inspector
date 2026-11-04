#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

/// Tone mappers the look can pick. Values match `RenderLook.ToneMapping` order in Swift.
typedef NS_ENUM(NSInteger, FLToneMapper) {
    FLToneMapperPBRNeutral = 0,
    FLToneMapperACES = 1,
    FLToneMapperACESLegacy = 2,
    FLToneMapperLinear = 3,
};

/// One Filament view, scene and camera over a process-wide Metal engine (gltfio ubershaders).
/// Main thread only. A live owner attaches a `CAMetalLayer` and calls `renderFrame…` from its
/// display link; a still owner never attaches one and asks for `copyStill…`.
@interface FLRenderer : NSObject

+ (nullable FLRenderer *)makeRendererWithError:(NSError **)error NS_SWIFT_NAME(make());
- (instancetype)init NS_UNAVAILABLE;

/// Parses the file and uploads its buffers and textures. Replaces the previous model.
- (BOOL)loadModelAtPath:(NSString *)path error:(NSError **)error;
@property (nonatomic, readonly) BOOL hasModel;
/// World-space box of the loaded model (zeros without one).
@property (nonatomic, readonly) simd_float3 boundsMin;
@property (nonatomic, readonly) simd_float3 boundsMax;
@property (nonatomic, readonly) NSInteger renderableCount;
@property (nonatomic, readonly) NSInteger materialVariantCount;

// MARK: Look

/// Equirectangular `.hdr`; prefiltered once per path per process. Nil removes the IBL.
- (BOOL)setEnvironmentPath:(nullable NSString *)path error:(NSError **)error;
- (void)setEnvironmentIntensity:(float)intensity yawDegrees:(float)yaw;
/// Linear multiplier (2^EV).
- (void)setExposure:(float)multiplier;
- (void)setToneMapper:(FLToneMapper)toneMapper;
/// Straight (not premultiplied) sRGB color behind the model.
- (void)setBackgroundRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha;
/// -1 restores the file default.
- (void)applyMaterialVariant:(NSInteger)index;
@property (nonatomic) BOOL playsAnimation;

// MARK: Camera

- (void)lookFromEye:(simd_double3)eye target:(simd_double3)target;
- (void)setPerspectiveFieldOfView:(double)degrees near:(double)near far:(double)far;
/// `height` is the visible world-space height.
- (void)setOrthographicHeight:(double)height near:(double)near far:(double)far;

// MARK: Live

- (void)attachLayer:(CAMetalLayer *)layer;
- (void)detachLayer;
/// Renders one frame into the attached layer. `time` drives the first animation.
- (void)renderFrameWithWidth:(NSInteger)width height:(NSInteger)height time:(double)time;

// MARK: Still

/// One frame offscreen, read back as premultiplied RGBA8 sRGB.
- (nullable CGImageRef)copyStillWithWidth:(NSInteger)width
                                   height:(NSInteger)height
                                    error:(NSError **)error CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END

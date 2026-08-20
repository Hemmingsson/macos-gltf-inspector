> Read this when: implementing AsyncImage, downsampling, image memory, or SF Symbols.

# Image Optimization

**Contents**
- [AsyncImage](#asyncimage)
- [Downsampling](#downsampling)
- [Memory](#memory)
- [SF Symbols](#sf-symbols)

## AsyncImage

Handle all phases:

```swift
AsyncImage(url: imageURL) { phase in
    switch phase {
    case .empty: ProgressView()
    case .success(let image):
        image.resizable().aspectRatio(contentMode: .fit)
    case .failure:
        Image(systemName: "photo").foregroundStyle(.secondary)
    @unknown default: EmptyView()
    }
}
.frame(width: 200, height: 200)
```

## Downsampling

Optional when you see `UIImage(data:)` in lists/grids at display sizes much smaller than source. Decode off-main via `CGImageSourceCreateThumbnailAtIndex`:

- Source options: `kCGImageSourceShouldCache: false` (no full-res cache).
- Thumbnail: `CreateThumbnailFromImageAlways`, `CreateThumbnailWithTransform`, `ShouldCacheImmediately`, `ThumbnailMaxPixelSize` = `max(w,h) * scale`.

```swift
actor ImageProcessor {
    func downsample(data: Data, targetSize: CGSize) -> UIImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        // … CGImageSource thumbnail at maxPixel = max(w,h)*scale …
    }
}
```

Don't auto-apply — suggest for scroll/grid hotspots only.

## Memory

`UIImage(named:)` hits system cache → spikes in galleries. One-shots: `UIImage(contentsOfFile:)`. Bound processed images with `NSCache` + `countLimit`.

## SF Symbols

```swift
Image(systemName: "star.fill")
    .symbolRenderingMode(.multicolor)  // hierarchical / palette / monochrome
Image(systemName: "antenna.radiowaves.left.and.right")
    .symbolEffect(.variableColor)      // iOS 17+
```

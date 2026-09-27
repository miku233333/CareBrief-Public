import CareBriefAppSupport
import Foundation
import ImageIO
import UIKit
import Vision

enum DocumentImportError: Error {
  case unreadableImage
  case imageTooLarge
  case unsupportedRecognitionLanguages
  case noRecognizedText
  case recognitionFailed
  case scannerFailed

  var userMessage: String {
    switch self {
    case .unreadableImage:
      return "CareBrief could not open that image. Try another photo."
    case .imageTooLarge:
      return "That image is too large to process safely. Choose a standard photo under 50 MB."
    case .unsupportedRecognitionLanguages:
      return "Traditional Chinese and English text recognition is unavailable on this device."
    case .noRecognizedText:
      return "CareBrief could not find readable text in that image."
    case .recognitionFailed:
      return "Text recognition did not finish. Try again with a clearer image."
    case .scannerFailed:
      return "The document scanner did not finish. Try again or choose a photo."
    }
  }
}

struct VisionImagePage: @unchecked Sendable {
  private static let maximumEncodedByteCount = 50 * 1_024 * 1_024
  private static let maximumPixelDimension = 3_000

  let image: CGImage
  let orientation: CGImagePropertyOrientation

  static func prepare(data: Data) async throws -> VisionImagePage {
    let preparationTask = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      let page = try VisionImagePage(data: data)
      try Task.checkCancellation()
      return page
    }

    return try await withTaskCancellationHandler {
      try await preparationTask.value
    } onCancel: {
      preparationTask.cancel()
    }
  }

  init(data: Data) throws {
    guard data.count <= Self.maximumEncodedByteCount else {
      throw DocumentImportError.imageTooLarge
    }

    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
      throw DocumentImportError.unreadableImage
    }

    let thumbnailOptions =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelDimension,
        kCGImageSourceShouldCacheImmediately: true,
      ] as CFDictionary
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      throw DocumentImportError.unreadableImage
    }

    self.image = thumbnail
    self.orientation = .up
  }

  fileprivate init?(source: VisionImageSource) {
    guard let resizedImage = Self.downsampleIfNeeded(source.image) else { return nil }
    self.image = resizedImage
    self.orientation = source.orientation
  }

  private static func downsampleIfNeeded(_ image: CGImage) -> CGImage? {
    let longestDimension = max(image.width, image.height)
    guard longestDimension > maximumPixelDimension else { return image }

    let scale = Double(maximumPixelDimension) / Double(longestDimension)
    let targetWidth = max(1, Int((Double(image.width) * scale).rounded()))
    let targetHeight = max(1, Int((Double(image.height) * scale).rounded()))
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo =
      CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    guard
      let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    else {
      return nil
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    return context.makeImage()
  }
}

struct VisionImageSource: @unchecked Sendable {
  let image: CGImage
  let orientation: CGImagePropertyOrientation

  init?(uiImage: UIImage) {
    guard let image = uiImage.cgImage else { return nil }
    self.image = image
    self.orientation = uiImage.imageOrientation.cgImagePropertyOrientation
  }

  func preparePage() async throws -> VisionImagePage {
    let preparationTask = Task.detached(priority: .userInitiated) { [self] in
      try Task.checkCancellation()
      guard let page = VisionImagePage(source: self) else {
        throw DocumentImportError.unreadableImage
      }
      try Task.checkCancellation()
      return page
    }

    return try await withTaskCancellationHandler {
      try await preparationTask.value
    } onCancel: {
      preparationTask.cancel()
    }
  }
}

struct VisionTextRecognizer: Sendable {
  private static let preferredLanguages = ["zh-Hant", "en-US"]

  func recognize(page: VisionImagePage, pageIndex: Int) async throws -> [OCRTextFragment] {
    try Task.checkCancellation()

    let request = VNRecognizeTextRequest()
    request.revision = VNRecognizeTextRequestRevision3
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let supportedLanguages = try request.supportedRecognitionLanguages()
    let recognitionLanguages = Self.preferredLanguages.filter(supportedLanguages.contains)
    guard !recognitionLanguages.isEmpty else {
      throw DocumentImportError.unsupportedRecognitionLanguages
    }
    request.recognitionLanguages = recognitionLanguages

    let requestBox = VisionRequestBox(request: request)
    do {
      let fragments = try await withTaskCancellationHandler {
        try await Task.detached(priority: .userInitiated) {
          let request = requestBox.request
          let handler = VNImageRequestHandler(
            cgImage: page.image,
            orientation: page.orientation
          )
          try handler.perform([request])

          return (request.results ?? []).compactMap { observation -> OCRTextFragment? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            guard
              let normalizedBox = OCRNormalizedRect(
                x: Double(box.minX),
                y: Double(box.minY),
                width: Double(box.width),
                height: Double(box.height)
              )
            else {
              return nil
            }

            return OCRTextFragment(
              pageIndex: pageIndex,
              text: candidate.string,
              boundingBox: normalizedBox
            )
          }
        }.value
      } onCancel: {
        requestBox.cancel()
      }

      try Task.checkCancellation()
      return fragments
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as DocumentImportError {
      throw error
    } catch {
      if Task.isCancelled {
        throw CancellationError()
      }
      throw DocumentImportError.recognitionFailed
    }
  }
}

private final class VisionRequestBox: @unchecked Sendable {
  let request: VNRecognizeTextRequest

  init(request: VNRecognizeTextRequest) {
    self.request = request
  }

  func cancel() {
    request.cancel()
  }
}

extension UIImage.Orientation {
  fileprivate var cgImagePropertyOrientation: CGImagePropertyOrientation {
    switch self {
    case .up:
      return .up
    case .upMirrored:
      return .upMirrored
    case .down:
      return .down
    case .downMirrored:
      return .downMirrored
    case .left:
      return .left
    case .leftMirrored:
      return .leftMirrored
    case .right:
      return .right
    case .rightMirrored:
      return .rightMirrored
    @unknown default:
      return .up
    }
  }
}

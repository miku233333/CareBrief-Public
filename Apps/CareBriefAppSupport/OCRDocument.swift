import CareBriefCore
import Foundation

public struct OCRNormalizedRect: Equatable, Hashable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public var maxX: Double { x + width }
  public var maxY: Double { y + height }

  public init?(x: Double, y: Double, width: Double, height: Double) {
    let values = [x, y, width, height]
    guard values.allSatisfy(\.isFinite),
      x >= 0,
      y >= 0,
      width > 0,
      height > 0,
      x + width <= 1,
      y + height <= 1
    else {
      return nil
    }

    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public struct OCRTextFragment: Equatable, Sendable {
  public let pageIndex: Int
  public let text: String
  public let boundingBox: OCRNormalizedRect

  public init?(pageIndex: Int, text: String, boundingBox: OCRNormalizedRect) {
    guard pageIndex >= 0,
      text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
    else {
      return nil
    }

    self.pageIndex = pageIndex
    self.text = text
    self.boundingBox = boundingBox
  }
}

public struct OCRDocumentFragment: Equatable, Sendable {
  public let pageIndex: Int
  public let text: String
  public let boundingBox: OCRNormalizedRect
  public let range: UTF16TextRange
}

public struct OCRDocument: Equatable, Sendable {
  public let text: String
  public let fragments: [OCRDocumentFragment]
  public let sourcePageCount: Int
  public let pagesWithoutText: [Int]

  public var hasIncompletePages: Bool {
    !pagesWithoutText.isEmpty
  }
}

public enum OCRDocumentAssembler {
  public static func assemble(
    _ fragments: [OCRTextFragment],
    sourcePageCount: Int? = nil
  ) -> OCRDocument {
    var text = ""
    var assembledFragments: [OCRDocumentFragment] = []
    let orderedFragments = fragments.enumerated().sorted { lhs, rhs in
      if lhs.element.pageIndex != rhs.element.pageIndex {
        return lhs.element.pageIndex < rhs.element.pageIndex
      }
      if lhs.element.boundingBox.maxY != rhs.element.boundingBox.maxY {
        return lhs.element.boundingBox.maxY > rhs.element.boundingBox.maxY
      }
      if lhs.element.boundingBox.x != rhs.element.boundingBox.x {
        return lhs.element.boundingBox.x < rhs.element.boundingBox.x
      }
      return lhs.offset < rhs.offset
    }

    for (_, fragment) in orderedFragments {
      if let previousFragment = assembledFragments.last {
        text.append(previousFragment.pageIndex == fragment.pageIndex ? "\n" : "\n\n")
      }

      let location = (text as NSString).length
      text.append(fragment.text)
      guard
        let range = UTF16TextRange(
          location: location,
          length: (fragment.text as NSString).length
        )
      else {
        continue
      }

      assembledFragments.append(
        OCRDocumentFragment(
          pageIndex: fragment.pageIndex,
          text: fragment.text,
          boundingBox: fragment.boundingBox,
          range: range
        )
      )
    }

    let inferredPageCount = (assembledFragments.map(\.pageIndex).max() ?? -1) + 1
    let resolvedPageCount = max(sourcePageCount ?? inferredPageCount, inferredPageCount)
    let pagesWithText = Set(assembledFragments.map(\.pageIndex))
    let pagesWithoutText = (0..<resolvedPageCount).filter { !pagesWithText.contains($0) }

    return OCRDocument(
      text: text,
      fragments: assembledFragments,
      sourcePageCount: resolvedPageCount,
      pagesWithoutText: pagesWithoutText
    )
  }
}

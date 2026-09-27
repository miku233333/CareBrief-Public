import Foundation

public struct DocumentImportState: Equatable, Sendable {
  public enum Status: Equatable, Sendable {
    case idle
    case processing
    case failed(message: String)
  }

  public private(set) var status: Status
  public private(set) var latestDocument: OCRDocument?

  private var activeRequestID: UUID?

  public init() {
    self.status = .idle
    self.latestDocument = nil
    self.activeRequestID = nil
  }

  @discardableResult
  public mutating func begin(requestID: UUID = UUID()) -> UUID {
    activeRequestID = requestID
    status = .processing
    return requestID
  }

  @discardableResult
  public mutating func complete(_ document: OCRDocument, for requestID: UUID) -> Bool {
    guard activeRequestID == requestID else { return false }

    activeRequestID = nil
    status = .idle
    latestDocument = document
    return true
  }

  public mutating func cancel() {
    activeRequestID = nil
    status = .idle
  }

  @discardableResult
  public mutating func fail(userMessage: String, for requestID: UUID) -> Bool {
    guard activeRequestID == requestID else { return false }

    activeRequestID = nil
    status = .failed(message: userMessage)
    return true
  }

  public mutating func reset() {
    self = DocumentImportState()
  }
}

import SwiftUI
import VisionKit

enum DocumentScannerResult {
  case scanned(VNDocumentCameraScan)
  case cancelled
  case failed
}

struct DocumentScannerView: UIViewControllerRepresentable {
  let onResult: (DocumentScannerResult) -> Void

  @MainActor static var isSupported: Bool {
    VNDocumentCameraViewController.isSupported
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onResult: onResult)
  }

  func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
    let controller = VNDocumentCameraViewController()
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(
    _ uiViewController: VNDocumentCameraViewController,
    context: Context
  ) {}

  final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    private let onResult: (DocumentScannerResult) -> Void

    init(onResult: @escaping (DocumentScannerResult) -> Void) {
      self.onResult = onResult
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFinishWith scan: VNDocumentCameraScan
    ) {
      _ = controller
      onResult(.scanned(scan))
    }

    func documentCameraViewControllerDidCancel(
      _ controller: VNDocumentCameraViewController
    ) {
      _ = controller
      onResult(.cancelled)
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFailWithError error: Error
    ) {
      _ = controller
      _ = error
      onResult(.failed)
    }
  }
}

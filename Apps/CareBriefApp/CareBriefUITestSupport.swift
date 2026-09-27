#if DEBUG
  import CareBriefAppSupport
  import Foundation

  @MainActor
  enum CareBriefUITestSupport {
    static let launchArgument = "--carebrief-ui-testing"
    static private(set) var isSyntheticExporterActive = false

    private enum EnvironmentKey {
      static let onboardingCompleted = "CAREBRIEF_UI_TEST_ONBOARDING_COMPLETED"
      static let language = "CAREBRIEF_UI_TEST_LANGUAGE"
      static let easyRead = "CAREBRIEF_UI_TEST_EASY_READ"
    }

    static func makeViewModelIfRequested(
      processInfo: ProcessInfo = .processInfo,
      defaults: UserDefaults = .standard
    ) -> CareBriefViewModel? {
      guard processInfo.arguments.contains(launchArgument) else {
        isSyntheticExporterActive = false
        return nil
      }

      configurePreferences(
        environment: processInfo.environment,
        defaults: defaults
      )
      isSyntheticExporterActive = true
      return CareBriefViewModel(
        sampleText: "您需於 2026 年 8 月 15 日上午 9 時到示範醫院覆診。",
        exporter: CareBriefSyntheticUITestExporter()
      )
    }

    private static func configurePreferences(
      environment: [String: String],
      defaults: UserDefaults
    ) {
      let preferenceKeys = [
        CareBriefOnboardingPreferences.storageKey,
        CareBriefLanguagePreference.storageKey,
        CareBriefReadability.storageKey,
      ]
      for key in preferenceKeys {
        defaults.removeObject(forKey: key)
      }

      let onboardingCompleted = boolean(
        environment[EnvironmentKey.onboardingCompleted],
        fallback: CareBriefOnboardingPreferences.defaultIsCompleted
      )
      let languagePreference =
        environment[EnvironmentKey.language]
        .flatMap(CareBriefLanguagePreference.init(rawValue:))
        ?? CareBriefLanguagePreference.defaultPreference
      let easyRead = boolean(
        environment[EnvironmentKey.easyRead],
        fallback: CareBriefReadability.defaultIsEasyReadEnabled
      )

      defaults.set(onboardingCompleted, forKey: CareBriefOnboardingPreferences.storageKey)
      defaults.set(languagePreference.rawValue, forKey: CareBriefLanguagePreference.storageKey)
      defaults.set(easyRead, forKey: CareBriefReadability.storageKey)
    }

    private static func boolean(_ value: String?, fallback: Bool) -> Bool {
      switch value?.lowercased() {
      case "1", "true", "yes":
        return true
      case "0", "false", "no":
        return false
      default:
        return fallback
      }
    }
  }

  @MainActor
  private final class CareBriefSyntheticUITestExporter: ActionExporting {
    private var createdMarkers: Set<String> = []
    private var markersByIdentifier: [String: String] = [:]
    private var exportCallCount: UInt64 = 0

    func export(_ requests: [ActionExportRequest]) async -> ActionExportBatchResult {
      let operationID = nextOperationID()
      let results = requests.map { request in
        let marker = markerString(for: request)
        guard createdMarkers.insert(marker).inserted else {
          return ActionExportItemResult(actionID: request.actionID, outcome: .alreadyAdded)
        }

        let identifier = "carebrief-ui-test-\(CareBriefSHA256.hexDigest(Data(marker.utf8)))"
        markersByIdentifier[identifier] = marker
        let receipt = ExportReceiptItem(
          actionID: request.actionID,
          destination: request.destination,
          calendarItemIdentifier: identifier,
          markerURLString: marker,
          dateTime: request.dateTime
        )
        return ActionExportItemResult(actionID: request.actionID, outcome: .created(receipt))
      }
      return ActionExportBatchResult(operationID: operationID, results: results)
    }

    func undo(_ receipt: ExportReceipt) async -> ActionUndoBatchResult {
      let results = receipt.items.map { item in
        guard let identifier = item.calendarItemIdentifier,
          let marker = markersByIdentifier.removeValue(forKey: identifier),
          createdMarkers.remove(marker) != nil
        else {
          return ActionUndoItemResult(actionID: item.actionID, outcome: .alreadyRemoved)
        }
        return ActionUndoItemResult(actionID: item.actionID, outcome: .removed)
      }
      return ActionUndoBatchResult(operationID: receipt.operationID, results: results)
    }

    private func markerString(for request: ActionExportRequest) -> String {
      CareBriefSHA256.markerURL(for: request)?.absoluteString
        ?? "carebrief://export/v1/\(request.destination.rawValue)/invalid"
    }

    private func nextOperationID() -> UUID {
      exportCallCount &+= 1
      let call = exportCallCount
      return UUID(
        uuid: (
          0x43, 0x42, 0x55, 0x49, 0x54, 0x45, 0x53, 0x54,
          UInt8(truncatingIfNeeded: call >> 56),
          UInt8(truncatingIfNeeded: call >> 48),
          UInt8(truncatingIfNeeded: call >> 40),
          UInt8(truncatingIfNeeded: call >> 32),
          UInt8(truncatingIfNeeded: call >> 24),
          UInt8(truncatingIfNeeded: call >> 16),
          UInt8(truncatingIfNeeded: call >> 8),
          UInt8(truncatingIfNeeded: call)
        )
      )
    }
  }
#endif

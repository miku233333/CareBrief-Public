import CareBriefAppSupport
import CareBriefCore
import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct ContentView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var viewModel: CareBriefViewModel
  @Binding private var easyReadMode: Bool
  @Binding private var languagePreference: CareBriefLanguagePreference
  @State private var isDocumentEditorFocused = false
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var isShowingScanner = false
  @State private var selectedDraft: ActionDraft?
  @State private var selectedEvidenceAction: ActionCard?
  @State private var isShowingExportPreview = false
  @State private var isShowingReadabilitySettings = false
  @State private var isSourceTextExpanded = false
  @State private var isPrivacyExpanded = false

  private let onReplayOnboarding: () -> Void

  init(
    viewModel: CareBriefViewModel,
    easyReadMode: Binding<Bool>,
    languagePreference: Binding<CareBriefLanguagePreference>,
    onReplayOnboarding: @escaping () -> Void = {}
  ) {
    self.viewModel = viewModel
    _easyReadMode = easyReadMode
    _languagePreference = languagePreference
    self.onReplayOnboarding = onReplayOnboarding
  }

  var body: some View {
    NavigationStack {
      List {
        documentInputSection

        if viewModel.hasExtracted && !viewModel.isImporting {
          reviewProgressSection
          warningsSection
          actionsSections
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("CareBrief")
      .toolbar {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
          Button {
            isShowingReadabilitySettings = true
          } label: {
            Text("Aa")
              .font(.body.weight(.semibold))
              .frame(minWidth: 44, minHeight: 44)
              .contentShape(Rectangle())
          }
          .accessibilityLabel(localized("顯示設定", "Display settings"))
          .accessibilityIdentifier("carebrief.readabilitySettings")

          Button(action: onReplayOnboarding) {
            Image(systemName: "questionmark.circle")
              .frame(minWidth: 44, minHeight: 44)
              .contentShape(Rectangle())
          }
          .accessibilityLabel(localized("使用引導", "Guide"))
          .accessibilityIdentifier("carebrief.replayOnboarding")
        }

        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(localized("完成", "Done")) {
            isDocumentEditorFocused = false
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if shouldShowPreviewBar {
          exportPreviewBar
        }
      }
      .sheet(isPresented: $isShowingReadabilitySettings) {
        CareBriefReadabilitySettingsView(
          easyReadMode: $easyReadMode,
          languagePreference: $languagePreference
        )
        .presentationDetents([.medium])
      }
      .sheet(isPresented: $isShowingScanner) {
        DocumentScannerView { result in
          isShowingScanner = false
          switch result {
          case .scanned(let scan):
            viewModel.importScan(scan)
          case .cancelled:
            break
          case .failed:
            viewModel.reportScannerFailure()
          }
        }
      }
      .sheet(item: $selectedDraft) { draft in
        ActionDraftEditorView(
          draft: draft,
          category: viewModel.actions.first { $0.id == draft.sourceActionID }?.category,
          appLanguage: appLanguage
        ) { updatedDraft in
          viewModel.updateDraft(updatedDraft)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
      .sheet(item: $selectedEvidenceAction) { action in
        NavigationStack {
          EvidenceDetailView(
            evidence: action.evidence,
            sourceDocument: viewModel.reviewState.sourceDocument
          )
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button(localized("完成", "Done")) { selectedEvidenceAction = nil }
                .tint(.primary)
                .accessibilityIdentifier("carebrief.evidenceDone")
            }
          }
        }
        .presentationDetents([.large])
      }
      .sheet(isPresented: $isShowingExportPreview) {
        ActionExportPreviewView(viewModel: viewModel)
          .presentationDetents([.large])
          .interactiveDismissDisabled(viewModel.isExporting || viewModel.isUndoing)
      }
      .onChange(of: selectedPhotoItem) { item in
        guard let item else { return }
        selectedPhotoItem = nil
        isDocumentEditorFocused = false
        viewModel.importPhoto(item)
      }
      .onChange(of: viewModel.acceptedImportRevision) { revision in
        if revision > 0 {
          isSourceTextExpanded = true
        }
      }
      .onChange(of: easyReadMode) { isEasyRead in
        isPrivacyExpanded = !isEasyRead
      }
      .onAppear {
        isPrivacyExpanded = !easyReadMode
      }
    }
    .environment(\.careBriefEasyReadMode, easyReadMode)
    .environment(\.careBriefAppLanguage, appLanguage)
  }

  private var documentInputSection: some View {
    Section {
      photoPicker
      if DocumentScannerView.isSupported {
        scannerButton
      } else {
        Label(scannerUnavailableMessage.text(for: appLanguage), systemImage: "camera.fill")
          .font(.caption)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("carebrief.documentScannerUnavailable")
      }
      importStatus

      DisclosureGroup(isExpanded: $isSourceTextExpanded) {
        sourceTextEditor
        sourceTextActions

        Button {
          isDocumentEditorFocused = false
          viewModel.extract()
        } label: {
          Label {
            Text(
              easyReadMode
                ? localized("找出行動", "Find actions")
                : localized("抽取行動", "Extract actions")
            )
            .font(.body)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: "sparkles")
          }
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, minHeight: 44)
          .contentShape(Rectangle())
          .accessibilityIdentifier("carebrief.extractLabel")
        }
        .buttonStyle(.borderedProminent)
        .tint(.primary)
        .disabled(!viewModel.canExtract)
        .accessibilityIdentifier("carebrief.extract")
      } label: {
        Label {
          Text(localized("原文文字", "Source text"))
            .font(.body)
            .foregroundStyle(Color(uiColor: .label))
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "doc.text")
        }
        .accessibilityIdentifier("carebrief.sourceDisclosureLabel")
      }

      DisclosureGroup(isExpanded: $isPrivacyExpanded) {
        BilingualLabel(
          CareBriefReadability.documentPrivacyCopy(isEasyRead: easyReadMode),
          style: .explanation
        )
      } label: {
        Label {
          Text(localized("私隱說明", "Privacy"))
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "lock.shield")
        }
        .accessibilityIdentifier("carebrief.privacyDisclosureLabel")
      }
    } header: {
      Text(localized("加入文件", "Add document"))
        .foregroundStyle(Color(uiColor: .label))
    } footer: {
      Text(
        easyReadMode
          ? localized("相片及文字只在裝置上處理。", "Photos and text stay on this device.")
          : localized(
            "可選相片、在支援裝置掃描或手動輸入；OCR 只在裝置上執行。",
            "Choose a photo, scan on a supported device, or type text. OCR runs on device."
          )
      )
      .font(.footnote)
      .foregroundStyle(.primary)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("carebrief.documentPrivacyFooter")
    }
  }

  private var photoPicker: some View {
    let title = localized("選相片", "Choose photo")
    let hint = localized("選擇一張圖片，在裝置上辨識文字", "Choose one image for on-device OCR")
    return PhotosPicker(
      selection: $selectedPhotoItem,
      matching: .images,
      preferredItemEncoding: .current
    ) {
      HStack {
        Label(title, systemImage: "photo.on.rectangle")
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("carebrief.photoPickerLabel")
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isImporting)
    .accessibilityIdentifier("carebrief.photosPicker")
    .accessibilityHint(hint)
  }

  private var scannerButton: some View {
    let title = localized("掃描文件", "Scan document")
    return Button {
      isDocumentEditorFocused = false
      isShowingScanner = true
    } label: {
      HStack {
        Label(title, systemImage: "doc.viewfinder")
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isImporting)
    .accessibilityIdentifier("carebrief.documentScanner")
  }

  private var scannerUnavailableMessage: BilingualCopy {
    #if targetEnvironment(simulator)
      BilingualCopy(
        primary: "Simulator 不支援掃描，請選相片。",
        secondary: "Scanning is unavailable in Simulator. Choose a photo."
      )
    #else
      BilingualCopy(
        primary: "此裝置不支援文件掃描，仍可選相片。",
        secondary: "Document scanning is unavailable here. You can still choose a photo."
      )
    #endif
  }

  @ViewBuilder
  private var importStatus: some View {
    if viewModel.isImporting {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 10) {
          ProgressView()
            .accessibilityHidden(true)
          BilingualLabel(
            BilingualCopy(
              primary: "正在裝置上辨識文字…",
              secondary: "Recognizing text on this device…"
            ),
            style: .explanation
          )
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("carebrief.importStatus")

        Button(localized("取消", "Cancel"), role: .cancel) {
          viewModel.cancelImport()
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("carebrief.importCancel")
      }
    } else if let errorMessage = viewModel.importErrorMessage {
      Label {
        Text(verbatim: errorMessage)
          .font(.subheadline)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
      }
      .foregroundStyle(.red)
      .accessibilityIdentifier("carebrief.importStatus")
    } else if let summaryMessage = viewModel.importSummaryMessage {
      VStack(alignment: .leading, spacing: 6) {
        Label {
          Text(verbatim: summaryMessage)
            .font(.subheadline)
        } icon: {
          Image(systemName: "checkmark.circle.fill")
        }
        .foregroundStyle(.secondary)

        if let coverageWarning = viewModel.importCoverageWarningMessage {
          Label {
            Text(verbatim: coverageWarning)
              .font(.subheadline)
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
          }
          .foregroundStyle(.orange)
        }
      }
      .accessibilityIdentifier("carebrief.importStatus")
    }
  }

  private var sourceTextEditor: some View {
    ZStack(alignment: .topLeading) {
      if viewModel.inputText.isEmpty {
        Text(localized("貼上醫院或政府文件文字…", "Paste document text…"))
          .font(.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 5)
          .padding(.vertical, 8)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
          .accessibilityIdentifier("carebrief.sourceTextPlaceholder")
      }

      CareBriefDocumentTextEditor(
        text: Binding(
          get: { viewModel.inputText },
          set: { viewModel.updateInput($0) }
        ),
        isEditable: !viewModel.isImporting,
        isFocused: Binding(
          get: { isDocumentEditorFocused },
          set: { isDocumentEditorFocused = $0 }
        ),
        accessibilityLabel: localized("文件原文", "Document text"),
        accessibilityHint: localized(
          "抽取行動前先核對或修改文字",
          "Review or edit before extraction"
        )
      )
      .frame(minHeight: 150, alignment: .topLeading)
      .accessibilityIdentifier("carebrief.sourceTextEditor")
    }
    .padding(6)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private var sourceTextActions: some View {
    Group {
      if CareBriefAdaptiveLayout.usesStackedActionControls(at: dynamicTypeSize) {
        VStack(alignment: .leading, spacing: 8) {
          sampleButton
          clearButton
        }
      } else {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) {
            sampleButton
            Spacer(minLength: 8)
            clearButton
          }
          VStack(alignment: .leading, spacing: 8) {
            sampleButton
            clearButton
          }
        }
      }
    }
  }

  private var sampleButton: some View {
    Button {
      viewModel.loadSample()
      isSourceTextExpanded = true
      isDocumentEditorFocused = false
    } label: {
      Label {
        Text(localized("載入示例", "Load sample"))
          .foregroundStyle(.primary)
      } icon: {
        Image(systemName: "doc.text")
          .foregroundStyle(.tint)
      }
        .font(.body)
        .lineLimit(nil)
        .multilineTextAlignment(.leading)
        .frame(
          maxWidth: CareBriefAdaptiveLayout.usesStackedActionControls(at: dynamicTypeSize)
            ? .infinity : nil,
          alignment: .leading
        )
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityIdentifier("carebrief.loadSampleLabel")
    }
    .buttonStyle(.plain)
    .tint(.accentColor)
    .accessibilityIdentifier("carebrief.loadSample")
  }

  private var clearButton: some View {
    Button(role: .destructive) {
      viewModel.clear()
      isDocumentEditorFocused = false
    } label: {
      Label {
        Text(localized("清除", "Clear"))
          .foregroundStyle(.primary)
      } icon: {
        Image(systemName: "trash")
          .foregroundStyle(.red)
      }
        .font(.body)
        .lineLimit(nil)
        .multilineTextAlignment(.leading)
        .frame(
          maxWidth: CareBriefAdaptiveLayout.usesStackedActionControls(at: dynamicTypeSize)
            ? .infinity : nil,
          alignment: .leading
        )
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityIdentifier("carebrief.clearLabel")
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("carebrief.clear")
    .disabled(
      viewModel.inputText.isEmpty
        && !viewModel.hasExtracted
        && !viewModel.isImporting
        && viewModel.importErrorMessage == nil
        && !viewModel.hasImportedDocument
    )
  }

  private var reviewProgressSection: some View {
    Section {
      HStack(alignment: .firstTextBaseline) {
        BilingualLabel(
          BilingualCopy(primary: "已核對", secondary: "Checked"),
          style: .headline
        )
        .accessibilityIdentifier("review-progress-label")
        Spacer()
        Text(
          "\(viewModel.reviewState.confirmedActionCount) / \(viewModel.reviewState.actions.count)"
        )
        .font(.headline)
        .monospacedDigit()
        .accessibilityIdentifier("review-progress-count")
      }

      ProgressView(
        value: Double(viewModel.reviewState.confirmedActionCount),
        total: Double(max(viewModel.reviewState.actions.count, 1))
      )

      if viewModel.reviewState.actionsRequiringReviewCount > 0 {
        Label(
          localized(
            "需仔細覆核 \(viewModel.reviewState.actionsRequiringReviewCount) 項",
            "\(viewModel.reviewState.actionsRequiringReviewCount) need review"
          ),
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }
    } header: {
      Text(localized("核對進度", "Review progress"))
        .foregroundStyle(Color(uiColor: .label))
    }
  }

  @ViewBuilder
  private var warningsSection: some View {
    if !viewModel.warnings.isEmpty {
      Section {
        ForEach(Array(viewModel.warnings.enumerated()), id: \.offset) { _, warning in
          VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
              Text(localized("請按原文核對", "Check against source"))
                .foregroundStyle(Color(uiColor: .label))
            }
            .font(.caption.weight(.semibold))
            .accessibilityElement(children: .combine)
            Text(
              verbatim: CareBriefGeneratedCopy.warning(
                warning,
                language: appLanguage
              )
            )
            .font(.caption)
            .foregroundStyle(Color(uiColor: .label))
          }
        }
      } header: {
        Text(localized("注意", "Warnings"))
          .foregroundStyle(Color(uiColor: .label))
      }
    }
  }

  @ViewBuilder
  private var actionsSections: some View {
    Group {
      if viewModel.actions.isEmpty {
        Section(localized("行動卡", "Action cards")) {
          EmptyStateView(
            systemImage: "doc.text.magnifyingglass",
            title: BilingualCopy(primary: "未找到支援的行動", secondary: "No supported actions found"),
            message: CareBriefReadability.noActionsCopy(isEasyRead: easyReadMode)
          )
        }
      } else {
        actionSection(
          identifier: "today",
          title: BilingualCopy(primary: "今日", secondary: "Today"),
          drafts: actionGroups.today
        )
        actionSection(
          identifier: "scheduled",
          title: BilingualCopy(primary: "已排期", secondary: "Scheduled"),
          drafts: actionGroups.scheduled
        )
        actionSection(
          identifier: "unscheduled",
          title: BilingualCopy(primary: "未排期", secondary: "Unscheduled"),
          drafts: actionGroups.unscheduled
        )
      }
    }
    .disabled(viewModel.isImporting)
  }

  private var actionGroups: ActionDraftGroups {
    ActionDraftGrouper.group(
      viewModel.reviewState.drafts,
      today: Date(),
      calendar: .autoupdatingCurrent
    )
  }

  @ViewBuilder
  private func actionSection(
    identifier: String,
    title: BilingualCopy,
    drafts: [ActionDraft]
  ) -> some View {
    if !drafts.isEmpty {
      Section {
        ForEach(drafts) { draft in
          if let action = viewModel.actions.first(where: { $0.id == draft.sourceActionID }) {
            ActionCardView(
              action: action,
              draft: draft,
              isEdited: viewModel.isDraftEdited(actionID: action.id),
              onEdit: { selectedDraft = draft },
              onViewEvidence: { selectedEvidenceAction = action },
              isConfirmed: Binding(
                get: { viewModel.isConfirmed(actionID: action.id) },
                set: { viewModel.setConfirmation($0, forActionID: action.id) }
              )
            )
          }
        }
      } header: {
        Text(title.text(for: appLanguage))
          .font(.headline)
          .foregroundStyle(Color(uiColor: .label))
          .textCase(nil)
          .accessibilityHeading(.h2)
          .accessibilityIdentifier("action-section-\(identifier)")
      }
    }
  }

  private var shouldShowPreviewBar: Bool {
    (viewModel.hasExtracted && !viewModel.actions.isEmpty) || viewModel.latestExportReceipt != nil
  }

  private var exportPreviewBar: some View {
    VStack(spacing: 0) {
      Divider()
      Button {
        viewModel.prepareExportPreview()
        isShowingExportPreview = true
      } label: {
        Label(
          localized(
            "預覽 \(viewModel.reviewState.confirmedActionCount) 個行動",
            "Preview \(viewModel.reviewState.confirmedActionCount) actions"
          ),
          systemImage: "calendar.badge.plus"
        )
        .foregroundStyle(Color(uiColor: .systemBackground))
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityIdentifier("export.previewLabel")
      }
      .buttonStyle(.borderedProminent)
      .tint(Color(uiColor: .label))
      .padding(.horizontal)
      .padding(.vertical, 8)
      .disabled(
        viewModel.reviewState.confirmedActionCount == 0
          && viewModel.latestExportReceipt == nil
      )
      .accessibilityIdentifier("export.preview")
    }
    .background(.regularMaterial)
  }

  private func localized(_ traditionalChinese: String, _ english: String) -> String {
    BilingualCopy(primary: traditionalChinese, secondary: english).text(for: appLanguage)
  }

  private var appLanguage: CareBriefAppLanguage {
    languagePreference.resolvedLanguage
  }
}

private struct CareBriefDocumentTextEditor: UIViewRepresentable {
  @Binding var text: String
  let isEditable: Bool
  @Binding var isFocused: Bool
  let accessibilityLabel: String
  let accessibilityHint: String

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.delegate = context.coordinator
    textView.backgroundColor = .clear
    textView.font = .preferredFont(forTextStyle: .body)
    textView.adjustsFontForContentSizeCategory = true
    textView.isScrollEnabled = true
    textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.parent = self
    if textView.text != text {
      textView.text = text
    }
    textView.isEditable = isEditable
    textView.accessibilityLabel = accessibilityLabel
    textView.accessibilityHint = accessibilityHint

    if isFocused, !textView.isFirstResponder {
      textView.becomeFirstResponder()
    } else if !isFocused, textView.isFirstResponder {
      textView.resignFirstResponder()
    }
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: CareBriefDocumentTextEditor

    init(parent: CareBriefDocumentTextEditor) {
      self.parent = parent
    }

    func textViewDidChange(_ textView: UITextView) {
      parent.text = textView.text
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
      parent.isFocused = true
    }

    func textViewDidEndEditing(_ textView: UITextView) {
      parent.isFocused = false
    }
  }
}

struct CareBriefEasyReadModeKey: EnvironmentKey {
  static let defaultValue = true
}

extension EnvironmentValues {
  var careBriefEasyReadMode: Bool {
    get { self[CareBriefEasyReadModeKey.self] }
    set { self[CareBriefEasyReadModeKey.self] = newValue }
  }
}

private struct CareBriefReadabilitySettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var easyReadMode: Bool
  @Binding var languagePreference: CareBriefLanguagePreference

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker(
            BilingualCopy(primary: "語言", secondary: "Language").text(for: appLanguage),
            selection: $languagePreference
          ) {
            ForEach(CareBriefLanguagePreference.allCases, id: \.self) { preference in
              Text(preference.displayCopy.text(for: appLanguage)).tag(preference)
            }
          }
          .pickerStyle(.menu)
          .frame(minHeight: 44)
          .accessibilityIdentifier("carebrief.appLanguage")
        } header: {
          Text(BilingualCopy(primary: "語言", secondary: "Language").text(for: appLanguage))
        } footer: {
          Text(
            BilingualCopy(
              primary: "Apple 權限視窗會跟隨 iPhone 語言。",
              secondary: "Apple permission prompts follow the iPhone language."
            ).text(for: appLanguage)
          )
        }

        Section {
          Toggle(isOn: $easyReadMode) {
            BilingualLabel(
              BilingualCopy(primary: "易讀模式", secondary: "Easy Read"),
              style: .headline
            )
          }
          .frame(minHeight: 44)
          .accessibilityIdentifier("carebrief.easyReadMode")

          BilingualLabel(
            CareBriefReadability.modeDescriptionCopy(isEasyRead: easyReadMode),
            style: .explanation
          )
        }

        Section(BilingualCopy(primary: "字體", secondary: "Text size").text(for: appLanguage)) {
          BilingualLabel(
            BilingualCopy(
              primary: "字體大小完全跟隨 iPhone 系統設定。",
              secondary: "Text size follows your iPhone system setting."
            ),
            style: .explanation
          )
        }
      }
      .navigationTitle(BilingualCopy(primary: "顯示", secondary: "Display").text(for: appLanguage))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(BilingualCopy(primary: "完成", secondary: "Done").text(for: appLanguage)) {
            dismiss()
          }
        }
      }
    }
    .environment(\.careBriefAppLanguage, appLanguage)
  }

  private var appLanguage: CareBriefAppLanguage {
    languagePreference.resolvedLanguage
  }
}

private struct EmptyStateView: View {
  let systemImage: String
  let title: BilingualCopy
  let message: BilingualCopy

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.title2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      BilingualLabel(title, style: .headline)
        .multilineTextAlignment(.center)
      BilingualLabel(message, style: .explanation)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
  }
}

import CareBriefAppSupport
import CareBriefCore
import SwiftUI
import UIKit

struct ActionExportPreviewView: View {
  @ObservedObject var viewModel: CareBriefViewModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.careBriefEasyReadMode) private var easyReadMode
  @Environment(\.careBriefAppLanguage) private var appLanguage
  @State private var acknowledgesReviewWarnings = false
  @State private var isPrivacyDetailsExpanded = false
  @AccessibilityFocusState private var resultFocus: ResultFocus?

  var body: some View {
    NavigationStack {
      List {
        privacySection
        actionsSection
        validationSection
        resultsSection
        undoSection
      }
      .navigationTitle(localized("加入 Apple App", "Add to Apple apps"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(localized("完成", "Done")) { dismiss() }
            .tint(.primary)
            .disabled(viewModel.isExporting || viewModel.isUndoing)
            .accessibilityIdentifier("export.done")
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        addAction
      }
      .onChange(of: easyReadMode) { isEasyRead in
        isPrivacyDetailsExpanded = !isEasyRead
      }
      .onAppear {
        isPrivacyDetailsExpanded = !easyReadMode
      }
      .onChange(of: viewModel.exportResult?.operationID) { operationID in
        if operationID != nil {
          resultFocus = .exportResults
        }
      }
      .onChange(of: viewModel.undoResult?.operationID) { operationID in
        if operationID != nil {
          resultFocus = .undoResults
        }
      }
    }
  }

  private var privacySection: some View {
    Section {
      #if DEBUG
        if CareBriefUITestSupport.isSyntheticExporterActive {
          Image(systemName: "checkmark.shield")
            .foregroundStyle(.primary)
            .accessibilityLabel(
              localized("合成測試匯出器已啟用", "Synthetic test exporter active")
            )
            .accessibilityIdentifier("carebrief.syntheticExporter.active")
        }
      #endif

      Label {
        BilingualLabel(
          BilingualCopy(
            primary: "Calendar 及 Reminders 內容可能透過你的 Apple 帳戶同步。",
            secondary: "Calendar and Reminders items may sync through your Apple account."
          )
        )
        .accessibilityIdentifier("export.syncNotice")
      } icon: {
        Image(systemName: "icloud")
      }

      BilingualLabel(
        BilingualCopy(
          primary: "只會在按「加入」後，按所選目的地分別要求完整權限。",
          secondary: "Full access is requested separately by destination, only after Add."
        ),
        style: .body
      )
      .accessibilityIdentifier("export.permissionSummary")

      DisclosureGroup(isExpanded: $isPrivacyDetailsExpanded) {
        BilingualLabel(
          BilingualCopy(
            primary: easyReadMode
              ? "CareBrief 只查找自己的標記，以防重複及支援 Undo；不會展示或分析其他項目。"
              : "完整權限只用於精確查找 CareBrief 標記、防止重複、建立項目及核實本次 Undo；其他項目不會傳到畫面、分析、日誌或網路。",
            secondary: easyReadMode
              ? "CareBrief checks only its own markers for duplicates and Undo; it does not show or analyse other items."
              : "Full access is limited to exact CareBrief-marker lookup, creation, and receipt-verified Undo. Other items are not shown, analysed, logged, or uploaded."
          ),
          style: .explanation
        )
        .foregroundStyle(.secondary)
      } label: {
        Text(localized("權限及私隱詳情", "Access and privacy details"))
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("export.privacyDetailsLabel")
      }

      Toggle(
        isOn: Binding(
          get: { viewModel.exportPreview?.includeResponsiblePartyInNotes ?? false },
          set: { viewModel.setIncludeResponsiblePartyInNotes($0) }
        )
      ) {
        Text(localized("在備註加入負責人", "Add responsible person to notes"))
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("export.responsibleNotesLabel")
      }
      .disabled(viewModel.isExporting || viewModel.isUndoing)

      Text(
        verbatim: localized(
          "預設關閉；否則負責人只留在 CareBrief。",
          "Off by default; otherwise the responsible person stays only in CareBrief."
        )
      )
      .foregroundStyle(.primary)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("export.responsibleNotesExplanation")
    } header: {
      Text(localized("加入前", "Before you add"))
        .foregroundStyle(.primary)
        .accessibilityIdentifier("export.privacyHeader")
    }
  }

  @ViewBuilder
  private var actionsSection: some View {
    Section {
      if let preview = viewModel.exportPreview, !preview.items.isEmpty {
        ForEach(preview.items) { item in
          VStack(alignment: .leading, spacing: 7) {
            Text(verbatim: displayTitle(for: item))
              .font(.headline)
              .accessibilityIdentifier("export.title.\(item.actionID)")
            Text(item.category.bilingualName.text(for: appLanguage))
              .font(.caption)
              .foregroundStyle(.primary)
              .accessibilityIdentifier("export.category.\(item.actionID)")

            if let dateTime = item.draft.dateTime {
              ExportMetadataRow(
                label: localized("日期", "Date"),
                value: dateTime.localizedCareBriefDisplay(for: appLanguage),
                systemImage: "calendar",
                accessibilityIdentifier: "export.date.\(item.actionID)"
              )
            } else {
              Label(localized("未排期", "Unscheduled"), systemImage: "calendar.badge.questionmark")
                .foregroundStyle(.secondary)
            }

            if let location = item.draft.location {
              ExportMetadataRow(
                label: localized("地點", "Location"),
                value: location,
                systemImage: "mappin.and.ellipse",
                accessibilityIdentifier: "export.location.\(item.actionID)"
              )
            }

            ExportMetadataRow(
              label: localized("負責人", "Responsible"),
              value: item.draft.responsibleParty.displayCopy.text(for: appLanguage),
              systemImage: "person.crop.circle",
              accessibilityIdentifier: "export.responsible.\(item.actionID)"
            )

            Picker(
              selection: Binding(
                get: { item.destination },
                set: { viewModel.setExportDestination($0, forActionID: item.actionID) }
              )
            ) {
              ForEach(ActionExportDestination.allCases, id: \.self) { destination in
                Text(destination.displayCopy.text(for: appLanguage)).tag(destination)
              }
            } label: {
              Text(localized("目的地", "Destination"))
                .foregroundStyle(.primary)
                .accessibilityIdentifier("export.destinationLabel.\(item.actionID)")
            }
            .pickerStyle(.menu)
            .disabled(viewModel.isExporting || viewModel.isUndoing)
            .accessibilityIdentifier("export.destination.\(item.actionID)")

            DisclosureGroup {
              exportedDetails(for: item)
            } label: {
              CareBriefDynamicLabel(
                text: localized("更多資料", "Details"),
                accessibilityIdentifier: "export.detailsLabel.\(item.actionID)"
              )
            }

            DisclosureGroup {
              Text(verbatim: item.evidence.text)
                .textSelection(.enabled)
              Text("\(localized("規則", "Rule")): \(item.evidence.ruleID)")
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(
                "\(localized("可信度", "Confidence")): \(item.confidence.displayCopy.text(for: appLanguage))"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            } label: {
              CareBriefDynamicLabel(
                text: localized("原文", "Source"),
                accessibilityIdentifier: "export.sourceLabel.\(item.actionID)"
              )
            }

            if item.needsReview {
              Label(
                localized("仍需仔細核對", "Needs review remains active"),
                systemImage: "exclamationmark.triangle.fill"
              )
              .font(.caption)
              .foregroundStyle(.orange)
            }
          }
          .padding(.vertical, 3)
        }
      } else {
        BilingualLabel(
          BilingualCopy(
            primary: "請先核對至少一項行動。",
            secondary: "Check at least one action before preview."
          ),
          style: .explanation
        )
        .foregroundStyle(.secondary)
      }
    } header: {
      Text(localized("已核對行動", "Checked actions"))
        .foregroundStyle(.primary)
        .accessibilityIdentifier("export.actionsHeader")
    }
  }

  @ViewBuilder
  private var validationSection: some View {
    if let preview = viewModel.exportPreview, preview.requiresReviewAcknowledgement {
      Section(localized("最後警告", "Final warning")) {
        Toggle(
          localized("我已再核對警告及原文", "I reviewed the warning and source"),
          isOn: $acknowledgesReviewWarnings
        )
        .accessibilityIdentifier("export.reviewAcknowledgement")
      }
    }

    if !viewModel.exportValidationIssuesByActionID.isEmpty {
      Section(localized("加入前請修正", "Fix before adding")) {
        ForEach(viewModel.exportValidationIssuesByActionID.keys.sorted(), id: \.self) { id in
          VStack(alignment: .leading, spacing: 4) {
            Text(resultTitle(forActionID: id))
              .font(.headline)
            ForEach(viewModel.exportValidationIssuesByActionID[id] ?? [], id: \.self) { issue in
              Label(issue.copy.text(for: appLanguage), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var resultsSection: some View {
    if let result = viewModel.exportResult {
      Section {
        CareBriefDynamicLabel(
          text: localized("結果", "Results"),
          accessibilityIdentifier: "export.resultsHeader",
          textStyle: .headline,
          accessibilityTraits: [.staticText, .header]
        )
        .accessibilityFocused($resultFocus, equals: .exportResults)

        ForEach(result.results) { item in
          CareBriefDynamicLabel(
            text: "\(resultTitle(forActionID: item.actionID))\n"
              + "\(resultDestination(forActionID: item.actionID).displayCopy.text(for: appLanguage))\n"
              + item.outcome.copy.text(for: appLanguage),
            accessibilityIdentifier: "export.result.\(item.actionID)"
          )
        }
      }
    }

    if let undoResult = viewModel.undoResult {
      Section {
        CareBriefDynamicLabel(
          text: localized("Undo 結果", "Undo result"),
          accessibilityIdentifier: "export.undoResultsHeader",
          textStyle: .headline,
          accessibilityTraits: [.staticText, .header]
        )
        .accessibilityFocused($resultFocus, equals: .undoResults)

        ForEach(undoResult.results) { item in
          CareBriefDynamicLabel(
            text: "\(resultTitle(forActionID: item.actionID))\n"
              + item.outcome.copy.text(for: appLanguage),
            accessibilityIdentifier: "export.undoResult.\(item.actionID)"
          )
        }
      }
    }
  }

  @ViewBuilder
  private var undoSection: some View {
    if viewModel.latestExportReceipt != nil {
      Section {
        CareBriefUndoButton(
          title: viewModel.isUndoing
            ? localized("正在 Undo…", "Undoing…")
            : localized("Undo 本次加入項目", "Undo items added this session"),
          isEnabled: !viewModel.isUndoing && !viewModel.isExporting
        ) {
          Task { await viewModel.undoLatestExport() }
        }

        CareBriefDynamicLabel(
          text: localized("Undo 只在今次開啟期間有效。", "Undo works only in this app session."),
          accessibilityIdentifier: "export.undoFooter",
          textStyle: .footnote
        )
      }
    }
  }

  private var addAction: some View {
    Button {
      Task {
        await viewModel.addPreparedActions(
          acknowledgesReviewWarnings: acknowledgesReviewWarnings
        )
      }
    } label: {
      if viewModel.isExporting {
        HStack(spacing: 8) {
          ProgressView()
          Text(localized("正在加入…", "Adding…"))
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
      } else {
        Label {
          Text(localized("加入所選行動", "Add selected actions"))
            .accessibilityIdentifier("export.addLabel")
        } icon: {
          Image(systemName: "calendar.badge.plus")
        }
        .foregroundStyle(Color(uiColor: .systemBackground))
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
    }
    .buttonStyle(.borderedProminent)
    .tint(Color(uiColor: .label))
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.regularMaterial)
    .disabled(addDisabled)
    .accessibilityIdentifier("export.add")
  }

  private var addDisabled: Bool {
    guard let preview = viewModel.exportPreview else { return true }
    let hasDestination = preview.items.contains { $0.destination != .skip }
    let warningBlocked = preview.requiresReviewAcknowledgement && !acknowledgesReviewWarnings
    return !hasDestination || warningBlocked || viewModel.isExporting || viewModel.isUndoing
  }

  private func exportedDetails(for item: ActionExportPreviewItem) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      let detail = item.draft.detail.trimmingCharacters(in: .whitespacesAndNewlines)
      let evidence = item.evidence.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !detail.isEmpty, detail != item.draft.title, detail != evidence {
        Text(verbatim: detail)
      } else if !detail.isEmpty, detail == evidence {
        Text(
          localized(
            "原文詳情不會加入 Apple 備註",
            "Source detail will not be added to Apple notes"
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      if !item.draft.items.isEmpty {
        Label {
          Text(verbatim: item.draft.items.joined(separator: ", "))
        } icon: {
          Image(systemName: "bag")
        }
      }
      if let contact = item.draft.contact {
        Label {
          Text(verbatim: contact)
        } icon: {
          Image(systemName: "phone")
        }
      }
      if item.destination == .calendar, let dateTime = item.draft.dateTime {
        Text(
          dateTime.hasTime
            ? localized("Calendar 預設 60 分鐘", "Calendar defaults to 60 minutes")
            : localized("Calendar 全天行程", "Calendar all-day event")
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } else if item.destination == .reminder, item.draft.dateTime == nil {
        Text(localized("Reminder 可沒有到期日", "Reminder has no due date"))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if viewModel.exportPreview?.includeResponsiblePartyInNotes == true {
        Text(
          "\(localized("備註將包括", "Notes will include")): \(item.draft.responsibleParty.displayCopy.text(for: appLanguage))"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .font(.body)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func resultTitle(forActionID actionID: String) -> String {
    guard let item = viewModel.exportPreview?.items.first(where: { $0.actionID == actionID }) else {
      return localized("行動", "Action")
    }
    return displayTitle(for: item)
  }

  private func displayTitle(for item: ActionExportPreviewItem) -> String {
    CareBriefGeneratedCopy.actionTitle(
      category: item.category,
      draftTitle: item.draft.title,
      language: appLanguage
    )
  }

  private func resultDestination(forActionID actionID: String) -> ActionExportDestination {
    viewModel.exportPreview?.items.first(where: { $0.actionID == actionID })?.destination
      ?? .skip
  }

  private func localized(_ traditionalChinese: String, _ english: String) -> String {
    BilingualCopy(primary: traditionalChinese, secondary: english).text(for: appLanguage)
  }
}

private enum ResultFocus: Hashable {
  case exportResults
  case undoResults
}

@MainActor
private struct ExportMetadataRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let label: String
  let value: String
  let systemImage: String
  let accessibilityIdentifier: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(.primary)
        .imageScale(.small)
        .frame(minWidth: 18)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)

      Text(verbatim: value)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
    .frame(minHeight: 44, alignment: .leading)
    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
  }
}

@MainActor
private struct CareBriefUndoButton: UIViewRepresentable {
  let title: String
  let isEnabled: Bool
  let action: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  func makeUIView(context: Context) -> UIButton {
    let button = UIButton(type: .system)
    var configuration = UIButton.Configuration.plain()
    configuration.baseForegroundColor = .label
    configuration.image = UIImage(
      systemName: "arrow.uturn.backward.circle.fill"
    )?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
    configuration.imagePadding = 8
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 8,
      leading: 0,
      bottom: 8,
      trailing: 0
    )
    button.configuration = configuration
    button.contentHorizontalAlignment = .leading
    button.titleLabel?.font = .preferredFont(forTextStyle: .body)
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    button.titleLabel?.numberOfLines = 0
    button.accessibilityIdentifier = "export.undo"
    button.addTarget(
      context.coordinator, action: #selector(Coordinator.activate), for: .touchUpInside)
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    return button
  }

  func updateUIView(_ button: UIButton, context: Context) {
    context.coordinator.action = action
    var configuration = button.configuration
    configuration?.title = title
    button.configuration = configuration
    button.accessibilityLabel = title
    button.isEnabled = isEnabled
  }

  final class Coordinator: NSObject {
    var action: () -> Void

    init(action: @escaping () -> Void) {
      self.action = action
    }

    @objc func activate() {
      action()
    }
  }
}

@MainActor
private struct CareBriefDynamicLabel: UIViewRepresentable {
  let text: String
  let accessibilityIdentifier: String
  let textStyle: UIFont.TextStyle
  let accessibilityTraits: UIAccessibilityTraits

  init(
    text: String,
    accessibilityIdentifier: String,
    textStyle: UIFont.TextStyle = .body,
    accessibilityTraits: UIAccessibilityTraits = .staticText
  ) {
    self.text = text
    self.accessibilityIdentifier = accessibilityIdentifier
    self.textStyle = textStyle
    self.accessibilityTraits = accessibilityTraits
  }

  func makeUIView(context: Context) -> UILabel {
    let label = UILabel()
    label.adjustsFontForContentSizeCategory = true
    label.numberOfLines = 0
    label.textColor = .label
    label.setContentCompressionResistancePriority(.required, for: .vertical)
    return label
  }

  func updateUIView(_ label: UILabel, context: Context) {
    label.font = .preferredFont(forTextStyle: textStyle)
    label.text = text
    label.accessibilityLabel = text.replacingOccurrences(of: "\n", with: ", ")
    label.accessibilityIdentifier = accessibilityIdentifier
    label.accessibilityTraits = accessibilityTraits
  }
}

extension ActionExportDestination {
  fileprivate var displayCopy: BilingualCopy {
    switch self {
    case .skip:
      BilingualCopy(primary: "略過", secondary: "Skip")
    case .calendar:
      BilingualCopy(primary: "行事曆", secondary: "Calendar")
    case .reminder:
      BilingualCopy(primary: "提醒事項", secondary: "Reminder")
    }
  }
}

extension ActionExportValidationIssue {
  fileprivate var copy: BilingualCopy {
    switch self {
    case .emptyTitle:
      BilingualCopy(primary: "請輸入標題。", secondary: "Enter a title.")
    case .invalidResponsibleParty:
      BilingualCopy(
        primary: "請修正負責人名稱。",
        secondary: "Fix the responsible person's name."
      )
    case .ambiguousDate:
      BilingualCopy(
        primary: "請先把日期改為明確日期。",
        secondary: "Resolve the ambiguous date first."
      )
    case .calendarRequiresDate:
      BilingualCopy(primary: "Calendar 行動必須有日期。", secondary: "Calendar requires a date.")
    case .reviewAcknowledgementRequired:
      BilingualCopy(
        primary: "請再次確認需核對警告。",
        secondary: "Final warning acknowledgement is required."
      )
    }
  }
}

extension ActionExportItemOutcome {
  fileprivate var copy: BilingualCopy {
    switch self {
    case .created:
      BilingualCopy(primary: "已加入", secondary: "Added")
    case .alreadyAdded:
      BilingualCopy(
        primary: "已經加入；現有項目沒有改動。",
        secondary: "Already added; existing item unchanged."
      )
    case .skipped:
      BilingualCopy(primary: "已略過", secondary: "Skipped")
    case .failed(let failure):
      failure.copy
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .created: "checkmark.circle.fill"
    case .alreadyAdded: "equal.circle.fill"
    case .skipped: "minus.circle"
    case .failed: "exclamationmark.triangle.fill"
    }
  }

  fileprivate var tint: Color {
    switch self {
    case .created: .green
    case .alreadyAdded: .blue
    case .skipped: .secondary
    case .failed: .red
    }
  }
}

extension ActionExportFailure {
  fileprivate var copy: BilingualCopy {
    switch self {
    case .permissionDenied:
      BilingualCopy(
        primary: "權限被拒；CareBrief 草稿已保留。", secondary: "Access denied; your draft was kept.")
    case .permissionRestricted:
      BilingualCopy(primary: "此裝置限制了權限。", secondary: "Access is restricted on this device.")
    case .fullAccessRequired:
      BilingualCopy(
        primary: "防重複及 Undo 需要完整權限。",
        secondary: "Full access is required for duplicates and Undo."
      )
    case .noDefaultCalendar:
      BilingualCopy(primary: "沒有預設 Calendar。", secondary: "No default Calendar is available.")
    case .noDefaultReminderList:
      BilingualCopy(
        primary: "沒有預設 Reminders 列表。", secondary: "No default Reminders list is available.")
    case .invalidDate:
      BilingualCopy(primary: "未能安全建立日期。", secondary: "The date could not be created safely.")
    case .duplicateLookupFailed:
      BilingualCopy(
        primary: "未能安全檢查重複項目；沒有新增。",
        secondary: "Duplicates could not be checked safely; nothing was added."
      )
    case .ambiguousDuplicate:
      BilingualCopy(
        primary: "找到多個相同標記；沒有新增或刪除。",
        secondary: "Multiple exact markers found; nothing changed."
      )
    case .alreadyInProgress:
      BilingualCopy(primary: "這項行動正在加入。", secondary: "This action is already being added.")
    case .saveFailed:
      BilingualCopy(
        primary: "Apple App 未能儲存；草稿已保留。",
        secondary: "Apple apps could not save; your draft was kept."
      )
    case .itemChanged:
      BilingualCopy(primary: "項目已改動，因此沒有刪除。", secondary: "The item changed, so it was not deleted.")
    case .itemNotFound:
      BilingualCopy(
        primary: "未能核實原項目；沒有猜測或刪除其他項目。",
        secondary: "The item was not verified; nothing else was deleted."
      )
    case .invalidExporterResult:
      BilingualCopy(primary: "收到不完整結果；草稿已保留。", secondary: "Incomplete result; your draft was kept.")
    case .invalidReceipt:
      BilingualCopy(
        primary: "這張 Undo receipt 不屬於今次 App session。",
        secondary: "This Undo receipt is not valid for this session."
      )
    case .removeFailed:
      BilingualCopy(
        primary: "未能移除；你可以重試或使用 Apple App。",
        secondary: "Could not remove; retry or use the Apple app.")
    }
  }
}

extension ActionUndoItemOutcome {
  fileprivate var copy: BilingualCopy {
    switch self {
    case .removed:
      BilingualCopy(primary: "已移除", secondary: "Removed")
    case .alreadyRemoved:
      BilingualCopy(primary: "已經移除", secondary: "Already removed")
    case .failed(let failure):
      failure.copy
    }
  }
}

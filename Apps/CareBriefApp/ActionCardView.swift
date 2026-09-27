import CareBriefAppSupport
import CareBriefCore
import SwiftUI

struct ActionCardView: View {
  @Environment(\.careBriefEasyReadMode) private var easyReadMode
  @Environment(\.careBriefAppLanguage) private var appLanguage
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let action: ActionCard
  let draft: ActionDraft
  let isEdited: Bool
  let onEdit: () -> Void
  let onViewEvidence: () -> Void
  @Binding var isConfirmed: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(
        action.category.bilingualName.text(for: appLanguage),
        systemImage: action.category.systemImage
      )
      .font(.caption.weight(.semibold))
      .foregroundStyle(Color(uiColor: .label))
      .accessibilityIdentifier("action-category-\(action.id)")

      Text(
        verbatim: CareBriefGeneratedCopy.actionTitle(
          category: action.category,
          draftTitle: draft.title,
          language: appLanguage
        )
      )
      .font(.headline)
      .foregroundStyle(Color(uiColor: .label))
      .accessibilityHeading(.h3)
      .accessibilityIdentifier("action-title-\(action.id)")

      keyDetails
      statusBadges
      reviewButtons

      Toggle(isOn: $isConfirmed) {
        Text(localized("已核對", "Checked"))
          .foregroundStyle(Color(uiColor: .label))
          .accessibilityIdentifier("action-confirmation-label-\(action.id)")
      }
        .frame(minHeight: 44)
        .accessibilityIdentifier("action-confirmation-\(action.id)")
        .accessibilityHint(
          localized("只確認這一項；警告仍會保留", "Confirms this action only; warnings remain")
        )
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var keyDetails: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let dateTime = draft.dateTime {
        ActionDetailRow(
          label: dateTime.hasTime
            ? localized("日期時間", "Date and time") : localized("日期", "Date"),
          value: dateTime.localizedCareBriefDisplay(for: appLanguage),
          systemImage: "calendar",
          accessibilityIdentifier: "action-date-\(action.id)"
        )
      }

      if let location = draft.location {
        ActionDetailRow(
          label: localized("地點", "Location"),
          value: location,
          systemImage: "mappin.and.ellipse",
          accessibilityIdentifier: "action-location-\(action.id)"
        )
      }

      ActionDetailRow(
        label: localized("負責人", "Responsible"),
        value: draft.responsibleParty.displayCopy.text(for: appLanguage),
        systemImage: "person.crop.circle",
        accessibilityIdentifier: "action-responsible-\(action.id)"
      )
    }
  }

  @ViewBuilder
  private var statusBadges: some View {
    VStack(alignment: .leading, spacing: 5) {
      if action.needsReview {
        StatusBadge(
          text: localized("需要覆核", "Needs review"),
          systemImage: "exclamationmark.triangle.fill",
          tint: .orange
        )
      }

      if isEdited {
        StatusBadge(
          text: localized("已修改，請再核對", "Edited — check again"),
          systemImage: "pencil.circle.fill",
          tint: .blue
        )
      }

      if !easyReadMode || action.confidence != .high {
        StatusBadge(
          text: action.confidence.displayCopy.text(for: appLanguage),
          systemImage: "gauge.with.dots.needle.50percent",
          tint: action.confidence.tint
        )
      }
    }
  }

  private var reviewButtons: some View {
    Group {
      if CareBriefAdaptiveLayout.usesStackedActionControls(at: dynamicTypeSize) {
        VStack(alignment: .leading, spacing: 8) {
          editButton
          sourceButton
        }
      } else {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) {
            editButton
            sourceButton
          }
          VStack(alignment: .leading, spacing: 8) {
            editButton
            sourceButton
          }
        }
      }
    }
  }

  private var editButton: some View {
    Button(action: onEdit) {
      Label(localized("編輯", "Edit"), systemImage: "pencil")
        .labelStyle(.titleAndIcon)
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
        .accessibilityIdentifier("action-edit-label-\(action.id)")
    }
    .buttonStyle(.bordered)
    .tint(Color(uiColor: .label))
    .accessibilityIdentifier("action-edit-\(action.id)")
    .accessibilityHint(
      localized(
        "修改行動副本，不改原文證據",
        "Edits the draft without changing source evidence"
      )
    )
  }

  private var sourceButton: some View {
    Button(action: onViewEvidence) {
      Label(localized("原文", "Source"), systemImage: "quote.bubble")
        .labelStyle(.titleAndIcon)
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
        .accessibilityIdentifier("source-evidence-label-\(action.id)")
    }
    .buttonStyle(.bordered)
    .tint(Color(uiColor: .label))
    .accessibilityIdentifier("source-evidence-\(action.id)")
    .accessibilityHint(localized("查看精確來源文字", "Shows the exact source quote"))
  }

  private func localized(_ traditionalChinese: String, _ english: String) -> String {
    BilingualCopy(primary: traditionalChinese, secondary: english).text(for: appLanguage)
  }
}

private struct ActionDetailRow: View {
  let label: String
  let value: String
  let systemImage: String
  let accessibilityIdentifier: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(Color(uiColor: .label))
        .imageScale(.small)
        .frame(minWidth: 18)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
      Text(verbatim: value)
        .font(.subheadline)
        .foregroundStyle(Color(uiColor: .label))
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
    .frame(minHeight: 44, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(label): \(value)")
    .accessibilityAddTraits(.isStaticText)
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}

private struct StatusBadge: View {
  let text: String
  let systemImage: String
  let tint: Color

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      Image(systemName: systemImage)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      Text(text)
        .foregroundStyle(Color(uiColor: .label))
    }
    .font(.caption.weight(.semibold))
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
  }
}

extension ActionCategory {
  var bilingualName: BilingualCopy {
    switch self {
    case .appointment:
      BilingualCopy(primary: "覆診／預約", secondary: "Appointment")
    case .deadline:
      BilingualCopy(primary: "限期", secondary: "Deadline")
    case .preparation:
      BilingualCopy(primary: "準備", secondary: "Preparation")
    case .requiredItem:
      BilingualCopy(primary: "要帶物品", secondary: "Required item")
    case .contact:
      BilingualCopy(primary: "聯絡", secondary: "Contact")
    case .nextStep:
      BilingualCopy(primary: "下一步", secondary: "Next step")
    case .location:
      BilingualCopy(primary: "地點", secondary: "Location")
    }
  }

  var displayName: String { bilingualName.secondary }

  var systemImage: String {
    switch self {
    case .appointment: "calendar"
    case .deadline: "clock"
    case .preparation: "checkmark.circle"
    case .requiredItem: "bag"
    case .contact: "phone"
    case .nextStep: "arrow.right.circle"
    case .location: "mappin.and.ellipse"
    }
  }
}

extension ConfidenceLevel {
  var displayCopy: BilingualCopy {
    switch self {
    case .high: BilingualCopy(primary: "高可信度", secondary: "High confidence")
    case .medium: BilingualCopy(primary: "中可信度", secondary: "Medium confidence")
    case .low: BilingualCopy(primary: "低可信度", secondary: "Low confidence")
    }
  }

  var displayName: String {
    switch self {
    case .high: "High confidence"
    case .medium: "Medium confidence"
    case .low: "Low confidence"
    }
  }

  var tint: Color {
    switch self {
    case .high: .accentColor
    case .medium: .orange
    case .low: .red
    }
  }
}

extension ResponsibleParty {
  var displayCopy: BilingualCopy {
    switch self {
    case .me: BilingualCopy(primary: "我", secondary: "Me")
    case .familyOrCaregiver:
      BilingualCopy(primary: "家人／照顧者", secondary: "Family or caregiver")
    case .custom(let name): BilingualCopy(primary: name, secondary: name)
    }
  }
}

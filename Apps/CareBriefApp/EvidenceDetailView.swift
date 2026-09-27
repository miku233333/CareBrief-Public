import CareBriefCore
import SwiftUI

struct EvidenceDetailView: View {
  @Environment(\.careBriefEasyReadMode) private var easyReadMode
  @Environment(\.careBriefAppLanguage) private var appLanguage
  @State private var isTechnicalDetailsExpanded = false
  let evidence: SourceEvidence
  let sourceDocument: SourceDocument?

  private var evidenceResolves: Bool {
    guard let sourceDocument else { return false }
    return evidence.resolves(in: sourceDocument)
  }

  var body: some View {
    List {
      Section {
        if evidenceResolves {
          Label {
            Text(localized("原文已核實", "Exact quote verified"))
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("carebrief.evidenceVerificationTitle")
          } icon: {
            Image(systemName: "checkmark.shield.fill")
              .foregroundStyle(.green)
          }
        } else {
          Label {
            Text(localized("未能核實原文連結", "Source link not verified"))
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("carebrief.evidenceVerificationTitle")
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
          }
        }

        BilingualLabel(
          evidenceResolves
            ? BilingualCopy(
              primary: easyReadMode ? "原文相符。" : "這段文字及位置與目前文件相符。",
              secondary: easyReadMode
                ? "This quote matches the document."
                : "The quote and UTF-16 range resolve to the current source text."
            )
            : BilingualCopy(
              primary: easyReadMode
                ? "請返回文件再找出行動。" : "請返回文件重新抽取，再使用這項行動。",
              secondary: easyReadMode
                ? "Return to the document and find actions again."
                : "Return to the document and extract again before using this action."
            ),
          style: .body
        )
        .accessibilityIdentifier("carebrief.evidenceVerificationExplanation")
      } header: {
        Text(localized("原文連結", "Source link"))
          .foregroundStyle(.primary)
          .accessibilityIdentifier("carebrief.evidenceLinkHeader")
      }

      Section {
        Text(verbatim: evidence.text)
          .font(.body)
          .textSelection(.enabled)
      } header: {
        Text(localized("原文", "Exact source text"))
          .foregroundStyle(.primary)
          .accessibilityIdentifier("carebrief.evidenceSourceHeader")
      }

      Section {
        DisclosureGroup(
          localized("技術資料", "Technical details"),
          isExpanded: $isTechnicalDetailsExpanded
        ) {
          extractionMetadata
          Text(
            localized(
              "範圍採半開區間：由第一個數字開始，至第二個數字之前結束。UTF-16 對應 Apple Vision、NSRange 及 TextKit。",
              "The range is half-open and uses UTF-16 to match Apple Vision, NSRange, and TextKit."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle(localized("原文證據", "Source"))
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: easyReadMode) { isEasyRead in
      isTechnicalDetailsExpanded = !isEasyRead
    }
    .onAppear {
      isTechnicalDetailsExpanded = !easyReadMode
    }
  }

  @ViewBuilder
  private var extractionMetadata: some View {
    EvidenceMetadataRow(label: localized("規則 ID", "Rule ID"), value: evidence.ruleID)
    EvidenceMetadataRow(
      label: localized("UTF-16 範圍", "Range"),
      value: "[\(evidence.range.location), \(evidence.range.endLocation))"
    )
  }

  private func localized(_ traditionalChinese: String, _ english: String) -> String {
    BilingualCopy(primary: traditionalChinese, secondary: english).text(for: appLanguage)
  }
}

private struct EvidenceMetadataRow: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(verbatim: value)
        .font(.body.monospaced())
        .textSelection(.enabled)
    }
  }
}

import Foundation
import Testing

@testable import CareBriefCore

@Suite struct RuleBasedActionExtractorTests {
  private let extractor = RuleBasedActionExtractor()

  @Test func chineseAppointmentProducesEvidenceLinkedActions() throws {
    let text = """
      您需於 2026 年 8 月 15 日上午 9 時到威爾斯親王醫院內科門診覆診，覆診前禁食 8 小時，請攜帶身份證及覆診紙。
      """
    let document = SourceDocument(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
      text: text,
      language: .traditionalChinese
    )

    let result = extractor.extract(from: document)
    let appointment = try #require(result.actions.first { $0.category == .appointment })
    let preparation = try #require(result.actions.first { $0.category == .preparation })
    let requiredItems = try #require(result.actions.first { $0.category == .requiredItem })

    #expect(appointment.dateTime?.iso8601Local == "2026-08-15T09:00")
    #expect(appointment.location == "威爾斯親王醫院內科門診")
    #expect(requiredItems.items == ["身份證", "覆診紙"])
    #expect(preparation.confidence == .high)
    #expect(result.actions.allSatisfy { $0.evidence.resolves(in: document) })
  }

  @Test func englishDeadlineAndContactAreExtracted() throws {
    let text = "Submit the completed form by 17 July 2026.\nFor enquiries, contact 2123 4567."
    let document = SourceDocument(text: text, language: .english)
    let result = extractor.extract(from: document)

    let deadline = try #require(result.actions.first { $0.category == .deadline })
    let contact = try #require(result.actions.first { $0.category == .contact })
    #expect(deadline.dateTime?.iso8601Local == "2026-07-17")
    #expect(contact.contact == "2123 4567")
  }

  @Test func englishAppointmentLocationExcludesTimePhrase() throws {
    for time in ["9:00 AM", "9 AM"] {
      let document = SourceDocument(
        text: "Appointment on August 15, 2026 at \(time) at Prince of Wales Hospital."
      )
      let appointment = try #require(
        extractor.extract(from: document).actions.first { $0.category == .appointment }
      )

      #expect(appointment.dateTime?.iso8601Local == "2026-08-15T09:00")
      #expect(appointment.location == "Prince of Wales Hospital")
    }
  }

  @Test func appointmentLetterDoesNotCreateFalseAppointment() throws {
    let document = SourceDocument(text: "Please bring your HKID and appointment letter.")
    let result = extractor.extract(from: document)

    #expect(!result.actions.contains { $0.category == .appointment })
    #expect(
      result.actions.first { $0.category == .requiredItem }?.items
        == ["HKID", "appointment letter"]
    )
  }

  @Test func ambiguousNumericDateIsNotInvented() {
    let document = SourceDocument(text: "Please submit by 03/04/26.")
    let result = extractor.extract(from: document)

    #expect(!result.actions.contains { $0.category == .deadline })
    #expect(result.requiresReview)
  }

  @Test func unsupportedTextReturnsNoActionAndWarning() {
    let result = extractor.extract(from: SourceDocument(text: "這是一封一般資料通知。"))

    #expect(result.actions.isEmpty)
    #expect(result.warnings.count == 1)
    #expect(result.requiresReview)
  }

  @Test func actionIdentifiersAreDeterministicForSameDocument() {
    let document = SourceDocument(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
      text: "請攜帶身份證。"
    )

    #expect(
      extractor.extract(from: document).actions.map(\.id)
        == extractor.extract(from: document).actions.map(\.id)
    )
  }

  @Test func jsonIncludesNormalizedDateAndReviewState() throws {
    let document = SourceDocument(
      text: "Appointment on August 15, 2026 at 9:00 AM at Prince of Wales Hospital."
    )
    let result = extractor.extract(from: document)
    let data = try JSONEncoder().encode(result)
    let object = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let actions = try #require(object["actions"] as? [[String: Any]])
    let dateTime = try #require(actions.first?["dateTime"] as? [String: Any])

    #expect(object["requiresReview"] as? Bool == false)
    #expect(dateTime["iso8601Local"] as? String == "2026-08-15T09:00")
    #expect(try JSONDecoder().decode(ExtractionResult.self, from: data) == result)
  }

  @Test func evidenceOffsetRemainsCorrectAfterEmoji() throws {
    let document = SourceDocument(text: "👵🏻 提醒\n請攜帶身份證。")
    let action = try #require(
      extractor.extract(from: document).actions.first { $0.category == .requiredItem }
    )

    #expect(action.evidence.text == "請攜帶身份證。")
    #expect(action.evidence.range.substring(in: document.text) == action.evidence.text)
    #expect(action.evidence.range.location > 4)
  }

  @Test func explicitLocationLabelCreatesReviewableLocationAction() throws {
    let document = SourceDocument(text: "地點：Prince of Wales Hospital")
    let location = try #require(
      extractor.extract(from: document).actions.first { $0.category == .location }
    )

    #expect(location.location == "Prince of Wales Hospital")
    #expect(location.needsReview)
  }

  @Test func cancelledAppointmentDoesNotEmitActiveAppointment() {
    let document = SourceDocument(
      text:
        "Your appointment on August 15, 2026 at 9:00 AM at Prince of Wales Hospital has been cancelled."
    )
    let result = extractor.extract(from: document)

    #expect(!result.actions.contains { $0.category == .appointment })
    #expect(result.warnings.contains { $0.contains("cancelled") })
    #expect(result.requiresReview)
  }

  @Test func explicitlyNegatedAppointmentDoesNotEmitActiveAppointment() {
    let result = extractor.extract(
      from: SourceDocument(
        text:
          "Do not attend the clinic on August 15, 2026 at 9:00 AM at Prince of Wales Hospital."
      )
    )

    #expect(!result.actions.contains { $0.category == .appointment })
    #expect(result.warnings.contains { $0.contains("negated appointment") })
    #expect(result.requiresReview)
  }

  @Test func scopedAppointmentNegationAllowsInterveningModifiers() {
    let texts = [
      "請勿於2026年8月15日上午9時到示範醫院覆診。",
      "不要覆診。",
      "Appointment on August 15, 2026 at 9:00 AM at Example Hospital; do not under any circumstances attend the clinic.",
    ]

    for text in texts {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(!result.actions.contains { $0.category == .appointment })
      #expect(result.warnings.contains { $0.contains("negated appointment") })
      #expect(result.requiresReview)
    }
  }

  @Test func appointmentNegationDoesNotCrossChineseClauseBoundary() throws {
    let result = extractor.extract(
      from: SourceDocument(
        text: "請勿致電0000 0000，請於2026年8月15日上午9時到示範醫院覆診。"
      )
    )

    let appointment = try #require(result.actions.first { $0.category == .appointment })
    #expect(appointment.dateTime?.iso8601Local == "2026-08-15T09:00")
    #expect(result.warnings.contains { $0.contains("negated contact") })
  }

  @Test func appointmentNegationIgnoresAppointmentContextModifiers() throws {
    let cases: [(text: String, excludedCategory: ActionCategory, warning: String)] = [
      (
        "不需要在覆診前禁食8小時，請於2026年8月15日上午9時到示範醫院覆診。",
        .preparation,
        "negated preparation"
      ),
      (
        "請勿在覆診時攜帶身份證，請於2026年8月15日上午9時到示範醫院覆診。",
        .requiredItem,
        "negated bring"
      ),
      (
        "不需要在覆診之前禁食8小時，請於2026年8月15日上午9時到示範醫院覆診。",
        .preparation,
        "negated preparation"
      ),
      (
        "毋須在覆診之後空腹，請於2026年8月15日上午9時到示範醫院覆診。",
        .preparation,
        "negated preparation"
      ),
      (
        "請勿在覆診的時候攜帶身份證，請於2026年8月15日上午9時到示範醫院覆診。",
        .requiredItem,
        "negated bring"
      ),
      (
        "不需要在覆診當天禁食，請於2026年8月15日上午9時到示範醫院覆診。",
        .preparation,
        "negated preparation"
      ),
    ]

    for testCase in cases {
      let result = extractor.extract(from: SourceDocument(text: testCase.text))
      let appointment = try #require(
        result.actions.first { $0.category == .appointment }
      )

      #expect(appointment.dateTime?.iso8601Local == "2026-08-15T09:00")
      #expect(!result.actions.contains { $0.category == testCase.excludedCategory })
      #expect(result.warnings.contains { $0.contains(testCase.warning) })
      #expect(!result.warnings.contains { $0.contains("negated appointment") })
    }
  }

  @Test func parentheticalEnglishNegationIsScopedAcrossActionKinds() {
    let cases = [
      (
        "Appointment on August 15, 2026 at 9:00 AM at Example Hospital; "
          + "Do not, under any circumstances, attend the clinic.",
        "negated appointment"
      ),
      (
        "Do not, under any circumstances, fast for 8 hours before the appointment.",
        "negated preparation"
      ),
      ("Do not, under any circumstances, bring your HKID to the appointment.", "negated bring"),
      ("Do not, under any circumstances, call 0000 0000 after 5:00 PM.", "negated contact"),
      (
        "Do not, under any circumstances, submit the form by August 15, 2026.", "negated submission"
      ),
    ]

    for (text, warning) in cases {
      let result = extractor.extract(from: SourceDocument(text: text))

      #expect(result.actions.isEmpty)
      #expect(result.warnings.contains { $0.contains(warning) })
      #expect(result.requiresReview)
    }
  }

  @Test func negatedPreparationAndBringInstructionsAreNotMadePositive() {
    let result = extractor.extract(from: SourceDocument(text: "毋須禁食，請勿攜帶身份證。"))

    #expect(!result.actions.contains { $0.category == .preparation })
    #expect(!result.actions.contains { $0.category == .requiredItem })
    #expect(result.requiresReview)
  }

  @Test func expandedNegatedPreparationInstructionsDoNotBecomePositiveActions() {
    for text in ["毋須空腹。", "不需要空腹。", "切勿禁食。"] {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(
        !result.actions.contains {
          $0.evidence.ruleID == "preparation.explicit-instruction"
        }
      )
      #expect(result.warnings.contains { $0.contains("negated preparation") })
      #expect(result.requiresReview)
    }
  }

  @Test func scopedPreparationNegationAllowsInterveningModifiers() {
    for text in [
      "不需要在覆診前禁食8小時。",
      "Do not before the appointment fast for 8 hours.",
    ] {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(
        !result.actions.contains {
          $0.evidence.ruleID == "preparation.explicit-instruction"
        }
      )
      #expect(result.warnings.contains { $0.contains("negated preparation") })
      #expect(result.requiresReview)
    }
  }

  @Test func expandedNegatedRequiredItemInstructionsDoNotBecomePositiveActions() {
    for text in ["Never bring your HKID.", "毋須帶同身份證。"] {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(!result.actions.contains { $0.category == .requiredItem })
      #expect(result.warnings.contains { $0.contains("negated bring") })
      #expect(result.requiresReview)
    }
  }

  @Test func scopedRequiredItemNegationAllowsInterveningModifiers() {
    for text in [
      "請勿在覆診時攜帶身份證。",
      "Do not at the appointment bring your HKID.",
    ] {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(!result.actions.contains { $0.category == .requiredItem })
      #expect(result.warnings.contains { $0.contains("negated bring") })
      #expect(result.requiresReview)
    }
  }

  @Test func negatedItemsAreNotEmbeddedInAppointment() throws {
    let document = SourceDocument(
      text: "請於2026年8月15日上午9時到威爾斯親王醫院覆診，毋須攜帶身份證。"
    )
    let result = extractor.extract(from: document)
    let appointment = try #require(result.actions.first { $0.category == .appointment })

    #expect(appointment.items.isEmpty)
    #expect(!result.actions.contains { $0.category == .requiredItem })
    #expect(result.requiresReview)
  }

  @Test func negatedDeadlineAndSubmissionAreNotEmitted() {
    let result = extractor.extract(
      from: SourceDocument(text: "Do not complete the form by 17 July 2026.")
    )

    #expect(!result.actions.contains { $0.category == .deadline })
    #expect(!result.actions.contains { $0.category == .nextStep })
    #expect(result.requiresReview)
  }

  @Test func neverSubmitDoesNotEmitDeadlineOrNextStep() {
    let result = extractor.extract(
      from: SourceDocument(text: "Never submit the form by August 15, 2026.")
    )

    #expect(!result.actions.contains { $0.category == .deadline })
    #expect(!result.actions.contains { $0.category == .nextStep })
    #expect(result.warnings.contains { $0.contains("negated submission") })
    #expect(result.requiresReview)
  }

  @Test func scopedSubmissionNegationAllowsInterveningModifiers() {
    for text in [
      "不要在2026年8月15日前提交表格。",
      "Do not under any circumstances submit the form by August 15, 2026.",
    ] {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(!result.actions.contains { $0.category == .deadline })
      #expect(!result.actions.contains { $0.category == .nextStep })
      #expect(result.warnings.contains { $0.contains("negated submission") })
      #expect(result.requiresReview)
    }
  }

  @Test func submissionNegationDoesNotCrossEnglishClauseBoundary() throws {
    let result = extractor.extract(
      from: SourceDocument(
        text: "Do not call 0000 0000; submit the form by August 15, 2026."
      )
    )

    _ = try #require(result.actions.first { $0.category == .deadline })
    _ = try #require(result.actions.first { $0.category == .nextStep })
    #expect(!result.actions.contains { $0.category == .contact })
    #expect(result.warnings.contains { $0.contains("negated contact") })
  }

  @Test func sentenceSegmentationAssociatesAppointmentWithNearestDate() throws {
    let document = SourceDocument(
      text:
        "Letter generated July 1, 2026. Appointment on August 15, 2026 at 9:00 AM at Prince of Wales Hospital."
    )
    let appointment = try #require(
      extractor.extract(from: document).actions.first { $0.category == .appointment }
    )

    #expect(appointment.dateTime?.iso8601Local == "2026-08-15T09:00")
    #expect(appointment.evidence.text.hasPrefix("Appointment on August 15"))
  }

  @Test func ambiguousAppointmentWarningIsNotHiddenByUnrelatedDate() {
    let document = SourceDocument(
      text: "Letter generated July 1, 2026. Appointment: 03/04/26. Please bring your HKID."
    )
    let result = extractor.extract(from: document)

    #expect(!result.actions.contains { $0.category == .appointment })
    #expect(result.actions.contains { $0.category == .requiredItem })
    #expect(result.warnings.contains { $0.contains("not explicit enough") })
    #expect(result.requiresReview)
  }

  @Test func labResultLabelsDoNotBecomePreparationInstructions() {
    for text in ["Fasting blood glucose: 5.0 mmol/L.", "空腹血糖：5.0 mmol/L。"] {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(!result.actions.contains { $0.category == .preparation })
    }
  }

  @Test func longerReferenceNumberDoesNotBecomePhoneContact() {
    let result = extractor.extract(
      from: SourceDocument(text: "Please call reference number 123456789.")
    )
    #expect(!result.actions.contains { $0.category == .contact })
  }

  @Test func englishContactCuesRequireWholeWords() {
    for text in ["Please recall case 2123 4567.", "Contactless card 2123 4567."] {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(!result.actions.contains { $0.category == .contact })
    }
  }

  @Test func chineseAppointmentSlipDoesNotBecomeAppointment() throws {
    let document = SourceDocument(
      text: "請於2026年8月15日上午9時攜帶覆診紙到辦事處辦理手續。"
    )
    let result = extractor.extract(from: document)
    let items = try #require(result.actions.first { $0.category == .requiredItem })

    #expect(!result.actions.contains { $0.category == .appointment })
    #expect(items.items == ["覆診紙"])
  }

  @Test func multipleDatesInOneSegmentAreNotArbitrarilyBound() {
    let document = SourceDocument(
      text: "Appointment August 15, 2026; submit by August 10, 2026."
    )
    let result = extractor.extract(from: document)

    #expect(!result.actions.contains { $0.category == .appointment })
    #expect(!result.actions.contains { $0.category == .deadline })
    #expect(result.warnings.contains { $0.contains("Multiple dates") })
    #expect(result.requiresReview)
  }

  @Test func requiredItemCaptureStopsBeforeAnotherActionClause() throws {
    let cases = [
      ("Bring your HKID and arrive 15 minutes early.", ["HKID"]),
      ("攜帶身份證到辦事處辦理手續。", ["身份證"]),
      ("請攜帶身份證，覆診紙，藥物清單。", ["身份證", "覆診紙", "藥物清單"]),
    ]

    for (text, expectedItems) in cases {
      let action = try #require(
        extractor.extract(from: SourceDocument(text: text)).actions.first {
          $0.category == .requiredItem
        }
      )
      #expect(action.items == expectedItems)
    }
  }

  @Test func issuedDateDoesNotBindToUnrelatedAppointmentOrDeadline() {
    let cases: [(String, ActionCategory)] = [
      (
        "This letter was issued on August 1, 2026 at 10:00 AM about your appointment at Prince of Wales Hospital.",
        .appointment
      ),
      (
        "This notice was issued on August 1, 2026 at 10:00 AM and explains the deadline.",
        .deadline
      ),
    ]

    for (text, category) in cases {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(!result.actions.contains { $0.category == category })
      #expect(result.requiresReview)
    }
  }

  @Test func explicitOppositesDoNotBecomePositiveActions() {
    let cases: [(String, ActionCategory)] = [
      (
        "This is not an appointment on August 1, 2026 at 10:00 AM at Prince of Wales Hospital.",
        .appointment
      ),
      ("這不是覆診安排：2026年8月1日上午10時到威爾斯親王醫院。", .appointment),
      ("You are not required to bring your HKID.", .requiredItem),
    ]

    for (text, category) in cases {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(!result.actions.contains { $0.category == category })
      #expect(result.requiresReview)
    }
  }

  @Test func negatedContactsAreNotEmittedAndExplicitEmailWins() throws {
    for text in ["Do not call 2123 4567.", "This is not our contact number: 2123 4567."] {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(!result.actions.contains { $0.category == .contact })
      #expect(result.requiresReview)
    }

    let result = extractor.extract(
      from: SourceDocument(
        text: "Contact us by email help@example.com, quoting reference 12345678."
      )
    )
    let contact = try #require(result.actions.first { $0.category == .contact })
    #expect(contact.contact == "help@example.com")
  }

  @Test func expandedNegatedContactsDoNotEmitPositiveActions() {
    for text in ["Do not contact 2123 4567.", "Never call 2123 4567."] {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(!result.actions.contains { $0.category == .contact })
      #expect(result.warnings.contains { $0.contains("negated contact") })
      #expect(result.requiresReview)
    }
  }

  @Test func scopedContactNegationAllowsInterveningModifiers() {
    for text in [
      "請勿在下午5時後致電0000 0000。",
      "Do not after 5:00 PM call 0000 0000.",
    ] {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(!result.actions.contains { $0.category == .contact })
      #expect(result.warnings.contains { $0.contains("negated contact") })
      #expect(result.requiresReview)
    }
  }

  @Test func decodedAmbiguousActionCannotDisableReview() throws {
    let document = SourceDocument(
      text: "Appointment on August 15, 2026 at 3 at Prince of Wales Hospital."
    )
    let action = try #require(
      extractor.extract(from: document).actions.first { $0.category == .appointment }
    )
    let encoded = try JSONEncoder().encode(action)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["needsReview"] = false
    let contradictory = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(ActionCard.self, from: contradictory)

    #expect(decoded.dateTime?.isAmbiguous == true)
    #expect(decoded.needsReview)
  }

  @Test func mismatchedEvidenceDocumentForcesResultReview() throws {
    let source = SourceDocument(text: "請攜帶身份證。")
    let action = try #require(
      extractor.extract(from: source).actions.first { $0.category == .requiredItem }
    )
    let result = ExtractionResult(documentID: UUID(), actions: [action])

    #expect(result.requiresReview)
    #expect(result.warnings.contains { $0.contains("different source document") })
  }

  // MARK: - Medication instruction rules

  @Test func genericSchedulesDoNotBecomeMedicationInstructions() {
    let texts = [
      "每日辦公時間為上午九時至下午五時。",
      "請每日量度血壓並記錄。",
      "每週覆診一次。",
      "Your appointment is at bedtime.",
    ]

    for text in texts {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(
        !result.actions.contains {
          $0.evidence.ruleID == "medication.explicit-instruction"
        }
      )
    }
  }

  @Test func medicationReferencesWithoutAdministrationDoNotBecomeMedicationInstructions() {
    let texts = [
      "請每日更新藥物清單。",
      "Review your medication list once daily.",
      "Take your temperature once daily.",
      "Take a photo at bedtime.",
    ]

    for text in texts {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(
        !result.actions.contains {
          $0.evidence.ruleID == "medication.explicit-instruction"
        }
      )
    }
  }

  @Test func stoppedOrNegatedMedicationInstructionsDoNotBecomePositiveActions() {
    let texts = [
      "Do not take aspirin once daily.",
      "Do not take this medicine at bedtime.",
      "Stop taking aspirin once daily.",
      "Cancel this medication at bedtime.",
      "Hold this medicine twice daily.",
      "Discontinue this medication once daily.",
      "請勿每天服用阿司匹林。",
      "請停止每天服用阿司匹林。",
      "暫停每日服藥一次。",
      "取消每週服用此藥。",
    ]

    for text in texts {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(
        !result.actions.contains {
          $0.evidence.ruleID == "medication.explicit-instruction"
        }
      )
      #expect(result.warnings.contains { $0.contains("negated medication") })
    }
  }

  @Test func expandedNegatedOrWithdrawnMedicationInstructionsDoNotBecomePositiveActions() {
    let texts = [
      "Never take one aspirin tablet once daily.",
      "Avoid taking one aspirin tablet once daily.",
      "Take one aspirin tablet once daily; discontinued.",
      "Take one aspirin tablet once daily, but this has been discontinued.",
      "切勿每天服用阿司匹林。",
      "禁止每日服藥一次。",
      "每日服藥一次，現已停用。",
    ]

    for text in texts {
      let result = extractor.extract(from: SourceDocument(text: text))
      #expect(
        !result.actions.contains {
          $0.evidence.ruleID == "medication.explicit-instruction"
        }
      )
      #expect(result.warnings.contains { $0.contains("negated medication") })
      #expect(result.requiresReview)
    }
  }

  @Test func medicationNegationDoesNotCrossClauseBoundary() throws {
    for text in [
      "請勿致電0000 0000，每日服藥一次。",
      "Do not call 0000 0000; take one aspirin tablet once daily.",
    ] {
      let result = extractor.extract(from: SourceDocument(text: text))
      let medication = try #require(
        result.actions.first {
          $0.evidence.ruleID == "medication.explicit-instruction"
        }
      )
      #expect(medication.needsReview)
      #expect(result.warnings.contains { $0.contains("negated contact") })
    }
  }

  @Test func chineseMedicationBeforeMealsIsExtracted() throws {
    let document = SourceDocument(
      text: "處方藥物阿司匹林，每日三次飯前服用。"
    )
    let result = extractor.extract(from: document)
    let medication = try #require(
      result.actions.first {
        $0.category == .preparation && $0.evidence.ruleID == "medication.explicit-instruction"
      }
    )
    #expect(medication.title == "Medication")
    #expect(medication.confidence == .medium)
    #expect(medication.needsReview)
  }

  @Test func chineseMedicationAfterMealsWithFrequencyIsExtracted() throws {
    let document = SourceDocument(
      text: "頭孢抗生素每日兩次餐後服用。"
    )
    let result = extractor.extract(from: document)
    let medication = try #require(
      result.actions.first {
        $0.category == .preparation && $0.evidence.ruleID == "medication.explicit-instruction"
      }
    )
    #expect(medication.evidence.text.contains("餐後服用"))
  }

  @Test func englishMedicationTwiceDailyIsExtracted() throws {
    let document = SourceDocument(
      text: "Take one metformin tablet twice daily after meals."
    )
    let result = extractor.extract(from: document)
    let medication = try #require(
      result.actions.first {
        $0.category == .preparation && $0.evidence.ruleID == "medication.explicit-instruction"
      }
    )
    #expect(medication.title == "Medication")
    #expect(medication.confidence == .medium)
    #expect(medication.needsReview)
  }

  @Test func englishMedicationThreeTimesPerDayIsExtracted() throws {
    let document = SourceDocument(
      text: "Take ibuprofen 200 mg 3 times a day with food."
    )
    let result = extractor.extract(from: document)
    #expect(
      result.actions.contains {
        $0.category == .preparation && $0.evidence.ruleID == "medication.explicit-instruction"
      }
    )
  }

  @Test func negatedMedicationInstructionDoesNotEmitPositiveAction() {
    let document = SourceDocument(text: "毋須飯前服用，正常飲食即可。")
    let result = extractor.extract(from: document)
    #expect(!result.actions.contains { $0.evidence.ruleID == "medication.explicit-instruction" })
    #expect(result.warnings.contains { $0.contains("negated medication") })
  }

  @Test func englishNegatedMedicationDoesNotEmit() {
    let document = SourceDocument(text: "Do not take before meals. Normal diet is fine.")
    let result = extractor.extract(from: document)
    #expect(!result.actions.contains { $0.evidence.ruleID == "medication.explicit-instruction" })
  }

  @Test func chineseMedicationWithNumericFrequencyIsExtracted() throws {
    let document = SourceDocument(text: "每日3次飯後服用。")
    let result = extractor.extract(from: document)
    #expect(
      result.actions.contains {
        $0.category == .preparation && $0.evidence.ruleID == "medication.explicit-instruction"
      }
    )
  }

  @Test func bedtimeMedicationIsExtracted() throws {
    let document = SourceDocument(text: "Take the sleeping pill at bedtime.")
    let result = extractor.extract(from: document)
    #expect(
      result.actions.contains {
        $0.category == .preparation && $0.evidence.ruleID == "medication.explicit-instruction"
      }
    )
  }

  // MARK: - Enhanced next-step rules

  @Test func chineseNextStepCompleteCheckIsExtracted() throws {
    let document = SourceDocument(text: "請完成以下檢查並交回結果。")
    let result = extractor.extract(from: document)
    let nextStep = try #require(
      result.actions.first { $0.category == .nextStep }
    )
    #expect(nextStep.needsReview)
    #expect(nextStep.confidence == .medium)
  }

  @Test func chineseNextStepRegistrationIsExtracted() throws {
    let document = SourceDocument(text: "請先辦理登記手續，然後前往等候區。")
    let result = extractor.extract(from: document)
    #expect(result.actions.contains { $0.category == .nextStep })
  }

  @Test func englishNextStepFillOutFormIsExtracted() throws {
    let document = SourceDocument(
      text: "Please fill out the enclosed form and return it by Friday.")
    let result = extractor.extract(from: document)
    #expect(result.actions.contains { $0.category == .nextStep })
  }

  // MARK: - Realistic combined appointment letter

  @Test func realisticAppointmentLetterExtractsAllCategories() throws {
    let text = """
      威爾斯親王醫院內科門診覆診信。
      請於2026年8月15日上午9時到內科門診覆診。
      覆診前禁食8小時。處方藥物阿司匹林每日兩次飯後服用。
      請攜帶身份證、覆診紙及藥物清單。
      如有查詢請致電2632 2211。
      請先辦理登記手續。
      """
    let document = SourceDocument(text: text, language: .traditionalChinese)
    let result = extractor.extract(from: document)

    #expect(result.actions.contains { $0.category == .appointment })
    #expect(
      result.actions.contains {
        $0.category == .preparation && $0.evidence.ruleID == "preparation.explicit-instruction"
      })
    #expect(
      result.actions.contains {
        $0.category == .preparation && $0.evidence.ruleID == "medication.explicit-instruction"
      })
    #expect(result.actions.contains { $0.category == .requiredItem })
    #expect(result.actions.contains { $0.category == .contact })
    #expect(result.actions.contains { $0.category == .nextStep })
    #expect(result.actions.allSatisfy { $0.evidence.resolves(in: document) })
  }

  @Test func medicationAndPreparationCoexistWithoutConflict() throws {
    let document = SourceDocument(
      text: "覆診前禁食8小時。每日三次飯後服用阿司匹林。"
    )
    let result = extractor.extract(from: document)
    let preparations = result.actions.filter { $0.category == .preparation }
    #expect(preparations.count >= 2)
    #expect(preparations.contains { $0.evidence.ruleID == "preparation.explicit-instruction" })
    #expect(preparations.contains { $0.evidence.ruleID == "medication.explicit-instruction" })
  }
}

import Foundation

public struct RuleBasedActionExtractor: DocumentActionExtracting, Sendable {
  private struct Segment {
    let text: String
    let range: UTF16TextRange
  }

  private struct SegmentExtraction {
    var actions: [ActionCard] = []
    var warnings: [String] = []
  }

  private enum InstructionKind {
    case appointment
    case contact
    case medication
    case preparation
    case requiredItem
    case submission
  }

  private enum InstructionPolarity {
    case affirmative
    case negatedOrWithdrawn
  }

  private let dateTimeParser: DocumentDateTimeParser

  public init(dateTimeParser: DocumentDateTimeParser = .init()) {
    self.dateTimeParser = dateTimeParser
  }

  public func extract(from document: SourceDocument) -> ExtractionResult {
    var actions: [ActionCard] = []
    var warnings: [String] = []

    for segment in segments(in: document.text) {
      let extraction = extract(from: segment, document: document)
      actions.append(contentsOf: extraction.actions)
      warnings.append(contentsOf: extraction.warnings)
    }

    actions = deduplicated(actions).sorted {
      if $0.evidence.range.location == $1.evidence.range.location {
        return categoryOrder($0.category) < categoryOrder($1.category)
      }
      return $0.evidence.range.location < $1.evidence.range.location
    }

    warnings = deduplicatedWarnings(warnings)
    if actions.isEmpty {
      warnings.append(
        "No supported actionable instruction was found. Review the source document manually.")
    }

    return ExtractionResult(
      documentID: document.id,
      actions: actions,
      warnings: warnings
    )
  }

  private func extract(from segment: Segment, document: SourceDocument) -> SegmentExtraction {
    let lower = segment.text.lowercased()
    let parsedDateTimes = dateTimeParser.matches(in: segment.text)
    let parsedDateTime = parsedDateTimes.count == 1 ? parsedDateTimes.first : nil
    let location = extractLocation(from: segment.text)
    let requiredItems = extractRequiredItems(from: segment.text)
    let contact = extractContact(from: segment.text)
    var result = SegmentExtraction()

    if parsedDateTimes.count > 1 {
      result.warnings.append(
        "Multiple dates or times occur in one source segment; no single structured date was selected."
      )
    }

    let negatesPreparation =
      instructionPolarity(for: .preparation, in: lower) == .negatedOrWithdrawn
    let negatesRequiredItems =
      instructionPolarity(for: .requiredItem, in: lower) == .negatedOrWithdrawn
    let negatesSubmission =
      instructionPolarity(for: .submission, in: lower) == .negatedOrWithdrawn
    let negatesDeadline = contains(
      [
        "截止日期不適用", "截止不適用", "無截止日期", "沒有截止日期", "截止日期取消",
        "no deadline", "deadline not applicable", "deadline does not apply", "deadline cancelled",
        "deadline canceled",
      ],
      in: lower
    )

    let hasChineseAppointmentCue =
      firstMatch(
        pattern: #"(?:覆診|應診|預約)(?![紙信])"#,
        in: lower
      ) != nil
    let hasAppointmentKeyword =
      hasChineseAppointmentCue
      || contains(["appointment", "clinic visit", "attend the clinic"], in: lower)
    let onlyMentionsAppointmentLetter =
      lower.contains("appointment letter")
      && !contains(["appointment on", "appointment at", "attend the clinic"], in: lower)
      && !hasChineseAppointmentCue
    let negatesAppointment =
      hasAppointmentKeyword
      && instructionPolarity(for: .appointment, in: lower) == .negatedOrWithdrawn

    if hasAppointmentKeyword, negatesAppointment {
      result.warnings.append(
        "A cancelled, rescheduled, or negated appointment was detected; no active appointment action was emitted."
      )
    } else if hasAppointmentKeyword,
      !onlyMentionsAppointmentLetter,
      let parsedDateTime,
      hasAppointmentDateLink(in: segment.text, parsedDateTime: parsedDateTime)
    {
      let needsReview =
        !parsedDateTime.value.hasTime
        || parsedDateTime.value.isAmbiguous
        || location == nil
      result.actions.append(
        makeCard(
          category: .appointment,
          ruleID: "appointment.explicit-date",
          title: "Appointment",
          detail: segment.text,
          dateTime: parsedDateTime.value,
          location: location,
          items: negatesRequiredItems ? [] : requiredItems,
          segment: segment,
          document: document,
          confidence: needsReview ? .medium : .high,
          needsReview: needsReview
        )
      )
    } else if hasAppointmentKeyword,
      !onlyMentionsAppointmentLetter,
      parsedDateTime != nil
    {
      result.warnings.append(
        "An appointment keyword and date were found without a clear action-date relationship; no appointment action was emitted."
      )
    }

    let hasDeadlineKeyword =
      contains(
        ["截止", "前提交", "前遞交", "deadline", "no later than", "submit by", "return by"],
        in: lower
      )
      || firstMatch(
        pattern: #"\b(?:submit|return|complete)[^\n.!?]{0,80}\bby\b"#,
        in: lower,
        options: [.caseInsensitive]
      ) != nil
    let negatedSubmissionWarning =
      "A negated submission or deadline instruction was detected; no positive deadline or next-step action was emitted."
    if hasDeadlineKeyword, negatesSubmission || negatesDeadline {
      result.warnings.append(negatedSubmissionWarning)
    } else if hasDeadlineKeyword,
      let parsedDateTime,
      hasDeadlineDateLink(in: segment.text, parsedDateTime: parsedDateTime)
    {
      result.actions.append(
        makeCard(
          category: .deadline,
          ruleID: "deadline.explicit-date",
          title: "Deadline",
          detail: segment.text,
          dateTime: parsedDateTime.value,
          segment: segment,
          document: document,
          confidence: parsedDateTime.confidence,
          needsReview: parsedDateTime.value.isAmbiguous
        )
      )
    } else if hasDeadlineKeyword, parsedDateTime != nil {
      result.warnings.append(
        "A deadline keyword and date were found without a clear due-date relationship; no deadline action was emitted."
      )
    }

    let hasPreparationInstruction =
      contains(
        [
          "禁食", "需要空腹", "須空腹", "保持空腹", "fast for", "please fast", "must fast",
          "do not eat", "avoid eating",
        ],
        in: lower
      )
      || (negatesPreparation && lower.contains("空腹"))
    if hasPreparationInstruction, negatesPreparation {
      result.warnings.append(
        "A negated preparation instruction was detected; no positive preparation action was emitted."
      )
    } else if hasPreparationInstruction {
      result.actions.append(
        makeCard(
          category: .preparation,
          ruleID: "preparation.explicit-instruction",
          title: "Preparation",
          detail: segment.text,
          segment: segment,
          document: document,
          confidence: .high,
          needsReview: false
        )
      )
    }

    let hasChineseMedicationAdministrationCue = contains(["服用", "服藥", "用藥"], in: lower)
    let hasEnglishMedicationTakeCue =
      firstMatch(
        pattern: #"\b(?:take|taking)\b"#,
        in: lower,
        options: [.caseInsensitive]
      ) != nil
    let hasMedicationEntityCue =
      contains(["藥物", "藥片", "藥丸", "藥水"], in: lower)
      || firstMatch(
        pattern: #"\b(?:medicine|medication|tablet|capsule|pill|dose)\b"#,
        in: lower,
        options: [.caseInsensitive]
      ) != nil
    let hasMedicationDosageCue =
      firstMatch(
        pattern: #"\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml)\b"#,
        in: lower,
        options: [.caseInsensitive]
      ) != nil
    let hasMedicationScheduleCue =
      contains(
        [
          "飯前服用", "飯後服用", "餐前服用", "餐後服用", "睡前服用",
          "每日", "每天", "每週",
          "take before meals", "take after meals", "take with food",
          "take on an empty stomach", "at bedtime",
          "times daily", "times a day", "once daily", "twice daily",
        ],
        in: lower
      )
      || firstMatch(
        pattern: #"(?:每日|每天)\s*[一二三四五六七八九\d]+\s*次"#,
        in: segment.text
      ) != nil
      || firstMatch(
        pattern: #"\d+\s*times?\s+(?:daily|a day|per day)"#,
        in: lower,
        options: [.caseInsensitive]
      ) != nil
    let hasMedicationInstruction =
      hasMedicationScheduleCue
      && (hasChineseMedicationAdministrationCue
        || (hasEnglishMedicationTakeCue
          && (hasMedicationEntityCue || hasMedicationDosageCue)))
    let negatesMedication =
      instructionPolarity(for: .medication, in: lower) == .negatedOrWithdrawn
    if hasMedicationScheduleCue,
      hasChineseMedicationAdministrationCue || hasEnglishMedicationTakeCue
        || hasMedicationEntityCue || hasMedicationDosageCue,
      negatesMedication
    {
      result.warnings.append(
        "A negated medication instruction was detected; no positive medication action was emitted."
      )
    } else if hasMedicationInstruction {
      result.actions.append(
        makeCard(
          category: .preparation,
          ruleID: "medication.explicit-instruction",
          title: "Medication",
          detail: segment.text,
          segment: segment,
          document: document,
          confidence: .medium,
          needsReview: true
        )
      )
    }

    let hasRequiredItemInstruction = contains(["攜帶", "帶同", "bring"], in: lower)
    if hasRequiredItemInstruction, negatesRequiredItems {
      result.warnings.append(
        "A negated bring instruction was detected; no required-item action was emitted."
      )
    } else if hasRequiredItemInstruction, !requiredItems.isEmpty {
      result.actions.append(
        makeCard(
          category: .requiredItem,
          ruleID: "required-item.explicit-list",
          title: "Bring",
          detail: segment.text,
          items: requiredItems,
          segment: segment,
          document: document,
          confidence: .high,
          needsReview: false
        )
      )
    }

    let hasContactCue =
      contains(["致電", "聯絡", "查詢"], in: lower)
      || firstMatch(
        pattern: #"\b(?:call|contact)\b"#,
        in: lower,
        options: [.caseInsensitive]
      ) != nil
    let negatesContact =
      instructionPolarity(for: .contact, in: lower) == .negatedOrWithdrawn
    if hasContactCue, negatesContact {
      result.warnings.append(
        "A negated contact instruction was detected; no positive contact action was emitted."
      )
    } else if hasContactCue,
      let contact
    {
      result.actions.append(
        makeCard(
          category: .contact,
          ruleID: "contact.explicit-value",
          title: "Contact",
          detail: segment.text,
          contact: contact,
          segment: segment,
          document: document,
          confidence: .high,
          needsReview: false
        )
      )
    }

    let hasNextStepInstruction = contains(
      [
        "填妥", "交回", "提交", "上載", "submit", "return the", "complete the", "upload",
        "請完成以下", "請先辦理", "請填寫", "please complete the following",
        "fill out the form", "fill in the form", "please fill in",
        "please fill out", "please register", "please proceed to",
      ],
      in: lower
    )
    if hasNextStepInstruction, negatesSubmission {
      result.warnings.append(negatedSubmissionWarning)
    } else if hasNextStepInstruction {
      result.actions.append(
        makeCard(
          category: .nextStep,
          ruleID: "next-step.explicit-instruction",
          title: "Next step",
          detail: segment.text,
          segment: segment,
          document: document,
          confidence: .medium,
          needsReview: true
        )
      )
    }

    let explicitlyLabelsLocation = contains(
      ["地點", "地址", "location:", "address:"],
      in: lower
    )
    if explicitlyLabelsLocation,
      !hasAppointmentKeyword,
      let location
    {
      result.actions.append(
        makeCard(
          category: .location,
          ruleID: "location.explicit-label",
          title: "Location",
          detail: segment.text,
          location: location,
          segment: segment,
          document: document,
          confidence: .medium,
          needsReview: true
        )
      )
    }

    let hasUnresolvedAppointment =
      parsedDateTimes.isEmpty
      && hasAppointmentKeyword
      && !onlyMentionsAppointmentLetter
      && !negatesAppointment
    if hasUnresolvedAppointment || (hasDeadlineKeyword && parsedDateTimes.isEmpty) {
      result.warnings.append(
        "A date or time may be present but was not explicit enough to parse safely."
      )
    }

    return result
  }

  private func instructionPolarity(
    for kind: InstructionKind,
    in lower: String
  ) -> InstructionPolarity {
    switch kind {
    case .appointment:
      let hasFixedPolarity = contains(
        [
          "取消", "改期", "延期", "cancelled", "canceled", "rescheduled", "postponed",
          "no longer scheduled", "not an appointment", "not a scheduled appointment",
          "不是覆診", "並非覆診", "非覆診安排", "不是預約", "並非預約",
        ],
        in: lower
      )
      let hasScopedNegation = hasBoundedPreposedNegation(
        before:
          #"(?:(?:(?:到|前往)[^\n。！？.!?，,；;]{0,60}(?:覆診|應診)|(?:覆診|應診|預約))(?=\s*(?:[。！？.!?，,；;]|$))|\battend\s+(?:the\s+)?clinic\b|\bvisit\s+(?:the\s+)?clinic\b)"#,
        in: lower
      )
      return hasFixedPolarity || hasScopedNegation ? .negatedOrWithdrawn : .affirmative
    case .contact:
      let hasFixedPolarity = contains(
        [
          "不要致電", "請勿致電", "切勿致電", "毋須聯絡", "無需聯絡", "do not call",
          "should not call", "must not call", "never call", "do not contact",
          "should not contact", "must not contact", "never contact", "not our contact",
          "not a contact number",
        ],
        in: lower
      )
      let hasScopedNegation = hasBoundedPreposedNegation(
        before: #"(?:致電|聯絡|查詢|\bcall\b|\bcontact\b)"#,
        in: lower
      )
      return hasFixedPolarity || hasScopedNegation ? .negatedOrWithdrawn : .affirmative
    case .medication:
      let medicationCuePattern =
        #"(?:服用|服藥|用藥|藥物|藥片|藥丸|藥水|\b(?:take|taking|medicine|medication|tablet|capsule|pill|dose)\b)"#
      let hasExplicitNegation =
        contains(
          [
            "毋須飯前服用", "毋須飯後服用", "不需要飯前服用", "不需要飯後服用",
            "不用飯前服用", "不用飯後服用",
            "do not take before meals", "do not take after meals",
            "no need to take before meals", "no need to take after meals",
            "not required to take before meals", "not required to take after meals",
          ],
          in: lower
        )
        || hasBoundedPreposedNegation(before: medicationCuePattern, in: lower)
        || firstMatch(
          pattern:
            #"(?:停止|停用|暫停|取消|\b(?:stop|cancel|hold|discontinue)\b)[^\n。！？.!?，,；;]{0,40}"#
            + medicationCuePattern,
          in: lower,
          options: [.caseInsensitive]
        ) != nil

      let hasExplicitWithdrawal =
        firstMatch(
          pattern:
            #"(?:服用|服藥|用藥|藥物|藥片|藥丸|藥水)[^\n。！？.!?]{0,40}(?:現已|已)?(?:停止|停用|取消)"#,
          in: lower
        ) != nil
        || firstMatch(
          pattern:
            #"\b(?:take|taking|medicine|medication|tablet|capsule|pill|dose)\b[^\n.!?]{0,80}\b(?:stopped|cancelled|canceled|held|discontinued)\b"#,
          in: lower,
          options: [.caseInsensitive]
        ) != nil

      return hasExplicitNegation || hasExplicitWithdrawal ? .negatedOrWithdrawn : .affirmative
    case .preparation:
      let hasFixedPolarity = contains(
        [
          "毋須禁食", "無須禁食", "無需禁食", "不用禁食", "不需禁食", "請勿禁食",
          "切勿禁食", "不必禁食", "毋須空腹", "無須空腹", "無需空腹", "不用空腹",
          "不需空腹", "不需要空腹", "不必空腹", "no need to fast",
          "not required to fast", "fasting is not required", "do not fast", "should not fast",
          "must not fast",
        ],
        in: lower
      )
      let hasScopedNegation = hasBoundedPreposedNegation(
        before: #"(?:禁食|空腹|\bfast(?:ing)?\b)"#,
        in: lower
      )
      return hasFixedPolarity || hasScopedNegation ? .negatedOrWithdrawn : .affirmative
    case .requiredItem:
      let hasFixedPolarity = contains(
        [
          "毋須攜帶", "無須攜帶", "無需攜帶", "不用攜帶", "不需攜帶", "請勿攜帶",
          "切勿攜帶", "不要攜帶", "不必攜帶", "毋須帶同", "無須帶同", "無需帶同",
          "不用帶同", "不需帶同", "請勿帶同", "切勿帶同", "do not bring",
          "should not bring", "must not bring", "never bring", "no need to bring",
          "do not need to bring", "not required to bring", "not necessary to bring",
        ],
        in: lower
      )
      let hasScopedNegation = hasBoundedPreposedNegation(
        before: #"(?:攜帶|帶同|\bbring\b)"#,
        in: lower
      )
      return hasFixedPolarity || hasScopedNegation ? .negatedOrWithdrawn : .affirmative
    case .submission:
      let hasFixedPolarity = contains(
        [
          "毋須提交", "無須提交", "無需提交", "不用提交", "不需提交", "請勿提交",
          "不要提交", "不必提交", "do not submit", "should not submit", "must not submit",
          "never submit", "no need to submit", "not required to submit", "do not upload",
          "never upload", "do not return", "never return", "do not complete",
          "never complete",
        ],
        in: lower
      )
      let hasScopedNegation = hasBoundedPreposedNegation(
        before:
          #"(?:提交|遞交|交回|上載|填妥|完成|\bsubmit\b|\bupload\b|\breturn\b|\bcomplete\b)"#,
        in: lower
      )
      return hasFixedPolarity || hasScopedNegation ? .negatedOrWithdrawn : .affirmative
    }
  }

  private func hasBoundedPreposedNegation(
    before actionCuePattern: String,
    in lower: String,
    maximumGap: Int = 80
  ) -> Bool {
    let negationCuePattern =
      #"(?:\b(?:do\s+not|don['’]t)\s*,?\s*under\s+any\s+circumstances\s*,?\s*|請勿|切勿|禁止|不要|不可|不得|毋須|無須|無需|不用|不需|不需要|不必|\b(?:do\s+not|don['’]t|should\s+not|must\s+not|never|avoid|no\s+need\s+to|do\s+not\s+need\s+to|not\s+required\s+to|not\s+necessary\s+to)\b)"#
    let sameClauseGap = #"[^\n。！？.!?，,；;]{0,"# + String(maximumGap) + "}"
    let pattern = negationCuePattern + sameClauseGap + "(?:" + actionCuePattern + ")"
    return firstMatch(pattern: pattern, in: lower, options: [.caseInsensitive]) != nil
  }

  private func makeCard(
    category: ActionCategory,
    ruleID: String,
    title: String,
    detail: String,
    dateTime: ActionDateTime? = nil,
    location: String? = nil,
    items: [String] = [],
    contact: String? = nil,
    segment: Segment,
    document: SourceDocument,
    confidence: ConfidenceLevel,
    needsReview: Bool
  ) -> ActionCard {
    let evidence = SourceEvidence(
      documentID: document.id,
      range: segment.range,
      text: segment.text,
      ruleID: ruleID
    )
    return ActionCard(
      category: category,
      title: title,
      detail: detail,
      dateTime: dateTime,
      location: location,
      items: items,
      contact: contact,
      evidence: evidence,
      confidence: confidence,
      needsReview: needsReview
    )
  }

  private func segments(in text: String) -> [Segment] {
    guard
      let regex = try? NSRegularExpression(
        pattern: #"[^\n]+?(?:[。！？!?]+|\.(?=\s|$)|$)"#,
        options: [.anchorsMatchLines]
      )
    else {
      return []
    }

    let source = text as NSString
    let fullRange = NSRange(location: 0, length: source.length)
    return regex.matches(in: text, range: fullRange).compactMap { match in
      let rawText = source.substring(with: match.range)
      let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedText.isEmpty else { return nil }
      let localRange = (rawText as NSString).range(of: trimmedText)
      let range = NSRange(
        location: match.range.location + localRange.location,
        length: localRange.length
      )
      guard let utf16Range = UTF16TextRange(range) else { return nil }
      return Segment(text: trimmedText, range: utf16Range)
    }
  }

  private func extractLocation(from text: String) -> String? {
    let patterns: [(String, NSRegularExpression.Options)] = [
      (#"(?:到|前往)\s*([^，。；;\n]{2,80}?)(?=覆診|應診|辦理|接受|，|。|；|;|$)"#, []),
      (#"(?:地點|地址)\s*[:：]\s*([^，。；;\n]{2,80})"#, []),
      (
        #"(?:at|in|location:|address:)\s+((?!(?:[0-9]{1,2}(?::[0-9]{2})?\s*(?:am|pm)?|noon|midnight)\b)[^,.;\n]{2,80}?(?:Hospital|Clinic|Centre|Center|Office|Building|Room)(?:\s+[^,.;\n]+)?)"#,
        [.caseInsensitive]
      ),
    ]

    for (pattern, options) in patterns {
      if let value = firstCapture(pattern: pattern, in: text, options: options) {
        return cleaned(value)
      }
    }
    return nil
  }

  private func extractRequiredItems(from text: String) -> [String] {
    let patterns: [(String, NSRegularExpression.Options)] = [
      (
        #"(?:攜帶|帶同)\s*(.+?)(?=到[^。！？\n]*(?:辦理|覆診|提交)|[，,]\s*(?:並|及後|然後)?\s*(?:前往|到|提交|辦理)|(?:並|及後|然後)(?:前往|到|提交|辦理)|[。！？\n]|$)"#,
        []
      ),
      (
        #"\bbring\s+(?:your\s+|the\s+)?(.+?)(?=\s+and\s+(?:arrive|attend|submit|return|go|visit|call|contact)\b|[.!?\n]|$)"#,
        [.caseInsensitive]
      ),
    ]

    for (pattern, options) in patterns {
      guard let captured = firstCapture(pattern: pattern, in: text, options: options) else {
        continue
      }

      let separators = try? NSRegularExpression(
        pattern: #"\s*(?:、|，|,|及|和|\band\b)\s*"#,
        options: [.caseInsensitive]
      )
      let source = captured as NSString
      let fullRange = NSRange(location: 0, length: source.length)
      let normalized =
        separators?.stringByReplacingMatches(
          in: captured,
          range: fullRange,
          withTemplate: "\n"
        ) ?? captured
      return
        normalized
        .split(separator: "\n")
        .map { cleaned(String($0)) }
        .filter { !$0.isEmpty }
    }

    return []
  }

  private func extractContact(from text: String) -> String? {
    let patterns = [
      #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
      #"(?<![0-9])(?:\+?852[\s-]?)?[0-9]{4}[\s-]?[0-9]{4}(?![0-9])"#,
    ]
    for pattern in patterns {
      if let value = firstMatch(
        pattern: pattern,
        in: text,
        options: [.caseInsensitive]
      ) {
        return cleaned(value)
      }
    }
    return nil
  }

  private func hasAppointmentDateLink(
    in text: String,
    parsedDateTime: ParsedDocumentDateTime
  ) -> Bool {
    let date = NSRegularExpression.escapedPattern(for: parsedDateTime.rawText)
    let patterns = [
      #"\bappointment\b[^\n.!?]{0,50}\b(?:on|for|at)\s+"# + date,
      #"\bappointment\b[^\n.!?]{0,50}\b(?:scheduled|booked)\b[^\n.!?]{0,20}(?:for|on|at)?\s*"#
        + date,
      #"\b(?:attend|visit|report to)\b[^\n.!?]{0,80}"# + date,
      #"(?:請|需|須|應)[^。！？]{0,80}"# + date + #"[^。！？]{0,80}(?:覆診|應診|預約)"#,
      #"(?:覆診|應診|預約)(?:日期|時間|安排)?[^。！？]{0,30}"# + date,
    ]
    return patterns.contains {
      firstMatch(pattern: $0, in: text, options: [.caseInsensitive]) != nil
    }
  }

  private func hasDeadlineDateLink(
    in text: String,
    parsedDateTime: ParsedDocumentDateTime
  ) -> Bool {
    let date = NSRegularExpression.escapedPattern(for: parsedDateTime.rawText)
    let patterns = [
      #"\b(?:deadline|due date)\b[^\n.!?]{0,40}(?:is|on|:)?\s*"# + date,
      #"\b(?:submit|return|complete)\b[^\n.!?]{0,80}\bby\s+"# + date,
      date + #"\s+(?:is\s+)?(?:the\s+)?(?:deadline|due date)\b"#,
      #"(?:截止|最遲)[^。！？]{0,30}"# + date,
      date + #"[^。！？]{0,30}(?:前提交|前遞交|為截止日期)"#,
    ]
    return patterns.contains {
      firstMatch(pattern: $0, in: text, options: [.caseInsensitive]) != nil
    }
  }

  private func firstCapture(
    pattern: String,
    in text: String,
    options: NSRegularExpression.Options = []
  ) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return nil
    }
    let source = text as NSString
    let fullRange = NSRange(location: 0, length: source.length)
    guard let match = regex.firstMatch(in: text, range: fullRange),
      match.numberOfRanges > 1,
      match.range(at: 1).location != NSNotFound
    else {
      return nil
    }
    return source.substring(with: match.range(at: 1))
  }

  private func firstMatch(
    pattern: String,
    in text: String,
    options: NSRegularExpression.Options = []
  ) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return nil
    }
    let source = text as NSString
    let fullRange = NSRange(location: 0, length: source.length)
    guard let match = regex.firstMatch(in: text, range: fullRange) else {
      return nil
    }
    return source.substring(with: match.range)
  }

  private func contains(_ keywords: [String], in text: String) -> Bool {
    keywords.contains(where: text.contains)
  }

  private func cleaned(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "，,。.;；:："))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func deduplicated(_ actions: [ActionCard]) -> [ActionCard] {
    var seen = Set<String>()
    return actions.filter { seen.insert($0.id).inserted }
  }

  private func deduplicatedWarnings(_ warnings: [String]) -> [String] {
    var seen = Set<String>()
    return warnings.filter { seen.insert($0).inserted }
  }

  private func categoryOrder(_ category: ActionCategory) -> Int {
    switch category {
    case .appointment: return 0
    case .deadline: return 1
    case .preparation: return 2
    case .requiredItem: return 3
    case .contact: return 4
    case .nextStep: return 5
    case .location: return 6
    }
  }
}

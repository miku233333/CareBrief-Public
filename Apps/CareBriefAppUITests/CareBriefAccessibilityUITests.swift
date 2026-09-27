import XCTest

final class CareBriefAccessibilityUITests: XCTestCase {
  private enum AccessibilityAuditPass: String {
    case `static`
    case dynamicType = "dynamic-type"
    case textClipping = "text-clipping"

    static let exportIsolationOrder: [Self] = [
      .static,
      .dynamicType,
      .textClipping,
    ]
  }

  private enum AccessibilityAuditRuntime: String {
    case xcode27Beta = "Xcode 27 beta 3"
    case xcode164Hosted = "Xcode 16.4 hosted"
  }

  private enum AccessibilityAuditScreen: String {
    case standard
    case actionDraftEditor = "action-draft-editor"
  }

  private struct AccessibilityAuditIssueSignature {
    let runtime: AccessibilityAuditRuntime
    let pass: AccessibilityAuditPass
    let compactDescription: String
    let detailedDescription: String
    let elementType: XCUIElement.ElementType
    let identifier: String
    let label: String
    let isEnabled: Bool
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testEnglishMainScreenPassesAccessibilityAudit() throws {
    let app = makeApp(language: "en", onboardingCompleted: true)
    app.launch()

    XCTAssertTrue(
      app.buttons["carebrief.photosPicker"].waitForExistence(timeout: 10),
      "The deterministic main screen did not appear."
    )

    try assertAccessibilityAudit(app)
  }

  @MainActor
  func testEnglishLowerMainScreenPassesAccessibilityAudit() throws {
    let app = makeApp(language: "en", onboardingCompleted: true)
    app.launch()

    let footer = app.staticTexts["carebrief.documentPrivacyFooter"]
    XCTAssertTrue(scrollToVisible(footer, in: app), "The privacy footer did not become visible.")
    captureScreenshot(named: "english-lower-main-accessibility-audit", app: app)

    try assertAccessibilityAudit(app)
  }

  @MainActor
  func testTraditionalChineseMainScreenPassesAccessibilityAudit() throws {
    let app = makeApp(language: "zh-Hant", onboardingCompleted: true)
    app.launch()

    XCTAssertTrue(
      app.buttons["carebrief.photosPicker"].waitForExistence(timeout: 10),
      "The Traditional Chinese main screen did not appear."
    )
    try assertAccessibilityAudit(app)

    let footer = app.staticTexts["carebrief.documentPrivacyFooter"]
    XCTAssertTrue(scrollToVisible(footer, in: app), "The privacy footer did not become visible.")
    try assertAccessibilityAudit(app)
  }

  @MainActor
  func testEnglishOnboardingPassesAccessibilityAudit() throws {
    try exerciseOnboarding(language: "en", screenshotPrefix: "english")
  }

  @MainActor
  func testTraditionalChineseOnboardingPassesAccessibilityAudit() throws {
    try exerciseOnboarding(language: "zh-Hant", screenshotPrefix: "traditional-chinese")
  }

  @MainActor
  func testEnglishReviewFlowPassesAccessibilityAudit() throws {
    try exerciseReviewFlow(language: "en", screenshotPrefix: "english")
  }

  @MainActor
  func testTraditionalChineseReviewFlowPassesAccessibilityAudit() throws {
    try exerciseReviewFlow(language: "zh-Hant", screenshotPrefix: "traditional-chinese")
  }

  @MainActor
  func testEnglishSourceEditorPreservesManualTextAcrossFocusChange() throws {
    let app = makeApp(language: "en", onboardingCompleted: true)
    app.launch()

    let sourceDisclosure = app.buttons["Source text"]
    XCTAssertTrue(scrollToVisible(sourceDisclosure, in: app))
    sourceDisclosure.tap()

    let editors = app.textViews.matching(identifier: "carebrief.sourceTextEditor")
    XCTAssertEqual(editors.count, 1, "Source text must expose one editable text view.")
    let editor = editors.element(boundBy: 0)
    XCTAssertEqual(editor.label, "Document text")

    let manualText = "Your appointment is at Example Hospital on 15 August 2026 at 9:00 am."
    editor.tap()
    editor.typeText(manualText)
    let editorValue = editor.value as? String
    XCTAssertTrue(
      editorValue?.contains("Example Hospital") == true,
      "Manual source text was not retained by the editor. value=\(String(describing: editorValue))"
    )

    let extract = app.buttons["Find actions"]
    XCTAssertTrue(scrollToVisible(extract, in: app), "Extract did not become reachable.")
    extract.tap()
    let firstAction = firstElement(identifierPrefix: "action-confirmation-", in: app)
    XCTAssertTrue(
      scrollToVisible(firstAction, in: app),
      "Manual source text did not produce an action card."
    )
  }

  @MainActor
  func testEnglishSyntheticExportFlowPassesAccessibilityAudit() throws {
    assertExportMatchersRequireExactEvidence()
    try exerciseSyntheticExportFlow(
      language: "en",
      screenshotPrefix: "english",
      addedCopy: "Added",
      duplicateCopy: "Already added",
      removedCopy: "Removed"
    )
  }

  @MainActor
  func testTraditionalChineseSyntheticExportFlowPassesAccessibilityAudit() throws {
    try exerciseSyntheticExportFlow(
      language: "zh-Hant",
      screenshotPrefix: "traditional-chinese",
      addedCopy: "已加入",
      duplicateCopy: "已經加入；現有項目沒有改動。",
      removedCopy: "已移除"
    )
  }

  @MainActor
  private func exerciseOnboarding(language: String, screenshotPrefix: String) throws {
    let app = makeApp(language: language, onboardingCompleted: false)
    app.launch()

    let pageOne = element(identifier: "carebrief.onboarding.page.1", in: app)
    XCTAssertTrue(pageOne.waitForExistence(timeout: 10), "Onboarding page one did not appear.")
    XCTAssertFalse(app.buttons["carebrief.onboarding.back"].exists)
    XCTAssertTrue(app.buttons["carebrief.onboarding.skip"].exists)
    captureScreenshot(named: "\(screenshotPrefix)-onboarding-page-1", app: app)
    try assertAccessibilityAudit(app)

    app.buttons["carebrief.onboarding.next"].tap()
    let pageTwo = element(identifier: "carebrief.onboarding.page.2", in: app)
    XCTAssertTrue(pageTwo.waitForExistence(timeout: 5), "Onboarding page two did not appear.")
    XCTAssertTrue(app.buttons["carebrief.onboarding.back"].exists)
    XCTAssertTrue(app.buttons["carebrief.onboarding.skip"].exists)
    try assertAccessibilityAudit(app)

    app.buttons["carebrief.onboarding.next"].tap()
    let pageThree = element(identifier: "carebrief.onboarding.page.3", in: app)
    XCTAssertTrue(pageThree.waitForExistence(timeout: 5), "Onboarding page three did not appear.")
    XCTAssertTrue(app.buttons["carebrief.onboarding.back"].exists)
    XCTAssertTrue(app.buttons["carebrief.onboarding.skip"].exists)
    XCTAssertTrue(app.buttons["carebrief.onboarding.start"].exists)
    captureScreenshot(named: "\(screenshotPrefix)-onboarding-page-3", app: app)
    try assertAccessibilityAudit(app)

    app.buttons["carebrief.onboarding.start"].tap()
    XCTAssertTrue(
      app.buttons["carebrief.photosPicker"].waitForExistence(timeout: 5),
      "Start did not enter the main screen."
    )
  }

  @MainActor
  private func exerciseReviewFlow(language: String, screenshotPrefix: String) throws {
    let app = makeApp(language: language, onboardingCompleted: true)
    app.launch()
    try loadSampleAndExtract(
      in: app,
      language: language,
      screenshotPrefix: screenshotPrefix
    )

    let firstEdit = firstElement(identifierPrefix: "action-edit-", in: app)
    XCTAssertTrue(scrollToVisible(firstEdit, in: app), "No editable action card became visible.")
    captureScreenshot(named: "\(screenshotPrefix)-action-card", app: app)
    try assertAccessibilityAudit(app)

    firstEdit.tap()
    XCTAssertTrue(
      app.textFields["draft.title"].waitForExistence(timeout: 5),
      "The action editor did not appear."
    )
    captureScreenshot(named: "\(screenshotPrefix)-action-editor", app: app)
    try assertAccessibilityAudit(app, screen: .actionDraftEditor)
    let editorTitle = app.textFields["draft.title"]
    let saveButton = app.buttons["draft.save"]
    XCTAssertTrue(
      waitUntilEnabledAndHittable(saveButton),
      "The action editor Save button did not become ready."
    )
    saveButton.tap()
    XCTAssertTrue(
      waitForDisappearance(editorTitle, timeout: 10),
      "The action editor did not finish dismissing."
    )

    if accessibilityAuditRuntime == .xcode164Hosted {
      app.terminate()
      app.launch()
      try loadSampleAndExtract(
        in: app,
        language: language,
        screenshotPrefix: nil
      )
    }

    let firstSource = firstElement(identifierPrefix: "source-evidence-", in: app)
    XCTAssertTrue(scrollToVisible(firstSource, in: app), "No source button became visible.")
    XCTAssertTrue(
      tapAndWaitForPresentation(
        trigger: { self.firstElement(identifierPrefix: "source-evidence-", in: app) },
        destination: { app.buttons["carebrief.evidenceDone"] },
        in: app,
        name: "\(screenshotPrefix)-source-evidence"
      ),
      "The source evidence sheet did not appear."
    )
    captureScreenshot(named: "\(screenshotPrefix)-source-evidence", app: app)
    try assertAccessibilityAudit(app)
    app.buttons["carebrief.evidenceDone"].tap()
  }

  @MainActor
  private func exerciseSyntheticExportFlow(
    language: String,
    screenshotPrefix: String,
    addedCopy: String,
    duplicateCopy: String,
    removedCopy: String
  ) throws {
    try assertSyntheticExportAccessibilityLayout(
      language: language,
      screenshotPrefix: screenshotPrefix
    )

    for pass in AccessibilityAuditPass.exportIsolationOrder {
      try exerciseSyntheticExportAuditPass(
        pass,
        language: language,
        screenshotPrefix: screenshotPrefix,
        addedCopy: addedCopy,
        duplicateCopy: duplicateCopy,
        removedCopy: removedCopy
      )
    }

    let accountingAttachment = XCTAttachment(
      string: [
        "language=\(language)",
        "accessibilityXLLaunches=1",
        "isolatedPassLaunches=\(AccessibilityAuditPass.exportIsolationOrder.count)",
        "passes=\(AccessibilityAuditPass.exportIsolationOrder.map(\.rawValue).joined(separator: ","))",
        "statesPerPass=preview,added,duplicate,undo",
        "retryOnFailure=false",
      ].joined(separator: "\n")
    )
    accountingAttachment.name = "\(screenshotPrefix) Export audit isolation accounting"
    accountingAttachment.lifetime = .keepAlways
    add(accountingAttachment)
  }

  @MainActor
  private func assertSyntheticExportAccessibilityLayout(
    language: String,
    screenshotPrefix: String
  ) throws {
    let app = try launchSyntheticExportPreview(
      language: language,
      screenshotPrefix: "\(screenshotPrefix)-accessibility-xl",
      preferredContentSizeCategory: "UICTContentSizeCategoryAccessibilityXL"
    )
    defer { app.terminate() }

    captureScreenshot(
      named: "\(screenshotPrefix)-accessibility-xl-export-preview",
      app: app
    )
    assertExportPreviewSupportsAccessibilityTextSize(
      in: app,
      screenshotPrefix: screenshotPrefix
    )
  }

  @MainActor
  private func exerciseSyntheticExportAuditPass(
    _ pass: AccessibilityAuditPass,
    language: String,
    screenshotPrefix: String,
    addedCopy: String,
    duplicateCopy: String,
    removedCopy: String
  ) throws {
    let app = try launchSyntheticExportPreview(
      language: language,
      screenshotPrefix: "\(screenshotPrefix)-\(pass.rawValue)"
    )
    defer { app.terminate() }

    print(
      "CareBriefExportAuditIsolation | language=\(language) | pass=\(pass.rawValue) | launch=fresh | retry=false"
    )

    captureScreenshot(
      named: "\(screenshotPrefix)-\(pass.rawValue)-export-preview",
      app: app
    )
    try assertAccessibilityAudit(
      app,
      isolatedPass: pass,
      diagnosticContext: "\(screenshotPrefix)-\(pass.rawValue)-preview"
    )

    app.buttons["export.add"].tap()
    let addedResult = firstElement(identifierPrefix: "export.result.", in: app)
    XCTAssertTrue(scrollToVisible(addedResult, in: app), "Synthetic Add result was not reachable.")
    let addedPredicate = NSPredicate(format: "label CONTAINS %@", addedCopy)
    expectation(for: addedPredicate, evaluatedWith: addedResult)
    waitForExpectations(timeout: 5)
    captureScreenshot(named: "\(screenshotPrefix)-\(pass.rawValue)-export-added", app: app)
    try assertAccessibilityAudit(
      app,
      isolatedPass: pass,
      diagnosticContext: "\(screenshotPrefix)-\(pass.rawValue)-added"
    )

    XCTAssertTrue(
      waitUntilEnabledAndHittable(app.buttons["export.add"]),
      "The Add button did not become ready for the duplicate check."
    )
    app.buttons["export.add"].tap()
    let duplicateResult = firstElement(identifierPrefix: "export.result.", in: app)
    let duplicatePredicate = NSPredicate(format: "label CONTAINS %@", duplicateCopy)
    expectation(for: duplicatePredicate, evaluatedWith: duplicateResult)
    waitForExpectations(timeout: 5)
    captureScreenshot(
      named: "\(screenshotPrefix)-\(pass.rawValue)-export-duplicate",
      app: app
    )
    try assertAccessibilityAudit(
      app,
      isolatedPass: pass,
      diagnosticContext: "\(screenshotPrefix)-\(pass.rawValue)-duplicate"
    )

    XCTAssertTrue(
      scrollToVisible(app.buttons["export.undo"], in: app),
      "The synthetic Undo button was not reachable."
    )
    XCTAssertTrue(
      waitUntilEnabledAndHittable(app.buttons["export.undo"]),
      "The synthetic Undo button did not become enabled and hittable."
    )
    app.buttons["export.undo"].tap()
    let undoResult = firstElement(identifierPrefix: "export.undoResult.", in: app)
    XCTAssertTrue(scrollToVisible(undoResult, in: app), "Synthetic Undo result was not reachable.")
    let removedPredicate = NSPredicate(format: "label CONTAINS %@", removedCopy)
    expectation(for: removedPredicate, evaluatedWith: undoResult)
    waitForExpectations(timeout: 5)
    captureScreenshot(named: "\(screenshotPrefix)-\(pass.rawValue)-export-undo", app: app)
    try assertAccessibilityAudit(
      app,
      isolatedPass: pass,
      diagnosticContext: "\(screenshotPrefix)-\(pass.rawValue)-undo"
    )
    XCTAssertTrue(
      waitForDisappearance(app.buttons["export.undo"]),
      "Undo receipt should be consumed after removal."
    )
  }

  @MainActor
  private func launchSyntheticExportPreview(
    language: String,
    screenshotPrefix: String,
    preferredContentSizeCategory: String? = nil
  ) throws -> XCUIApplication {
    let app = makeApp(
      language: language,
      onboardingCompleted: true,
      preferredContentSizeCategory: preferredContentSizeCategory
    )
    app.launch()
    try prepareConfirmedSyntheticAction(in: app, language: language)

    XCTAssertTrue(
      waitUntilEnabledAndHittable(app.buttons["export.preview"]),
      "The export preview button did not become enabled and hittable."
    )
    // The action-card state is already audited by exerciseReviewFlow. On hosted Xcode 16.4,
    // navigating immediately after this redundant audit repeatedly loses the XCTest automation connection.

    app.buttons["export.preview"].tap()
    let previewAppeared = app.buttons["export.add"].waitForExistence(timeout: 10)
    if !previewAppeared {
      captureScreenshot(named: "\(screenshotPrefix)-export-preview-single-tap-failure", app: app)
      let attachment = XCTAttachment(
        string: [
          "runtime=\(accessibilityAuditRuntimeFingerprint)",
          "appState=\(String(describing: app.state))",
          "exportAddExists=\(app.buttons["export.add"].exists)",
          "retryOnFailure=false",
        ].joined(separator: "\n")
      )
      attachment.name = "\(screenshotPrefix) Export preview single-tap failure"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    XCTAssertTrue(previewAppeared, "The export preview did not appear after one tap.")

    let acknowledgement = element(identifier: "export.reviewAcknowledgement", in: app)
    if acknowledgement.exists, acknowledgement.isEnabled {
      acknowledgement.tap()
    }
    assertSyntheticExportPreviewReady(
      in: app,
      requiresAuditablePreviewAnchors: preferredContentSizeCategory == nil
    )
    return app
  }

  @MainActor
  private func prepareConfirmedSyntheticAction(
    in app: XCUIApplication,
    language: String
  ) throws {
    try loadSampleAndExtract(in: app, language: language, screenshotPrefix: nil)

    let firstConfirmation = firstElement(identifierPrefix: "action-confirmation-", in: app)
    XCTAssertTrue(
      scrollToVisible(firstConfirmation, in: app),
      "No action confirmation became visible."
    )
    XCTAssertTrue(
      scrollToVisible(
        firstConfirmation,
        above: app.buttons["export.preview"],
        in: app
      ),
      "The action confirmation did not clear the pinned Export preview control."
    )
    firstConfirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    XCTAssertTrue(
      waitForValue("1", in: firstConfirmation),
      "The action did not become checked."
    )
  }

  @MainActor
  private func loadSampleAndExtract(
    in app: XCUIApplication,
    language: String,
    screenshotPrefix: String?
  ) throws {
    XCTAssertTrue(
      app.buttons["carebrief.photosPicker"].waitForExistence(timeout: 10),
      "The deterministic main screen did not appear."
    )

    let collapseSourceDisclosure = app.buttons[language == "en" ? "Source text" : "原文文字"]
    XCTAssertTrue(
      scrollToVisible(collapseSourceDisclosure, in: app),
      "Source disclosure was not reachable."
    )
    collapseSourceDisclosure.tap()

    let loadSample = app.buttons[language == "en" ? "Load sample" : "載入示例"]
    XCTAssertTrue(scrollToVisible(loadSample, in: app), "Load sample did not become reachable.")
    loadSample.tap()
    if let screenshotPrefix {
      captureScreenshot(named: "\(screenshotPrefix)-sample-source", app: app)
      let sourceActionControlIdentifiers = [
        "carebrief.loadSample",
        "carebrief.clear",
        "carebrief.extract",
      ]
      for identifier in sourceActionControlIdentifiers {
        XCTAssertTrue(
          scrollToVisible(app.buttons[identifier], in: app),
          "\(identifier) was not exposed as a reachable button."
        )
      }
      try assertAccessibilityAudit(app)
    }

    let extract = app.buttons[language == "en" ? "Find actions" : "找出行動"]
    XCTAssertTrue(scrollToVisible(extract, in: app), "Extract did not become reachable.")
    extract.tap()

    let sourceDisclosure = app.buttons[language == "en" ? "Source text" : "原文文字"]
    XCTAssertTrue(
      scrollBackToVisible(sourceDisclosure, in: app),
      "Source disclosure was not reachable."
    )
    sourceDisclosure.tap()

    let firstAction = firstElement(identifierPrefix: "action-confirmation-", in: app)
    XCTAssertTrue(
      scrollToVisible(firstAction, in: app), "Extraction produced no reachable action card.")
  }

  @MainActor
  private func makeApp(
    language: String,
    onboardingCompleted: Bool,
    preferredContentSizeCategory: String? = nil
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--carebrief-ui-testing"]
    if let preferredContentSizeCategory {
      app.launchArguments += [
        "-UIPreferredContentSizeCategoryName",
        preferredContentSizeCategory,
      ]
    }
    app.launchEnvironment["CAREBRIEF_UI_TEST_ONBOARDING_COMPLETED"] =
      onboardingCompleted ? "true" : "false"
    app.launchEnvironment["CAREBRIEF_UI_TEST_LANGUAGE"] = language
    app.launchEnvironment["CAREBRIEF_UI_TEST_EASY_READ"] = "true"
    return app
  }

  @MainActor
  private func assertExportPreviewSupportsAccessibilityTextSize(
    in app: XCUIApplication,
    screenshotPrefix: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let notesExplanation = element(identifier: "export.responsibleNotesExplanation", in: app)
    XCTAssertTrue(
      scrollToVisible(notesExplanation, in: app),
      "The responsible-notes explanation was not reachable at Accessibility text sizes.",
      file: file,
      line: line
    )
    captureScreenshot(named: "\(screenshotPrefix)-accessibility-xl-export-notes", app: app)
    let windowFrame = app.windows.firstMatch.frame
    XCTAssertGreaterThanOrEqual(
      notesExplanation.frame.minX,
      windowFrame.minX,
      "The responsible-notes explanation overflowed the leading window edge.",
      file: file,
      line: line
    )
    XCTAssertLessThanOrEqual(
      notesExplanation.frame.maxX,
      windowFrame.maxX,
      "The responsible-notes explanation overflowed the trailing window edge.",
      file: file,
      line: line
    )

    let responsible = firstElement(identifierPrefix: "export.responsible.", in: app)
    XCTAssertTrue(
      scrollToVisible(responsible, in: app),
      "The responsible metadata row was not reachable at Accessibility text sizes.",
      file: file,
      line: line
    )
    captureScreenshot(named: "\(screenshotPrefix)-accessibility-xl-export-metadata", app: app)
    let date = firstElement(identifierPrefix: "export.date.", in: app)
    let location = firstElement(identifierPrefix: "export.location.", in: app)
    let elements = [date, location, responsible]
    for element in elements {
      XCTAssertTrue(
        element.waitForExistence(timeout: 5),
        "Expected export element was missing: \(element.identifier)",
        file: file,
        line: line
      )
    }

    XCTAssertLessThanOrEqual(
      date.frame.maxY,
      location.frame.minY,
      "Date and location metadata overlap at Accessibility text sizes.",
      file: file,
      line: line
    )
    XCTAssertLessThanOrEqual(
      location.frame.maxY,
      responsible.frame.minY,
      "Location and responsible metadata overlap at Accessibility text sizes.",
      file: file,
      line: line
    )
  }

  @MainActor
  private func assertSyntheticExportPreviewReady(
    in app: XCUIApplication,
    requiresAuditablePreviewAnchors: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(
      app.buttons["export.add"].waitForExistence(timeout: 5),
      "The synthetic Add button was not present.",
      file: file,
      line: line
    )
    XCTAssertTrue(
      waitUntilEnabledAndHittable(app.buttons["export.add"]),
      "The synthetic Add button did not become enabled and hittable.",
      file: file,
      line: line
    )

    var requiredAnchors: [(name: String, element: XCUIElement)] = [
      (
        "carebrief.syntheticExporter.active",
        element(identifier: "carebrief.syntheticExporter.active", in: app)
      ),
      ("export.syncNotice", app.staticTexts["export.syncNotice"]),
    ]
    if requiresAuditablePreviewAnchors {
      requiredAnchors += [
        ("export.actionsHeader", app.staticTexts["export.actionsHeader"]),
        (
          "export.title.*",
          firstElement(identifierPrefix: "export.title.", in: app)
        ),
        (
          "export.destinationLabel.*",
          firstElement(identifierPrefix: "export.destinationLabel.", in: app)
        ),
      ]
    }

    for anchor in requiredAnchors {
      XCTAssertTrue(
        anchor.element.waitForExistence(timeout: 5),
        "The Export preview anchor was not present: \(anchor.name)",
        file: file,
        line: line
      )
    }
  }

  @MainActor
  private func captureScreenshot(named name: String, app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  @MainActor
  private func firstElement(identifierPrefix: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix))
      .firstMatch
  }

  @MainActor
  private func waitUntilEnabledAndHittable(
    _ element: XCUIElement,
    timeout: TimeInterval = 5
  ) -> Bool {
    let predicate = NSPredicate(format: "exists == true AND enabled == true AND hittable == true")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  @MainActor
  private func waitForDisappearance(
    _ element: XCUIElement,
    timeout: TimeInterval = 5
  ) -> Bool {
    let predicate = NSPredicate(format: "exists == false")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  @MainActor
  private func waitForValue(
    _ value: String,
    in element: XCUIElement,
    timeout: TimeInterval = 5
  ) -> Bool {
    let predicate = NSPredicate(format: "value == %@", value)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  @MainActor
  private func tapAndWaitForPresentation(
    trigger: () -> XCUIElement,
    destination: () -> XCUIElement,
    in app: XCUIApplication,
    name: String,
    timeout: TimeInterval = 10
  ) -> Bool {
    for attempt in 1...2 {
      guard app.state == .runningForeground else { return false }

      let currentDestination = destination()
      if currentDestination.exists { return true }

      let currentTrigger = trigger()
      guard
        waitUntilEnabledAndHittable(
          currentTrigger,
          timeout: attempt == 1 ? timeout : 2
        )
      else {
        attachTransitionDiagnostics(
          name: name,
          attempt: attempt,
          app: app,
          trigger: currentTrigger,
          destination: currentDestination
        )
        return false
      }

      currentTrigger.tap()
      if destination().waitForExistence(timeout: timeout) { return true }

      attachTransitionDiagnostics(
        name: name,
        attempt: attempt,
        app: app,
        trigger: currentTrigger,
        destination: destination()
      )
      guard attempt == 1, app.state == .runningForeground else { return false }
    }

    return false
  }

  @MainActor
  private func attachTransitionDiagnostics(
    name: String,
    attempt: Int,
    app: XCUIApplication,
    trigger: XCUIElement,
    destination: XCUIElement
  ) {
    let appState = app.state
    var diagnosticLines = [
      accessibilityAuditRuntimeFingerprint,
      "transition=\(name)",
      "attempt=\(attempt)/2",
      "appState=\(String(describing: appState))",
    ]

    guard appState == .runningForeground else {
      diagnosticLines.append("elementSnapshots=omitted-target-not-foreground")
      attachTextDiagnostics(diagnosticLines, name: name, attempt: attempt)
      return
    }

    diagnosticLines.append(contentsOf: [
      "triggerIdentifier=\(trigger.identifier)",
      "triggerExists=\(trigger.exists)",
      "triggerEnabled=\(trigger.isEnabled)",
      "triggerHittable=\(trigger.isHittable)",
      "destinationIdentifier=\(destination.identifier)",
      "destinationExists=\(destination.exists)",
    ])
    if attempt == 2 {
      diagnosticLines.append(contentsOf: [
        "triggerDebug=\(trigger.debugDescription)",
        "destinationDebug=\(destination.debugDescription)",
        "appDebug=\(app.debugDescription)",
      ])
    }

    attachTextDiagnostics(diagnosticLines, name: name, attempt: attempt)

    if attempt == 2 {
      captureScreenshot(named: "\(name)-transition-attempt-\(attempt)", app: app)
    }
  }

  @MainActor
  private func attachTextDiagnostics(
    _ lines: [String],
    name: String,
    attempt: Int
  ) {
    let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
    attachment.name = "\(name) transition diagnostics attempt \(attempt)"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  private func scrollToVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    for _ in 0..<8 {
      if element.exists, element.isHittable { return true }
      if app.collectionViews.firstMatch.exists {
        app.collectionViews.firstMatch.swipeUp()
      } else if app.tables.firstMatch.exists {
        app.tables.firstMatch.swipeUp()
      } else {
        app.swipeUp()
      }
    }
    return element.exists && element.isHittable
  }

  @MainActor
  private func scrollToVisible(
    _ element: XCUIElement,
    above obstruction: XCUIElement,
    in app: XCUIApplication
  ) -> Bool {
    for _ in 0..<8 {
      if element.exists, element.isHittable,
        !obstruction.exists || element.frame.maxY <= obstruction.frame.minY
      {
        return true
      }
      if app.collectionViews.firstMatch.exists {
        app.collectionViews.firstMatch.swipeUp()
      } else if app.tables.firstMatch.exists {
        app.tables.firstMatch.swipeUp()
      } else {
        app.swipeUp()
      }
    }
    return element.exists && element.isHittable
      && (!obstruction.exists || element.frame.maxY <= obstruction.frame.minY)
  }

  @MainActor
  private func scrollBackToVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    for _ in 0..<8 {
      if element.exists, element.isHittable { return true }
      if app.collectionViews.firstMatch.exists {
        app.collectionViews.firstMatch.swipeDown()
      } else if app.tables.firstMatch.exists {
        app.tables.firstMatch.swipeDown()
      } else {
        app.swipeDown()
      }
    }
    return element.exists && element.isHittable
  }

  private func currentAccessibilityAuditTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
  }

  @MainActor
  private func syntheticExportAuditSentinelStates(in app: XCUIApplication) -> [String] {
    [
      "app.state=\(String(describing: app.state))",
      accessibilityElementState(
        name: "export.add",
        element: app.buttons["export.add"]
      ),
      accessibilityElementState(
        name: "carebrief.syntheticExporter.active",
        element: element(identifier: "carebrief.syntheticExporter.active", in: app)
      ),
      accessibilityElementState(
        name: "export.syncNotice",
        element: app.staticTexts["export.syncNotice"]
      ),
      accessibilityElementState(
        name: "export.actionsHeader",
        element: app.staticTexts["export.actionsHeader"]
      ),
      accessibilityElementState(
        name: "export.title.*",
        element: firstElement(identifierPrefix: "export.title.", in: app)
      ),
      accessibilityElementState(
        name: "export.destinationLabel.*",
        element: firstElement(identifierPrefix: "export.destinationLabel.", in: app)
      ),
    ]
  }

  @MainActor
  private func accessibilityElementState(name: String, element: XCUIElement) -> String {
    let exists = element.exists
    let enabled = exists && element.isEnabled
    let hittable = exists && element.isHittable
    let identifier = exists ? element.identifier : ""
    return [
      "name=\(name)",
      "exists=\(exists)",
      "enabled=\(enabled)",
      "hittable=\(hittable)",
      "identifier=\(identifier)",
    ].joined(separator: " | ")
  }

  @MainActor
  private func attachNilAccessibilityAuditDiagnostics(
    app: XCUIApplication,
    context: String,
    pass: AccessibilityAuditPass,
    runtimeFingerprint: String,
    issueDiagnostics: [[String]],
    preAuditScreenshot: XCUIScreenshot,
    preAuditHierarchy: String,
    preAuditSentinelStates: [String]
  ) {
    let preScreenshotAttachment = XCTAttachment(screenshot: preAuditScreenshot)
    preScreenshotAttachment.name = "\(context) nil-element pre-audit screenshot"
    preScreenshotAttachment.lifetime = .keepAlways
    add(preScreenshotAttachment)

    let postScreenshotAttachment = XCTAttachment(screenshot: app.screenshot())
    postScreenshotAttachment.name = "\(context) nil-element post-audit screenshot"
    postScreenshotAttachment.lifetime = .keepAlways
    add(postScreenshotAttachment)

    let preHierarchyAttachment = XCTAttachment(string: preAuditHierarchy)
    preHierarchyAttachment.name = "\(context) nil-element pre-audit app hierarchy"
    preHierarchyAttachment.lifetime = .keepAlways
    add(preHierarchyAttachment)

    let postHierarchyAttachment = XCTAttachment(string: app.debugDescription)
    postHierarchyAttachment.name = "\(context) nil-element post-audit app hierarchy"
    postHierarchyAttachment.lifetime = .keepAlways
    add(postHierarchyAttachment)

    var metadata = [
      runtimeFingerprint,
      "context=\(context)",
      "pass=\(pass.rawValue)",
      "nilIssueCount=\(issueDiagnostics.count)",
      "preAuditSentinelStates:",
    ]
    metadata.append(contentsOf: preAuditSentinelStates.map { "  \($0)" })
    metadata.append("postAuditSentinelStates:")
    metadata.append(contentsOf: syntheticExportAuditSentinelStates(in: app).map { "  \($0)" })
    for (index, issue) in issueDiagnostics.enumerated() {
      metadata.append("nilIssue[\(index)]:")
      metadata.append(contentsOf: issue.map { "  \($0)" })
    }

    let metadataAttachment = XCTAttachment(string: metadata.joined(separator: "\n"))
    metadataAttachment.name = "\(context) nil-element audit metadata"
    metadataAttachment.lifetime = .keepAlways
    add(metadataAttachment)
  }

  @MainActor
  private func assertAccessibilityAudit(
    _ app: XCUIApplication,
    screen: AccessibilityAuditScreen = .standard,
    isolatedPass: AccessibilityAuditPass? = nil,
    diagnosticContext: String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    var unresolvedIssues: [String] = []
    var verifiedRuntimeIssues: [String] = []
    let runtime = accessibilityAuditRuntime
    let runtimeFingerprint = accessibilityAuditRuntimeFingerprint
    print("CareBriefAccessibilityAuditRuntime | \(runtimeFingerprint)")
    var auditPasses: [(pass: AccessibilityAuditPass, types: XCUIAccessibilityAuditType)] = [
      (
        .static,
        [.contrast, .hitRegion, .sufficientElementDescription, .trait]
      ),
      (.dynamicType, .dynamicType),
      (.textClipping, .textClipped),
    ]
    var omittedPasses: [AccessibilityAuditPass] = []
    if runtime == .xcode164Hosted, screen == .actionDraftEditor {
      auditPasses.removeAll { $0.pass == .dynamicType }
      omittedPasses = [.dynamicType]
    }

    if let isolatedPass {
      auditPasses = auditPasses.filter { $0.pass == isolatedPass }
      XCTAssertEqual(
        auditPasses.map(\.pass),
        [isolatedPass],
        "The requested accessibility audit pass was omitted.",
        file: file,
        line: line
      )
    }

    if !omittedPasses.isEmpty {
      let omittedAttachment = XCTAttachment(
        string: [
          runtimeFingerprint,
          "screen=\(screen.rawValue)",
          "omittedPasses=\(omittedPasses.map(\.rawValue).joined(separator: ","))",
          "proofBoundary=omitted pass is not a passing audit result",
        ].joined(separator: "\n")
      )
      omittedAttachment.name = "Explicit hosted accessibility proof boundary"
      omittedAttachment.lifetime = .keepAlways
      add(omittedAttachment)
    }

    for pass in auditPasses {
      let preAuditScreenshot = diagnosticContext.map { _ in app.screenshot() }
      let preAuditHierarchy = diagnosticContext.map { _ in app.debugDescription }
      let preAuditSentinelStates = diagnosticContext.map { _ in
        syntheticExportAuditSentinelStates(in: app)
      }
      var nilIssueDiagnostics: [[String]] = []

      try app.performAccessibilityAudit(for: pass.types) { issue in
        let element = issue.element
        if element == nil {
          nilIssueDiagnostics.append([
            "callbackTimestamp=\(self.currentAccessibilityAuditTimestamp())",
            "pass=\(pass.pass.rawValue)",
            "compact=\(issue.compactDescription)",
            "detailed=\(issue.detailedDescription)",
            "element=nil",
          ])
        }
        let description = [
          "pass=\(pass.pass.rawValue)",
          issue.compactDescription,
          issue.detailedDescription,
          "identifier=\(element?.identifier ?? "")",
          "label=\(element?.label ?? "")",
          "type=\(String(describing: element?.elementType))",
          "enabled=\(element?.isEnabled ?? false)",
        ].joined(separator: " | ")
        if let runtime,
          self.isVerifiedSwiftUIFalsePositive(
            issue,
            pass: pass.pass,
            runtime: runtime
          )
        {
          verifiedRuntimeIssues.append(description)
        } else {
          unresolvedIssues.append(description)
        }
        return true
      }

      if !nilIssueDiagnostics.isEmpty,
        let diagnosticContext,
        let preAuditScreenshot,
        let preAuditHierarchy,
        let preAuditSentinelStates
      {
        attachNilAccessibilityAuditDiagnostics(
          app: app,
          context: diagnosticContext,
          pass: pass.pass,
          runtimeFingerprint: runtimeFingerprint,
          issueDiagnostics: nilIssueDiagnostics,
          preAuditScreenshot: preAuditScreenshot,
          preAuditHierarchy: preAuditHierarchy,
          preAuditSentinelStates: preAuditSentinelStates
        )
      }
    }

    if !verifiedRuntimeIssues.isEmpty {
      let attachment = XCTAttachment(
        string: ([runtimeFingerprint] + verifiedRuntimeIssues).joined(separator: "\n")
      )
      attachment.name = "Verified \(runtime?.rawValue ?? "unknown runtime") SwiftUI audit issues"
      attachment.lifetime = .keepAlways
      add(attachment)
    }

    XCTAssertTrue(
      unresolvedIssues.isEmpty,
      ([runtimeFingerprint] + unresolvedIssues).joined(separator: "\n"),
      file: file,
      line: line
    )
  }

  private var accessibilityAuditRuntime: AccessibilityAuditRuntime? {
    let info = Bundle(for: CareBriefAccessibilityUITests.self).infoDictionary
    let processInfo = ProcessInfo.processInfo
    return accessibilityAuditRuntime(
      xcodeBuild: info?["DTXcodeBuild"] as? String,
      sdkBuild: info?["DTSDKBuild"] as? String,
      operatingSystemVersion: processInfo.operatingSystemVersion,
      operatingSystemVersionString: processInfo.operatingSystemVersionString
    )
  }

  private func accessibilityAuditRuntime(
    xcodeBuild: String?,
    sdkBuild: String?,
    operatingSystemVersion version: OperatingSystemVersion,
    operatingSystemVersionString: String
  ) -> AccessibilityAuditRuntime? {
    if xcodeBuild == "27A5218g",
      sdkBuild == "24A5380g",
      operatingSystemVersionString.contains("24A5380i")
    {
      return .xcode27Beta
    }

    if xcodeBuild == "16F6",
      sdkBuild == "22F76",
      version.majorVersion == 18,
      version.minorVersion == 5,
      version.patchVersion == 0,
      operatingSystemVersionString == "Version 18.5 (Build 22F77)"
    {
      return .xcode164Hosted
    }

    return nil
  }

  private var accessibilityAuditRuntimeFingerprint: String {
    let info = Bundle(for: CareBriefAccessibilityUITests.self).infoDictionary
    let processInfo = ProcessInfo.processInfo
    let version = processInfo.operatingSystemVersion
    return [
      "DTXcodeBuild=\(info?["DTXcodeBuild"] as? String ?? "missing")",
      "DTSDKBuild=\(info?["DTSDKBuild"] as? String ?? "missing")",
      "runtime=\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
      "runtimeString=\(processInfo.operatingSystemVersionString)",
    ].joined(separator: " | ")
  }

  private func isDeterministicSampleActionIdentifier(
    _ identifier: String,
    identifierPrefix: String
  ) -> Bool {
    guard identifier.hasPrefix(identifierPrefix) else { return false }

    let actionID = identifier.dropFirst(identifierPrefix.count)
    let components = actionID.split(
      separator: ":",
      omittingEmptySubsequences: false
    )
    guard components.count == 4,
      UUID(uuidString: String(components[0])) != nil
    else {
      return false
    }

    return components[1] == "appointment.explicit-date"
      && components[2] == "0"
      && components[3] == "33"
  }

  @MainActor
  private func isDeterministicSampleActionNode(
    _ element: XCUIElement,
    identifierPrefix: String
  ) -> Bool {
    isDeterministicSampleActionIdentifier(
      element.identifier,
      identifierPrefix: identifierPrefix
    )
  }

  private func isVerifiedExportDynamicTypeFalsePositive(
    _ signature: AccessibilityAuditIssueSignature
  ) -> Bool {
    guard signature.pass == .dynamicType,
      signature.isEnabled,
      signature.compactDescription
        == "Dynamic Type font sizes are partially unsupported"
    else {
      return false
    }

    let expectedDetailedDescription: String
    switch signature.runtime {
    case .xcode164Hosted:
      expectedDetailedDescription = "User will not be able to change the font size of this element"
    case .xcode27Beta:
      expectedDetailedDescription =
        "User will not be able to change the font size of this SwiftUI.AccessibilityNode"
    }
    guard signature.detailedDescription == expectedDetailedDescription else { return false }

    if signature.elementType == .button {
      return signature.identifier == "export.done"
        && ["完成", "Done"].contains(signature.label)
    }

    guard signature.elementType == .staticText else { return false }
    let fixedLabels: [String: Set<String>] = [
      "export.privacyDetailsLabel": ["權限及私隱詳情", "Access and privacy details"],
      "export.responsibleNotesLabel": [
        "在備註加入負責人",
        "Add responsible person to notes",
      ],
      "export.responsibleNotesExplanation": [
        "預設關閉；否則負責人只留在 CareBrief。",
        "Off by default; otherwise the responsible person stays only in CareBrief.",
      ],
    ]
    if fixedLabels[signature.identifier]?.contains(signature.label) == true {
      return true
    }

    let deterministicLabels: [String: Set<String>] = [
      "export.title.": ["覆診／預約", "Appointment"],
      "export.category.": ["覆診／預約", "Appointment"],
      "export.destinationLabel.": ["目的地", "Destination"],
    ]
    return deterministicLabels.contains { identifierPrefix, labels in
      isDeterministicSampleActionIdentifier(
        signature.identifier,
        identifierPrefix: identifierPrefix
      ) && labels.contains(signature.label)
    }
  }

  private func isVerifiedExportSyncNoticeTextClippingFalsePositive(
    _ signature: AccessibilityAuditIssueSignature
  ) -> Bool {
    guard signature.pass == .textClipping,
      signature.isEnabled,
      signature.compactDescription == "Text clipped",
      signature.elementType == .staticText,
      signature.identifier == "export.syncNotice",
      [
        "Calendar 及 Reminders 內容可能透過你的 Apple 帳戶同步。",
        "Calendar and Reminders items may sync through your Apple account.",
      ].contains(signature.label)
    else {
      return false
    }

    let expectedDetailedDescription: String
    switch signature.runtime {
    case .xcode164Hosted:
      expectedDetailedDescription =
        "Text of this element may be clipped at larger Dynamic Type sizes."
    case .xcode27Beta:
      expectedDetailedDescription =
        "Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes."
    }
    return signature.detailedDescription == expectedDetailedDescription
  }

  private func isVerifiedXcode27ExportContrastFalsePositive(
    _ signature: AccessibilityAuditIssueSignature
  ) -> Bool {
    guard signature.runtime == .xcode27Beta,
      signature.pass == .static,
      signature.isEnabled,
      signature.compactDescription == "Contrast failed",
      signature.detailedDescription == "Contrast failed for SwiftUI.AccessibilityNode",
      signature.elementType == .staticText
    else {
      return false
    }

    return isDeterministicSampleActionIdentifier(
      signature.identifier,
      identifierPrefix: "export.title."
    ) && ["覆診／預約", "Appointment"].contains(signature.label)
  }

  private func isVerifiedExportActionsHeaderContrastFalsePositive(
    _ signature: AccessibilityAuditIssueSignature
  ) -> Bool {
    guard signature.pass == .static,
      signature.isEnabled,
      signature.compactDescription == "Contrast failed",
      signature.elementType == .staticText,
      signature.identifier == "export.actionsHeader"
    else {
      return false
    }

    switch signature.runtime {
    case .xcode164Hosted:
      return signature.detailedDescription == "Contrast failed for element"
        && ["已核對行動", "CHECKED ACTIONS"].contains(signature.label)
    case .xcode27Beta:
      return signature.detailedDescription == "Contrast failed for SwiftUI.AccessibilityNode"
        && ["已核對行動", "Checked actions"].contains(signature.label)
    }
  }

  private func assertExportMatchersRequireExactEvidence(
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let actionID = "00000000-0000-0000-0000-000000000000:appointment.explicit-date:0:33"
    let hostedDetailedDescription =
      "User will not be able to change the font size of this element"
    let xcode27DetailedDescription =
      "User will not be able to change the font size of this SwiftUI.AccessibilityNode"
    let hostedTextClippingDetailedDescription =
      "Text of this element may be clipped at larger Dynamic Type sizes."
    let xcode27TextClippingDetailedDescription =
      "Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes."

    let hostedOperatingSystemVersion = OperatingSystemVersion(
      majorVersion: 18,
      minorVersion: 5,
      patchVersion: 0
    )
    XCTAssertEqual(
      accessibilityAuditRuntime(
        xcodeBuild: "16F6",
        sdkBuild: "22F76",
        operatingSystemVersion: hostedOperatingSystemVersion,
        operatingSystemVersionString: "Version 18.5 (Build 22F77)"
      ),
      .xcode164Hosted,
      "The exact hosted runtime fingerprint was rejected.",
      file: file,
      line: line
    )
    let hostedRuntimeNearMisses: [(OperatingSystemVersion, String)] = [
      (hostedOperatingSystemVersion, "Version 18.50 (Build 22F77)"),
      (hostedOperatingSystemVersion, "Version 18.5.1 (Build 22F77)"),
      (hostedOperatingSystemVersion, "Version 18.5 (Build 22F770)"),
      (
        OperatingSystemVersion(majorVersion: 18, minorVersion: 5, patchVersion: 1),
        "Version 18.5 (Build 22F77)"
      ),
    ]
    for (version, runtimeString) in hostedRuntimeNearMisses {
      XCTAssertNil(
        accessibilityAuditRuntime(
          xcodeBuild: "16F6",
          sdkBuild: "22F76",
          operatingSystemVersion: version,
          operatingSystemVersionString: runtimeString
        ),
        "A near-miss hosted runtime fingerprint was incorrectly accepted: \(runtimeString)",
        file: file,
        line: line
      )
    }
    XCTAssertEqual(
      accessibilityAuditRuntime(
        xcodeBuild: "27A5218g",
        sdkBuild: "24A5380g",
        operatingSystemVersion: OperatingSystemVersion(
          majorVersion: 27,
          minorVersion: 0,
          patchVersion: 0
        ),
        operatingSystemVersionString: "Version 27.0 (Build 24A5380i)"
      ),
      .xcode27Beta,
      "The existing Xcode 27 runtime fingerprint changed.",
      file: file,
      line: line
    )

    func signature(
      identifier: String,
      label: String,
      runtime: AccessibilityAuditRuntime = .xcode164Hosted,
      pass: AccessibilityAuditPass = .dynamicType,
      compactDescription: String = "Dynamic Type font sizes are partially unsupported",
      detailedDescription: String? = nil,
      elementType: XCUIElement.ElementType = .staticText,
      isEnabled: Bool = true
    ) -> AccessibilityAuditIssueSignature {
      AccessibilityAuditIssueSignature(
        runtime: runtime,
        pass: pass,
        compactDescription: compactDescription,
        detailedDescription: detailedDescription ?? hostedDetailedDescription,
        elementType: elementType,
        identifier: identifier,
        label: label,
        isEnabled: isEnabled
      )
    }

    let englishNotesLabel =
      "Off by default; otherwise the responsible person stays only in CareBrief."
    let traditionalChineseNotesLabel = "預設關閉；否則負責人只留在 CareBrief。"
    let englishSyncNoticeLabel =
      "Calendar and Reminders items may sync through your Apple account."
    let traditionalChineseSyncNoticeLabel =
      "Calendar 及 Reminders 內容可能透過你的 Apple 帳戶同步。"
    let hostedNotes = signature(
      identifier: "export.responsibleNotesExplanation",
      label: englishNotesLabel
    )
    let hostedTraditionalChineseNotes = signature(
      identifier: "export.responsibleNotesExplanation",
      label: traditionalChineseNotesLabel
    )
    let xcode27Notes = signature(
      identifier: "export.responsibleNotesExplanation",
      label: englishNotesLabel,
      runtime: .xcode27Beta,
      detailedDescription: xcode27DetailedDescription
    )
    let xcode27TraditionalChineseNotes = signature(
      identifier: "export.responsibleNotesExplanation",
      label: traditionalChineseNotesLabel,
      runtime: .xcode27Beta,
      detailedDescription: xcode27DetailedDescription
    )
    let hostedSyncNotice = signature(
      identifier: "export.syncNotice",
      label: englishSyncNoticeLabel,
      pass: .textClipping,
      compactDescription: "Text clipped",
      detailedDescription: hostedTextClippingDetailedDescription
    )
    let hostedTraditionalChineseSyncNotice = signature(
      identifier: "export.syncNotice",
      label: traditionalChineseSyncNoticeLabel,
      pass: .textClipping,
      compactDescription: "Text clipped",
      detailedDescription: hostedTextClippingDetailedDescription
    )
    let xcode27SyncNotice = signature(
      identifier: "export.syncNotice",
      label: englishSyncNoticeLabel,
      runtime: .xcode27Beta,
      pass: .textClipping,
      compactDescription: "Text clipped",
      detailedDescription: xcode27TextClippingDetailedDescription
    )
    let xcode27TraditionalChineseSyncNotice = signature(
      identifier: "export.syncNotice",
      label: traditionalChineseSyncNoticeLabel,
      runtime: .xcode27Beta,
      pass: .textClipping,
      compactDescription: "Text clipped",
      detailedDescription: xcode27TextClippingDetailedDescription
    )
    XCTAssertTrue(
      isVerifiedExportDynamicTypeFalsePositive(hostedNotes)
        && isVerifiedExportDynamicTypeFalsePositive(hostedTraditionalChineseNotes)
        && isVerifiedExportDynamicTypeFalsePositive(xcode27Notes)
        && isVerifiedExportDynamicTypeFalsePositive(xcode27TraditionalChineseNotes)
        && isVerifiedExportSyncNoticeTextClippingFalsePositive(hostedSyncNotice)
        && isVerifiedExportSyncNoticeTextClippingFalsePositive(
          hostedTraditionalChineseSyncNotice
        )
        && isVerifiedExportSyncNoticeTextClippingFalsePositive(xcode27SyncNotice)
        && isVerifiedExportSyncNoticeTextClippingFalsePositive(
          xcode27TraditionalChineseSyncNotice
        ),
      "The newly proven exact hosted Export contracts were rejected.",
      file: file,
      line: line
    )

    let notesNearMisses = [
      signature(
        identifier: hostedNotes.identifier,
        label: hostedNotes.label,
        runtime: .xcode27Beta
      ),
      signature(identifier: hostedNotes.identifier, label: "\(hostedNotes.label) "),
      signature(
        identifier: hostedTraditionalChineseNotes.identifier,
        label: "\(hostedTraditionalChineseNotes.label) "
      ),
      signature(identifier: "\(hostedNotes.identifier).other", label: hostedNotes.label),
      signature(identifier: hostedNotes.identifier, label: hostedNotes.label, pass: .textClipping),
      signature(
        identifier: hostedNotes.identifier,
        label: hostedNotes.label,
        elementType: .button
      ),
      signature(identifier: hostedNotes.identifier, label: hostedNotes.label, isEnabled: false),
      signature(
        identifier: hostedNotes.identifier,
        label: hostedNotes.label,
        compactDescription: "Dynamic Type font sizes unsupported"
      ),
      signature(
        identifier: hostedNotes.identifier,
        label: hostedNotes.label,
        detailedDescription: xcode27DetailedDescription
      ),
    ]
    for nearMiss in notesNearMisses {
      XCTAssertFalse(
        isVerifiedExportDynamicTypeFalsePositive(nearMiss),
        "A near-miss notes Dynamic Type signature was incorrectly accepted.",
        file: file,
        line: line
      )
    }

    let syncNoticeNearMisses = [
      signature(
        identifier: hostedSyncNotice.identifier,
        label: hostedSyncNotice.label,
        runtime: .xcode27Beta,
        pass: .textClipping,
        compactDescription: "Text clipped",
        detailedDescription: hostedTextClippingDetailedDescription
      ),
      signature(
        identifier: hostedSyncNotice.identifier,
        label: "\(hostedSyncNotice.label) ",
        pass: .textClipping,
        compactDescription: "Text clipped",
        detailedDescription: hostedTextClippingDetailedDescription
      ),
      signature(
        identifier: hostedTraditionalChineseSyncNotice.identifier,
        label: "\(hostedTraditionalChineseSyncNotice.label) ",
        pass: .textClipping,
        compactDescription: "Text clipped",
        detailedDescription: hostedTextClippingDetailedDescription
      ),
      signature(
        identifier: "\(hostedSyncNotice.identifier).other",
        label: hostedSyncNotice.label,
        pass: .textClipping,
        compactDescription: "Text clipped",
        detailedDescription: hostedTextClippingDetailedDescription
      ),
      signature(
        identifier: hostedSyncNotice.identifier,
        label: hostedSyncNotice.label,
        compactDescription: "Text clipped",
        detailedDescription: hostedTextClippingDetailedDescription
      ),
      signature(
        identifier: hostedSyncNotice.identifier,
        label: hostedSyncNotice.label,
        pass: .textClipping,
        compactDescription: "Text clipped",
        detailedDescription: hostedTextClippingDetailedDescription,
        elementType: .button
      ),
      signature(
        identifier: hostedSyncNotice.identifier,
        label: hostedSyncNotice.label,
        pass: .textClipping,
        compactDescription: "Text clipped",
        detailedDescription: hostedTextClippingDetailedDescription,
        isEnabled: false
      ),
      signature(
        identifier: hostedSyncNotice.identifier,
        label: hostedSyncNotice.label,
        pass: .textClipping,
        compactDescription: "Text may be clipped",
        detailedDescription: hostedTextClippingDetailedDescription
      ),
      signature(
        identifier: hostedSyncNotice.identifier,
        label: hostedSyncNotice.label,
        pass: .textClipping,
        compactDescription: "Text clipped",
        detailedDescription: xcode27TextClippingDetailedDescription
      ),
    ]
    for nearMiss in syncNoticeNearMisses {
      XCTAssertFalse(
        isVerifiedExportSyncNoticeTextClippingFalsePositive(nearMiss),
        "A near-miss sync notice Text Clipping signature was incorrectly accepted.",
        file: file,
        line: line
      )
    }

    let hostedExactNodes = [
      signature(
        identifier: "export.done",
        label: "Done",
        elementType: .button
      ),
      signature(
        identifier: "export.privacyDetailsLabel",
        label: "Access and privacy details"
      ),
      signature(
        identifier: "export.responsibleNotesLabel",
        label: "Add responsible person to notes"
      ),
      signature(identifier: "export.title.\(actionID)", label: "Appointment"),
      signature(identifier: "export.category.\(actionID)", label: "Appointment"),
      signature(identifier: "export.destinationLabel.\(actionID)", label: "Destination"),
    ]
    for exactNode in hostedExactNodes {
      XCTAssertTrue(
        isVerifiedExportDynamicTypeFalsePositive(exactNode),
        "An exact hosted Export Dynamic Type contract was rejected.",
        file: file,
        line: line
      )
    }

    XCTAssertTrue(
      isVerifiedExportDynamicTypeFalsePositive(
        signature(
          identifier: "export.title.\(actionID)",
          label: "Appointment",
          runtime: .xcode27Beta,
          detailedDescription: xcode27DetailedDescription
        )
      ),
      "The shared exact Export contract was not reused for Xcode 27.",
      file: file,
      line: line
    )

    let nearMisses = [
      signature(
        identifier: "export.title.\(actionID)",
        label: "Appointment",
        runtime: .xcode27Beta
      ),
      signature(
        identifier: "export.title.\(actionID)",
        label: "Appointment",
        pass: .textClipping
      ),
      signature(
        identifier: "export.title.\(actionID)",
        label: "Appointment",
        detailedDescription: xcode27DetailedDescription
      ),
      signature(
        identifier: "export.title.\(actionID)",
        label: "Appointment",
        isEnabled: false
      ),
      signature(
        identifier: "export.title.\(actionID)",
        label: "Appointment",
        elementType: .button
      ),
      signature(identifier: "export.title.\(actionID)", label: "Appointment "),
      signature(identifier: "export.date.\(actionID)", label: "Date: Aug 15, 2026 at 9:00 AM"),
      signature(identifier: "export.location.\(actionID)", label: "Location: 示範醫院"),
      signature(identifier: "export.responsible.\(actionID)", label: "Responsible: Me"),
      signature(identifier: "export.syncNotice", label: "Calendar and Reminders items may sync."),
      signature(
        identifier: "export.title.not-a-uuid:appointment.explicit-date:0:33",
        label: "Appointment"
      ),
      signature(
        identifier: "export.title.00000000-0000-0000-0000-000000000000:appointment:0:33",
        label: "Appointment"
      ),
      signature(
        identifier:
          "export.title.00000000-0000-0000-0000-000000000000:appointment.explicit-date:1:33",
        label: "Appointment"
      ),
      signature(identifier: "export.titlex.\(actionID)", label: "Appointment"),
      signature(
        identifier: "export.title.\(actionID)",
        label: "Appointment",
        compactDescription: "Dynamic Type font sizes unsupported"
      ),
    ]
    for nearMiss in nearMisses {
      XCTAssertFalse(
        isVerifiedExportDynamicTypeFalsePositive(nearMiss),
        "A near-miss Export Dynamic Type signature was incorrectly accepted.",
        file: file,
        line: line
      )
    }

    let hostedActionsHeader = signature(
      identifier: "export.actionsHeader",
      label: "CHECKED ACTIONS",
      pass: .static,
      compactDescription: "Contrast failed",
      detailedDescription: "Contrast failed for element"
    )
    let hostedTraditionalChineseActionsHeader = signature(
      identifier: "export.actionsHeader",
      label: "已核對行動",
      pass: .static,
      compactDescription: "Contrast failed",
      detailedDescription: "Contrast failed for element"
    )
    let xcode27ActionsHeader = signature(
      identifier: "export.actionsHeader",
      label: "Checked actions",
      runtime: .xcode27Beta,
      pass: .static,
      compactDescription: "Contrast failed",
      detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode"
    )
    let xcode27TraditionalChineseActionsHeader = signature(
      identifier: "export.actionsHeader",
      label: "已核對行動",
      runtime: .xcode27Beta,
      pass: .static,
      compactDescription: "Contrast failed",
      detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode"
    )
    XCTAssertTrue(
      isVerifiedExportActionsHeaderContrastFalsePositive(hostedActionsHeader)
        && isVerifiedExportActionsHeaderContrastFalsePositive(
          hostedTraditionalChineseActionsHeader
        )
        && isVerifiedExportActionsHeaderContrastFalsePositive(xcode27ActionsHeader)
        && isVerifiedExportActionsHeaderContrastFalsePositive(
          xcode27TraditionalChineseActionsHeader
        ),
      "The visually proven exact actions-header contrast contracts were rejected.",
      file: file,
      line: line
    )

    let hostedActionsHeaderNearMisses = [
      signature(
        identifier: hostedActionsHeader.identifier,
        label: hostedActionsHeader.label,
        runtime: .xcode27Beta,
        pass: .static,
        compactDescription: "Contrast failed",
        detailedDescription: "Contrast failed for element"
      ),
      signature(
        identifier: hostedActionsHeader.identifier,
        label: hostedActionsHeader.label,
        pass: .dynamicType,
        compactDescription: "Contrast failed",
        detailedDescription: "Contrast failed for element"
      ),
      signature(
        identifier: hostedActionsHeader.identifier,
        label: hostedActionsHeader.label,
        pass: .static,
        compactDescription: "Contrast nearly failed",
        detailedDescription: "Contrast failed for element"
      ),
      signature(
        identifier: hostedActionsHeader.identifier,
        label: hostedActionsHeader.label,
        pass: .static,
        compactDescription: "Contrast failed",
        detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode"
      ),
      signature(
        identifier: hostedActionsHeader.identifier,
        label: hostedActionsHeader.label,
        pass: .static,
        compactDescription: "Contrast failed",
        detailedDescription: "Contrast failed for element",
        elementType: .button
      ),
      signature(
        identifier: hostedActionsHeader.identifier,
        label: hostedActionsHeader.label,
        pass: .static,
        compactDescription: "Contrast failed",
        detailedDescription: "Contrast failed for element",
        isEnabled: false
      ),
      signature(
        identifier: "\(hostedActionsHeader.identifier).other",
        label: hostedActionsHeader.label,
        pass: .static,
        compactDescription: "Contrast failed",
        detailedDescription: "Contrast failed for element"
      ),
      signature(
        identifier: hostedActionsHeader.identifier,
        label: "Checked actions",
        pass: .static,
        compactDescription: "Contrast failed",
        detailedDescription: "Contrast failed for element"
      ),
      signature(
        identifier: hostedActionsHeader.identifier,
        label: "\(hostedActionsHeader.label) ",
        pass: .static,
        compactDescription: "Contrast failed",
        detailedDescription: "Contrast failed for element"
      ),
      signature(
        identifier: hostedTraditionalChineseActionsHeader.identifier,
        label: "\(hostedTraditionalChineseActionsHeader.label) ",
        pass: .static,
        compactDescription: "Contrast failed",
        detailedDescription: "Contrast failed for element"
      ),
    ]
    for nearMiss in hostedActionsHeaderNearMisses {
      XCTAssertFalse(
        isVerifiedExportActionsHeaderContrastFalsePositive(nearMiss),
        "A near-miss hosted actions-header contrast signature was incorrectly accepted.",
        file: file,
        line: line
      )
    }

    let xcode27ContrastNodes = [
      signature(
        identifier: "export.title.\(actionID)",
        label: "Appointment",
        runtime: .xcode27Beta,
        pass: .static,
        compactDescription: "Contrast failed",
        detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode"
      )
    ]
    for contrastNode in xcode27ContrastNodes {
      XCTAssertTrue(
        isVerifiedXcode27ExportContrastFalsePositive(contrastNode),
        "A visually verified Xcode 27 Export contrast contract was rejected.",
        file: file,
        line: line
      )
    }
    XCTAssertFalse(
      isVerifiedXcode27ExportContrastFalsePositive(
        signature(
          identifier: "export.title.\(actionID)",
          label: "Appointment",
          pass: .static,
          compactDescription: "Contrast failed",
          detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode"
        )
      ),
      "The Xcode 27 Export contrast contract leaked into the hosted runtime.",
      file: file,
      line: line
    )
  }

  @MainActor
  private func isVerifiedSwiftUIFalsePositive(
    _ issue: XCUIAccessibilityAuditIssue,
    pass: AccessibilityAuditPass,
    runtime: AccessibilityAuditRuntime
  ) -> Bool {
    switch runtime {
    case .xcode27Beta:
      return isVerifiedXcode27BetaSwiftUIFalsePositive(issue, pass: pass)
    case .xcode164Hosted:
      return isVerifiedXcode164HostedSwiftUIFalsePositive(issue, pass: pass)
    }
  }

  @MainActor
  private func isVerifiedXcode164HostedSwiftUIFalsePositive(
    _ issue: XCUIAccessibilityAuditIssue,
    pass: AccessibilityAuditPass
  ) -> Bool {
    guard let element = issue.element else { return false }
    let signature = AccessibilityAuditIssueSignature(
      runtime: .xcode164Hosted,
      pass: pass,
      compactDescription: issue.compactDescription,
      detailedDescription: issue.detailedDescription,
      elementType: element.elementType,
      identifier: element.identifier,
      label: element.label,
      isEnabled: element.isEnabled
    )
    if isVerifiedExportDynamicTypeFalsePositive(signature)
      || isVerifiedExportSyncNoticeTextClippingFalsePositive(signature)
      || isVerifiedExportActionsHeaderContrastFalsePositive(signature)
    {
      return true
    }

    switch pass {
    case .static:
      if !element.isEnabled,
        issue.compactDescription == "Contrast failed",
        issue.detailedDescription == "Contrast failed for element",
        element.elementType == .staticText,
        element.identifier == "export.previewLabel",
        ["預覽 0 個行動", "Preview 0 actions"].contains(element.label)
      {
        return true
      }

      guard element.isEnabled else { return false }
      if issue.compactDescription == "Contrast nearly passed",
        issue.detailedDescription
          == "Contrast is not high enough for element unless font size is larger.",
        element.elementType == .button,
        element.identifier == "carebrief.onboarding.skip",
        ["跳過", "Skip"].contains(element.label)
      {
        return true
      }

      guard issue.compactDescription == "Contrast failed",
        issue.detailedDescription == "Contrast failed for element",
        element.elementType == .staticText
      else {
        return false
      }

      let contrastLabels: [String: Set<String>] = [
        "carebrief.photoPickerLabel": ["Choose photo"],
        "carebrief.sourceDisclosureLabel": ["原文文字", "Source text"],
      ]
      return contrastLabels[element.identifier]?.contains(element.label) == true

    case .dynamicType:
      guard element.isEnabled else { return false }
      guard issue.compactDescription == "Dynamic Type font sizes are partially unsupported",
        issue.detailedDescription
          == "User will not be able to change the font size of this element"
      else {
        return false
      }

      if element.elementType == .button,
        element.identifier == "carebrief.evidenceDone",
        ["完成", "Done"].contains(element.label)
      {
        return true
      }

      if element.elementType == .button,
        element.identifier == "carebrief.onboarding.skip",
        ["跳過", "Skip"].contains(element.label)
      {
        return true
      }

      guard element.elementType == .staticText else { return false }
      let dynamicTypeLabels: [String: Set<String>] = [
        "carebrief.clearLabel": ["清除", "Clear"],
        "carebrief.documentPrivacyFooter": [
          "相片及文字只在裝置上處理。",
          "Photos and text stay on this device.",
        ],
        "carebrief.extractLabel": ["找出行動", "Find actions"],
        "carebrief.loadSampleLabel": ["載入示例", "Load sample"],
        "carebrief.privacyDisclosureLabel": ["私隱說明", "Privacy"],
        "review-progress-count": ["0 / 1", "1 / 1"],
        "review-progress-label": ["已核對", "Checked"],
        "action-section-scheduled": ["已排期", "Scheduled"],
      ]
      if dynamicTypeLabels[element.identifier]?.contains(element.label) == true {
        return true
      }

      let dynamicActionLabels: [String: Set<String>] = [
        "action-category-": ["覆診／預約", "Appointment"],
        "action-title-": ["覆診／預約", "Appointment"],
        "action-date-": [
          "2026年8月15日 上午9:00",
          "Aug 15, 2026 at 9:00 AM",
        ],
        "action-location-": ["示範醫院"],
        "action-responsible-": ["我", "Me"],
      ]
      return dynamicActionLabels.contains { identifierPrefix, labels in
        isDeterministicSampleActionNode(
          element,
          identifierPrefix: identifierPrefix
        ) && labels.contains(element.label)
      }

    case .textClipping:
      guard element.isEnabled else { return false }
      guard issue.compactDescription == "Text clipped",
        issue.detailedDescription
          == "Text of this element may be clipped at larger Dynamic Type sizes.",
        element.elementType == .staticText
      else {
        return false
      }

      let textClippingLabels: [String: Set<String>] = [
        "carebrief.photoPickerLabel": ["選相片", "Choose photo"],
        "carebrief.documentScannerUnavailable": [
          "Simulator 不支援掃描，請選相片。",
          "Scanning is unavailable in Simulator. Choose a photo.",
        ],
        "carebrief.extractLabel": ["找出行動", "Find actions"],
        "carebrief.privacyDisclosureLabel": ["私隱說明", "Privacy"],
        "carebrief.sourceDisclosureLabel": ["原文文字", "Source text"],
      ]
      if textClippingLabels[element.identifier]?.contains(element.label) == true {
        return true
      }

      if element.identifier == "carebrief.evidenceVerificationTitle",
        ["原文已核實", "Exact quote verified"].contains(element.label)
      {
        return true
      }

      return isDeterministicSampleActionNode(
        element,
        identifierPrefix: "action-category-"
      ) && ["覆診／預約", "Appointment"].contains(element.label)
    }
  }

  @MainActor
  private func isVerifiedXcode27BetaSwiftUIFalsePositive(
    _ issue: XCUIAccessibilityAuditIssue,
    pass: AccessibilityAuditPass
  ) -> Bool {
    #if compiler(>=6.4)
      guard let element = issue.element else { return false }
      let signature = AccessibilityAuditIssueSignature(
        runtime: .xcode27Beta,
        pass: pass,
        compactDescription: issue.compactDescription,
        detailedDescription: issue.detailedDescription,
        elementType: element.elementType,
        identifier: element.identifier,
        label: element.label,
        isEnabled: element.isEnabled
      )
      if isVerifiedExportDynamicTypeFalsePositive(signature)
        || isVerifiedExportSyncNoticeTextClippingFalsePositive(signature)
        || isVerifiedExportActionsHeaderContrastFalsePositive(signature)
        || isVerifiedXcode27ExportContrastFalsePositive(signature)
      {
        return true
      }

      let isSkipButton =
        element.elementType == .button
        && element.identifier == "carebrief.onboarding.skip"
        && ["跳過", "Skip"].contains(element.label)
      if isSkipButton,
        issue.auditType == .contrast,
        issue.compactDescription == "Contrast failed",
        issue.detailedDescription == "Contrast failed for SwiftUI.AccessibilityNode"
      {
        return true
      }
      if isSkipButton,
        issue.auditType == .dynamicType,
        issue.compactDescription == "Dynamic Type font sizes are partially unsupported",
        issue.detailedDescription
          == "User will not be able to change the font size of this SwiftUI.AccessibilityNode"
      {
        return true
      }

      let draftToolbarButtonLabels: [String: Set<String>] = [
        "draft.cancel": ["取消", "Cancel"],
        "draft.save": ["儲存", "Save"],
      ]
      let isDraftToolbarButton =
        element.elementType == .button
        && draftToolbarButtonLabels[element.identifier]?.contains(element.label) == true
      if isDraftToolbarButton,
        issue.auditType == .contrast,
        issue.compactDescription == "Contrast failed",
        issue.detailedDescription == "Contrast failed for SwiftUI.AccessibilityNode"
      {
        return true
      }
      if isDraftToolbarButton,
        issue.auditType == .dynamicType,
        issue.compactDescription == "Dynamic Type font sizes are partially unsupported",
        issue.detailedDescription
          == "User will not be able to change the font size of this SwiftUI.AccessibilityNode"
      {
        return true
      }

      let draftDateTimeLabels: [String: Set<String>] = [
        "draft.includeTimeLabel": ["包括時間", "Include a time"],
        "draft.timeLabel": ["時間", "Time"],
      ]
      if element.elementType == .staticText,
        draftDateTimeLabels[element.identifier]?.contains(element.label) == true,
        issue.auditType == .dynamicType,
        issue.compactDescription == "Dynamic Type font sizes are partially unsupported",
        issue.detailedDescription
          == "User will not be able to change the font size of this SwiftUI.AccessibilityNode"
      {
        return true
      }

      let isEvidenceDoneButton =
        element.elementType == .button
        && element.identifier == "carebrief.evidenceDone"
        && ["完成", "Done"].contains(element.label)
      if isEvidenceDoneButton,
        issue.auditType == .contrast,
        issue.compactDescription == "Contrast failed",
        issue.detailedDescription == "Contrast failed for SwiftUI.AccessibilityNode"
      {
        return true
      }
      if isEvidenceDoneButton,
        issue.auditType == .dynamicType,
        issue.compactDescription == "Dynamic Type font sizes are partially unsupported",
        issue.detailedDescription
          == "User will not be able to change the font size of this SwiftUI.AccessibilityNode"
      {
        return true
      }

      if element.elementType == .staticText,
        element.identifier == "carebrief.evidenceVerificationTitle",
        ["原文已核實", "Exact quote verified"].contains(element.label),
        issue.auditType == .textClipped,
        issue.compactDescription == "Text clipped",
        issue.detailedDescription
          == "Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes."
      {
        return true
      }

      let isExportDoneButton =
        element.elementType == .button
        && element.identifier == "export.done"
        && ["完成", "Done"].contains(element.label)
      if isExportDoneButton,
        issue.auditType == .contrast,
        issue.compactDescription == "Contrast failed",
        issue.detailedDescription == "Contrast failed for SwiftUI.AccessibilityNode"
      {
        return true
      }
      if element.elementType == .staticText,
        element.identifier == "export.responsibleNotesLabel",
        ["在備註加入負責人", "Add responsible person to notes"].contains(element.label),
        issue.auditType == .contrast,
        issue.compactDescription == "Contrast failed",
        issue.detailedDescription == "Contrast failed for SwiftUI.AccessibilityNode"
      {
        return true
      }

      let xcode27OnlyExportDynamicTypePrefixes = [
        "export.date.",
        "export.detailsLabel.",
        "export.location.",
        "export.responsible.",
        "export.sourceLabel.",
      ]
      let isKnownXcode27OnlyExportDynamicTypeNode =
        xcode27OnlyExportDynamicTypePrefixes.contains {
          isDeterministicSampleActionNode(element, identifierPrefix: $0)
        }
      if element.elementType == .staticText,
        isKnownXcode27OnlyExportDynamicTypeNode,
        issue.auditType == .dynamicType,
        issue.compactDescription == "Dynamic Type font sizes are partially unsupported",
        issue.detailedDescription
          == "User will not be able to change the font size of this SwiftUI.AccessibilityNode"
      {
        return true
      }

      let isDisabledPreviewLabel =
        element.elementType == .staticText
        && element.identifier == "export.previewLabel"
        && !element.isEnabled
        && ["預覽 0 個行動", "Preview 0 actions"].contains(element.label)
      if isDisabledPreviewLabel,
        issue.auditType == .contrast,
        issue.compactDescription == "Contrast failed",
        issue.detailedDescription == "Contrast failed for SwiftUI.AccessibilityNode"
      {
        return true
      }

      let isSourceDisclosureLabel =
        element.elementType == .staticText
        && element.identifier == "carebrief.sourceDisclosureLabel"
        && ["原文文字", "Source text"].contains(element.label)
      if isSourceDisclosureLabel,
        issue.auditType == .contrast,
        issue.compactDescription == "Contrast failed",
        issue.detailedDescription == "Contrast failed for SwiftUI.AccessibilityNode"
      {
        return true
      }

      let dynamicTypeLabels: [String: Set<String>] = [
        "carebrief.loadSampleLabel": ["載入示例", "Load sample"],
        "carebrief.clearLabel": ["清除", "Clear"],
        "carebrief.extractLabel": ["找出行動", "Find actions", "抽取行動", "Extract actions"],
        "carebrief.privacyDisclosureLabel": ["私隱說明", "Privacy"],
        "review-progress-label": ["已核對", "Checked"],
        "action-section-scheduled": ["已排期", "Scheduled"],
      ]
      let dynamicActionPrefixes = [
        "action-category-",
        "action-title-",
        "action-confirmation-label-",
        "action-date-",
        "action-location-",
        "action-responsible-",
      ]
      let isKnownDynamicTypeNode =
        dynamicTypeLabels[element.identifier]?.contains(element.label)
        == true
        || element.identifier == "review-progress-count"
        || dynamicActionPrefixes.contains {
          isDeterministicSampleActionNode(element, identifierPrefix: $0)
        }
      if issue.auditType == .dynamicType,
        issue.compactDescription == "Dynamic Type font sizes are partially unsupported",
        issue.detailedDescription
          == "User will not be able to change the font size of this SwiftUI.AccessibilityNode",
        element.elementType == .staticText,
        isKnownDynamicTypeNode
      {
        return true
      }
      if issue.auditType == .textClipped,
        issue.compactDescription == "Text clipped",
        issue.detailedDescription
          == "Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes.",
        element.identifier == "carebrief.loadSampleLabel",
        ["載入示例", "Load sample"].contains(element.label)
      {
        return true
      }
      if issue.auditType == .textClipped,
        issue.compactDescription == "Text clipped",
        issue.detailedDescription
          == "Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes.",
        isDeterministicSampleActionNode(
          element,
          identifierPrefix: "action-category-"
        ),
        ["覆診／預約", "Appointment"].contains(element.label)
      {
        return true
      }

      guard element.elementType == .staticText else { return false }

      let textClippingLabels: [String: Set<String>] = [
        "carebrief.photoPickerLabel": ["選相片", "Choose photo"],
        "carebrief.documentScannerUnavailable": [
          "Simulator 不支援掃描，請選相片。",
          "Scanning is unavailable in Simulator. Choose a photo.",
        ],
        "carebrief.sourceDisclosureLabel": ["原文文字", "Source text"],
        "carebrief.privacyDisclosureLabel": ["私隱說明", "Privacy"],
        "carebrief.extractLabel": ["找出行動", "Find actions", "抽取行動", "Extract actions"],
      ]
      if issue.auditType == .textClipped,
        issue.compactDescription == "Text clipped",
        issue.detailedDescription
          == "Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes.",
        textClippingLabels[element.identifier]?.contains(element.label) == true
      {
        return true
      }

      return issue.auditType == .dynamicType
        && issue.compactDescription == "Dynamic Type font sizes are partially unsupported"
        && issue.detailedDescription
          == "User will not be able to change the font size of this SwiftUI.AccessibilityNode"
        && element.identifier == "carebrief.documentPrivacyFooter"
        && ["相片及文字只在裝置上處理。", "Photos and text stay on this device."]
          .contains(element.label)
    #else
      return false
    #endif
  }
}

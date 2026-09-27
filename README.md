# CareBrief｜睇得明

CareBrief is an iOS app that turns difficult medical and government documents into clear, verifiable next steps.

## MAIC 2026 · SeeClear Labs

CareBrief is SeeClear Labs' entry for the Hong Kong and Macao regional competition of the 2026 Mobile Application Innovation Contest.

- AU Chun Ngai／歐駿毅 — [`@siumiu1968`](https://github.com/siumiu1968)
- OU Qixi／歐啟熙 — [`@miku233333`](https://github.com/miku233333)
- LI KAM HIN／李錦軒 — [`@ECC-2077`](https://github.com/ECC-2077)

Academic adviser: [`@kcbb-edu`](https://github.com/kcbb-edu). The app was developed collaboratively by SeeClear Labs.

Instead of producing only a generic summary, CareBrief extracts the actions a person actually needs to take:

- when and where to go;
- what to prepare, bring, pay, or submit;
- whether fasting or another preparation is required;
- which deadline, follow-up, or medication instruction matters;
- who in the family or care team is responsible;
- calendar events and reminders that can be created after user confirmation;
- Cantonese voice playback and multilingual care versions.

## Product principle

**Every generated action must be traceable to the original document.**

CareBrief must show the source text beside each extracted item, allow users to correct it, and never present medical diagnosis or legal advice.

## MVP

1. Scan with the camera or import an image/PDF.
2. Run OCR and detect the document language.
3. Extract structured actions such as date, time, location, preparation, required items, deadline, contact and next step.
4. Present an editable “Action Card” with links back to the source text.
5. Add confirmed items to Apple Calendar and Reminders.
6. Read the result aloud in Cantonese and support Traditional Chinese and English.
7. Store documents locally by default and make deletion easy.

Initial document types:

- hospital appointment letters;
- discharge instructions;
- medicine labels and printed medication instructions;
- government notices and application letters.

## Technical notes

- [Evidence-linked extraction architecture](docs/adr/ADR-0001-evidence-linked-local-first-extraction.md)
- [Calendar and Reminders permission boundary](docs/adr/ADR-0002-eventkit-full-access-action-export.md)

## Status

`CareBriefCore` is a local, deterministic Swift package that turns supported document instructions into evidence-linked Action Cards. The SwiftUI App Layer accepts manual text, a synthetic sample, one image from Photos or a multi-page scan from the system document camera on supported devices. Apple Vision OCR runs on device, places recognized text in the editable source field and preserves each fragment's page, normalized bounding box and assembled UTF-16 range.

The MAIC action loop now creates an editable draft beside each immutable Core action. A user can correct title, details, date/time, location, required items and contact, choose themselves, a family/caregiver label or a custom responsible name, re-check the unchanged source evidence, then explicitly confirm the action. Confirmed actions enter a final Calendar/Reminders preview with destination overrides, Apple-account sync disclosure, just-in-time permission, deterministic duplicate detection, per-item results and same-process Undo.

The App opens with a three-page, permission-free guide that can be skipped from the top-right of every page and replayed later without resetting the current review. Its compact native-list interface follows the user's system Dynamic Type setting. Easy Read is on by default but changes only copy length and disclosure state, not text size, row height or control size. App chrome shows one selected language at a time: it follows the iPhone by default and supports persistent Traditional Chinese or English overrides. Source documents and user-entered text stay unchanged and are not translated; Apple permission dialogs continue to follow the iPhone language.

OCR never starts extraction, confirmation or EventKit output automatically. Responsible names stay in CareBrief unless the preview toggle is explicitly enabled, and no Contacts or messaging integration is used. PDF import, document/draft persistence, caregiver sharing, speech, document translation and HealthKit remain separate follow-up work. The document camera is unavailable in Simulator and still requires physical-device runtime verification.

## SwiftUI prototype

The checked-in iOS 16 project uses the local `CareBriefCore` and `CareBriefAppSupport` package products:

```bash
open CareBriefApp.xcodeproj
```

`project.yml` is the source of truth for the checked-in project. The project was clean-generated with the official XcodeGen 2.45.4 release and verified with an Xcode 27 simulator target build. Install [XcodeGen 2.45.4](https://github.com/yonaskolb/XcodeGen/releases/tag/2.45.4) on `PATH`, and point `DEVELOPER_DIR` to an installed full Xcode before building:

```bash
xcodegen --version # must report 2.45.4
xcodegen generate --spec project.yml
DEVELOPER_DIR="/path/to/Xcode.app/Contents/Developer" \
xcodebuild \
  -project CareBriefApp.xcodeproj \
  -scheme CareBriefApp \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

XcodeGen 2.45.4 uses the checkout folder name for the root local-package navigator entry. Use the canonical `CareBrief` checkout name when comparing the generated project byte for byte; a differently named worktree can change that display entry and its derived project IDs without changing the package path or build behavior.

The App Layer accepts manual text, its synthetic built-in sample or a user-selected image. It uses `PhotosPicker` without requesting broad photo-library access and only presents `VNDocumentCameraViewController` when the device reports support. Vision OCR prefers supported Traditional Chinese and English recognition, respects image orientation, and discards image data after the in-memory recognition task. It does not persist or upload source images.

Editing or replacing the input invalidates the previous extraction and confirmations; checking a card never removes its `needsReview` state. OCR success also creates a fresh, unextracted review state even when the recognized text matches the previous text. The evidence screen displays the exact quote, extraction rule and half-open UTF-16 range.

Editing an extracted draft invalidates only that action's confirmation and never changes the Core evidence, rule, confidence or `needsReview` flag. Today includes only an unambiguous Gregorian model date equal to today in the user's local time zone; undated or ambiguous work stays Unscheduled. Calendar date-only actions become all-day events, timed actions default to 60 minutes, and Reminders may omit a due date. Full EventKit access is requested only from the final Add action and is used only for exact CareBrief-marker lookup, creation and receipt-verified Undo.

The main screen keeps import and review actions visible while placing manual text, full privacy wording and extraction metadata in disclosures. Edit and Source remain available on every action, review warnings stay visible after confirmation, and the bottom Preview action uses a safe-area inset so it does not cover the list.

## Product roadmap

Evidence-linked extraction, Camera/Photos OCR, editable responsible-person drafts and explicitly confirmed Calendar/Reminders output are implemented as separate, user-controlled layers. The next milestones are:

1. offline action intelligence using synthetic-data Python tooling, a small Core ML classifier and rule-based safety guardrails. Model-added cards always require review and remain experimental unless every accuracy and safety gate passes.
2. document translation and Cantonese read-aloud care versions, with the original source always available.
3. PDF import, richer reading-order analysis and geometry-linked source highlighting on top of the existing Camera, Photos and Vision OCR provenance.
4. A separate, privacy-reviewed caregiver sharing flow.
5. A medical-only, read-only HealthKit spike with just-in-time, per-type permission requests before any production integration.

HealthKit is not a generic task store. A future CareBrief spike may read user-authorized clinical medication records already present in supported Health Records setups, while appointments, government-document actions and caregiver tasks remain in CareBrief, Calendar or Reminders. Clinical/FHIR records can be unavailable or incomplete and must not replace the source document. HealthKit clinical records are read-only; OCR output must never be written automatically. Newer medication concepts and dose-event APIs require iOS 26+ availability checks and are a separate path from clinical medication records. Any future medication feature or supported write must first verify the deployed OS, exact HealthKit data type and allowed operation, then require a separate preview and explicit user action. An empty query is treated as “no available data,” not proof that permission was denied. See Apple's [HealthKit authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) and [clinical-record access](https://developer.apple.com/documentation/healthkit/accessing-health-records) documentation.

## CareBriefCore

Requirements: a Swift 6 toolchain. The package itself compiles in Swift 5 language mode so the public core stays conservative for iOS integration.

```bash
swift package describe
swift test
swift run carebrief-demo
```

On macOS, select a full Xcode toolchain before running Swift Testing. This avoids incomplete Command Line Tools installations that can compile but cannot load `Testing.framework`:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

The demo accepts built-in Traditional Chinese sample text, a UTF-8 file, or stdin:

```bash
swift run carebrief-demo --file notice.txt
printf 'Submit the form by 17 July 2026.\n' | swift run carebrief-demo --stdin
```

The demo prints the supplied source sentences as evidence. Use synthetic or de-identified text in shell sessions and CI, and do not retain stdout logs containing private medical or government-document content.

Its JSON output includes each action's category, structured fields, confidence, review flag, rule ID, source text and UTF-16 source range. The current rule-based extractor supports explicit appointment dates/times, locations, preparation instructions, required items, deadlines, contact details and next steps in selected Traditional Chinese and English patterns.

CareBriefCore does not diagnose, provide medical or legal advice, upload documents, call a cloud service, or store API credentials. Unsupported or ambiguous text stays reviewable instead of being invented.

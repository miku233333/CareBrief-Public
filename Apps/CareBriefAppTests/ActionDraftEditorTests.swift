import CareBriefCore
import Testing

@testable import CareBrief

@Suite struct ActionDraftEditorTests {
  @Test func ambiguousDateRequiresAnExplicitDayChoice() {
    var resolution = ActionDraftDateResolution(
      dateTime: ActionDateTime(
        year: 2026,
        month: 8,
        day: 9,
        isAmbiguous: true
      )
    )

    #expect(resolution.blocksSave)

    resolution.register(.timeAvailability)
    resolution.register(.timeSelected)
    resolution.register(.dateAvailability(true))

    #expect(resolution.blocksSave)

    resolution.register(.daySelected)

    #expect(!resolution.blocksSave)
  }

  @Test func removingDateRestoresTheAmbiguousDateBlock() {
    var resolution = ActionDraftDateResolution(
      dateTime: ActionDateTime(
        year: 2026,
        month: 8,
        day: 9,
        isAmbiguous: true
      )
    )
    resolution.register(.daySelected)

    resolution.register(.dateAvailability(false))

    #expect(resolution.blocksSave)
  }

  @Test func clearSourceDateNeedsNoResolution() {
    var resolution = ActionDraftDateResolution(
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15)
    )

    resolution.register(.dateAvailability(false))

    #expect(!resolution.blocksSave)
  }
}

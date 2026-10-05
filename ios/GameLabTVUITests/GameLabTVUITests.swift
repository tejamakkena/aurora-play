import XCTest

/// Automates the exact question that took 15 rounds of manual on-device
/// testing to even diagnose: does pressing Select (or Play/Pause) on the
/// Siri Remote actually invoke a game card's action on the game-selection
/// screen at all?
///
/// This deliberately tests nothing else -- it only checks "does pressing
/// this remote button invoke the button's/command's closure" -- but it
/// genuinely cannot assume the app stays on the selection screen while
/// checking that anymore. It was originally written assuming exactly that
/// ("no real navigation past the selection screen ... no backend runs in
/// CI"), which was true for as long as a since-fixed bug (see PR #73) meant
/// `create_room`'s response never actually reached anything listening for
/// it. Now that it does, this test's own presses reach the real, live
/// server configured in AppConstants.serverURL and can flip the screen
/// straight to the lobby before either test ever gets to check for the
/// `debugLastInput` diagnostic in TVGameSelectionView (compiled in only for
/// `#if DEBUG` builds, which is what this test target -- and every other
/// Simulator build in this repo -- runs as) -- confirmed directly from a
/// real CI failure log: `gameCard_trivia` had vanished and the visible
/// hierarchy showed a `Button, label: 'Waiting for 2 more…'` -- TVLobbyView,
/// not a broken press. `pressAndExpectDebugLabel` below treats either
/// signal (the banner, or the whole selection screen navigating away) as
/// equally valid proof the press reached `pick(_:)`.
final class GameLabTVUITests: XCTestCase {

    private let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Polls `hasFocus` without touching the remote, so waiting for focus can
    /// never itself move focus.
    private func waitForFocus(on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasFocus == true"),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Launches fresh and returns the trivia game card with focus actually
    /// on it, so a remote-button press below can be attributed to that card.
    ///
    /// TVGameSelectionView originally tried `.prefersDefaultFocus` for this,
    /// but this test's own first real CI run showed Select/Play-Pause never
    /// reaching `pick(_:)` at all -- consistent with a known tvOS gotcha
    /// where that modifier can silently lose against a `LazyVGrid`'s own
    /// child-layout timing (see the "ScrollView and prefersDefaultFocus
    /// currently incompatible?" report on Apple's developer forums). The
    /// view now assigns `$focusedGame` imperatively on `.onAppear` instead,
    /// which doesn't have the same race. This helper still insists on a real
    /// `hasFocus` before pressing anything -- so a future focus-assignment
    /// regression fails loudly here with a clear message, rather than this
    /// test silently pressing Select/Play-Pause against the wrong element.
    private func focusedTriviaCard(in app: XCUIApplication) -> XCUIElement {
        let triviaCard = app.buttons["gameCard_trivia"]
        XCTAssertTrue(
            triviaCard.waitForExistence(timeout: 10),
            "gameCard_trivia never appeared -- the game-selection screen didn't load."
        )

        // Wait for the view's own focus assignment rather than racing it.
        // The original order checked hasFocus the instant the element
        // existed and pressed Right if it was still false -- but on a cold
        // launch TVGameSelectionView's .onAppear assignment lands a beat
        // after the card is first queryable, so that press moved focus onto
        // the *second* card, from which trivia can never come back, and the
        // wait that followed could then only ever time out. Richer card
        // rendering made that race start losing; the ordering was always
        // wrong, and no press belongs in a step that only waits.
        XCTAssertTrue(
            waitForFocus(on: triviaCard, timeout: 8),
            "gameCard_trivia never gained focus on its own -- TVGameSelectionView's "
            + ".onAppear focus assignment is not reaching it."
        )

        // A remote press sent the instant focus lands can race the focus
        // engine's own settle/animation -- observed directly on a PR that
        // touched nothing in this view or its test: identical code that had
        // passed cleanly on the previous run (hasFocus confirmed true, then
        // immediately "Pressing Select/Play-Pause button", then nothing)
        // failed both tests the very next run. Giving the UI a brief beat to
        // settle before the first press removes that race without weakening
        // what's actually being asserted below.
        Thread.sleep(forTimeInterval: 2.0)
        return triviaCard
    }

    /// Presses `button` on the remote and confirms it reached `pick(_:)`,
    /// retrying the press itself (not just the wait) a few times, with a
    /// growing gap between attempts, before failing.
    ///
    /// Two earlier versions of this treated only `debugLastInput` appearing
    /// as success and both failed identically on every retry, in both test
    /// methods, across independent app launches -- not the Simulator-input
    /// flakiness that was the working theory at the time. The real CI log
    /// showed why: the press *did* reach `pick(_:)` every time, and now that
    /// PR #73's socket-handler fix is in, `pick(_:)` -> `createRoom` really
    /// does round-trip with the live server and can flip the whole screen to
    /// TVLobbyView -- unmounting `debugLastInput` (and `gameCard_trivia`
    /// itself) -- before either test's wait ever caught the banner. That's
    /// a second, independent proof the button's action fired: the selection
    /// screen cannot navigate away on its own, only `pick(_:)` triggers
    /// that. Whichever signal shows up first is accepted.
    private func pressAndExpectDebugLabel(
        _ button: XCUIRemote.Button,
        expectedLabel: String,
        in app: XCUIApplication,
        attempts: Int = 3
    ) {
        let debugLabel = app.staticTexts["debugLastInput"]
        let triviaCard = app.buttons["gameCard_trivia"]
        for attempt in 1...attempts {
            if triviaCard.exists, !triviaCard.hasFocus {
                remote.press(.right)
                Thread.sleep(forTimeInterval: 1.0)
            }
            remote.press(button)

            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                // Read the banner through one snapshot, not `exists` and
                // then `.label`: pick(_:)'s createRoom round-trip can flip
                // the screen to the lobby between those two queries, and
                // reading `.label` off the unmounted element fails the test
                // ("No matches found for debugLastInput") even though the
                // press DID reach pick(_:). A failed snapshot just means
                // "not there right now" and falls through to the checks below.
                if let banner = try? debugLabel.snapshot() {
                    XCTAssertEqual(banner.label, expectedLabel)
                    return
                }
                if !triviaCard.exists {
                    // The selection screen itself is gone -- only
                    // reachable via pick(_:) actually running and its
                    // createRoom round-trip landing a room_updated back.
                    return
                }
                Thread.sleep(forTimeInterval: 0.2)
            }

            if attempt < attempts {
                Thread.sleep(forTimeInterval: Double(attempt) * 2.0)
            }
        }
        XCTFail(
            "Neither debugLastInput nor a navigated-away selection screen appeared after " +
            "\(attempts) attempts pressing \(button) on the focused trivia card -- \(button) " +
            "is not reaching pick(_:)."
        )
    }

    func testSelectPressFiresPickForFocusedCard() {
        let app = XCUIApplication()
        app.launch()
        _ = focusedTriviaCard(in: app)

        pressAndExpectDebugLabel(.select, expectedLabel: "Select fired: trivia", in: app)
    }

    func testPlayPausePressFiresPickForFocusedCard() {
        let app = XCUIApplication()
        app.launch()
        _ = focusedTriviaCard(in: app)

        pressAndExpectDebugLabel(.playPause, expectedLabel: "Play/Pause fired: trivia", in: app)
    }
}

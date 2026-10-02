import SwiftUI

struct TVGameSelectionView: View {
    let onSelect: (GameID) -> Void
    /// Starts a game with no phones at all — the Siri Remote is the controller.
    var onSelectSolo: ((GameID) -> Void)? = nil

    @State private var selectedCategory: GameCategory? = nil
    @FocusState private var focusedGame: GameID?
    @State private var hasAppeared = false
    @State private var isPulsing = false

    // Every soloPlayable game also supports more than one player (Neon
    // Snake, 2048, Simon Says: up to 4; Brick Breaker: up to 2; Atlas: up to
    // 8) -- picking one used to always start it solo immediately with no
    // way to invite anyone, despite the card's own "N–M players" caption
    // advertising otherwise. Reported directly: Neon Snake showed no room
    // code and no controller access at all, and Atlas -- whose only input
    // style is typed text -- had no way to answer, since AtlasControllerView
    // (the phone UI that types the answer) can never appear if no phone can
    // ever join. This prompt gives a real choice instead of assuming solo.
    @State private var soloChoiceGame: GameID? = nil

    // Gives the first game card a deterministic initial focus target instead
    // of leaving it to the focus engine's default first-focusable-view guess
    // (which would otherwise land on the "All" sidebar pill), so
    // GameLabTVUITests doesn't need to reproduce an exact D-pad navigation
    // sequence just to reach a card before pressing Select.
    //
    // Deliberately NOT using .prefersDefaultFocus(_:in:): the first attempt
    // at this used exactly that, and GameLabTVUITests' own first real CI run
    // showed Select/Play-Pause never reaching pick(_:) at all -- consistent
    // with a known tvOS gotcha where .prefersDefaultFocus racing a LazyVGrid's
    // own child layout can silently lose to whatever non-lazy view (here, the
    // sidebar's "All" pill) is already laid out by the time the focus engine
    // resolves an initial target. Setting the existing, already-working
    // $focusedGame binding directly (below, on .onAppear) sidesteps that
    // race entirely -- it's the same binding swipe navigation already uses
    // successfully, just assigned imperatively instead of declaratively.
    // GameLabTVUITests keeps its own defensive hasFocus check + Right-press
    // fallback regardless, so a future regression here fails loudly there
    // with a clear message instead of silently pressing the wrong element.

    // TEMPORARY diagnostic: four different Select-click mechanisms have each
    // been reported as "still doesn't do anything" on real hardware, with no
    // way from here to tell whether the input is reaching `pick(_:)` at all
    // or whether it fires but something after it (onSelect/onSelectSolo ->
    // the socket round-trip -> the screen transition) is what's silent. This
    // makes that unambiguous with a full-screen flash + label the instant
    // pick(_:) runs, before any of that downstream logic -- independent of
    // TVGameCard's own focus styling, which was a red herring earlier: a
    // Button's default focus chrome is a FOCUS effect, not proof a click
    // fired. Remove this whole block once the real cause is confirmed.
    //
    // #if DEBUG: this used to ship (unintentionally) into real TestFlight
    // builds -- a yellow full-screen banner is not something real users
    // should ever see. It's gated to DEBUG now that GameLabTVUITests exists
    // to answer the "does Select even fire pick(_:)" question automatically,
    // in a Simulator, on every PR -- which is the actual replacement for the
    // 15 rounds of manual on-device testing this was added for. DEBUG is
    // available here because local/CI Simulator builds (build-check, and the
    // new tv-ui-test job) default to the Debug configuration, while the real
    // TestFlight archive (deploy-tvos) explicitly passes
    // -configuration Release, which #if DEBUG excludes.
    #if DEBUG
    @State private var debugLastInput: String? = nil
    #endif

    // Observed rather than read off the singleton, so the dot actually updates
    // when the connection drops.
    @ObservedObject private var socket = GameSocketManager.shared

    private var displayedGames: [GameID] {
        if let cat = selectedCategory {
            return GameID.allCases.filter { $0.category == cat }
        }
        return GameID.allCases
    }

    var body: some View {
        HStack(spacing: 60) {
            // Left sidebar — categories
            VStack(alignment: .leading, spacing: 20) {
                Text("Aurora")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .cyan], startPoint: .leading, endPoint: .trailing)
                    )

                Text("Pick a game")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))

                Divider().background(Color.white.opacity(0.2))

                VStack(alignment: .leading, spacing: 12) {
                    CategoryPill(label: "All", accent: .cyan, isSelected: selectedCategory == nil) {
                        selectCategory(nil)
                    }
                    // Each pill carries its category's own accent (the same one
                    // its cards wear), so the sidebar doubles as the grid's
                    // colour legend rather than nine identical cyan pills.
                    ForEach(GameCategory.allCases, id: \.self) { cat in
                        CategoryPill(label: cat.rawValue,
                                     accent: cat.tvStyle.accent,
                                     isSelected: selectedCategory == cat) {
                            selectCategory(selectedCategory == cat ? nil : cat)
                        }
                    }
                }

                Spacer()

                // Connection status dot — breathes gently while reconnecting
                // so the state reads as "actively retrying", not stuck.
                HStack(spacing: 8) {
                    Circle()
                        .fill(socket.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                        .opacity(socket.isConnected ? 1 : (isPulsing ? 1 : 0.3))
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                isPulsing = true
                            }
                        }
                    Text(socket.isConnected ? "Server connected" : "Reconnecting…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))

                    // Build stamp — which commit this build came from, so a
                    // glance at the TV answers "is this running the new code?".
                    Text(BuildStamp.displayString)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.top, 2)
                }
            }
            .frame(width: 280)
            .padding(.vertical, 60)
            .padding(.leading, 60)
            // Gives the focus engine a clear boundary: moving right off the
            // last category jumps into the grid's own section below, rather
            // than the engine guessing at a target across two sibling stacks.
            .focusSection()

            // Right — game grid
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(260), spacing: 28), count: 4),
                    spacing: 28
                ) {
                    ForEach(displayedGames, id: \.self) { game in
                        // Third attempt at this, so a full account of what
                        // was tried and why, confirmed from real on-device
                        // testing each time:
                        //   1. Plain VStack + .onTapGesture: swipe worked
                        //      (once .focusable() was added), but Select
                        //      never fired the tap at all.
                        //   2. Button + .buttonStyle(.plain): Select finally
                        //      registered, but tvOS drew its own default
                        //      focus/pressed "card" chrome underneath the
                        //      button regardless of style -- the stray white
                        //      rounded rectangle that was reported.
                        //   3. Plain VStack + .onLongPressGesture(minimumDuration: 0):
                        //      removed the white chrome, but on real
                        //      hardware Select stopped registering again --
                        //      apparently no more reliable than
                        //      .onTapGesture was for a non-Button view.
                        // (2) is the only one of the three that actually
                        // made Select fire reliably, so Button is right.
                        // Attempt 4 tried .focusEffectDisabled() to remove
                        // (2)'s remaining cosmetic issue -- tvOS's own
                        // default focus/pressed "card" chrome bleeding
                        // through underneath the button regardless of
                        // .buttonStyle(.plain) -- and made things worse, not
                        // better: confirmed on real hardware that adding it
                        // made Select stop registering ANYTHING at all. That
                        // ruled out .focusEffectDisabled() specifically (a
                        // documented, independently-reported tvOS
                        // reliability issue, not unique to this app), not
                        // Button itself, so this cosmetic fix -- promised as
                        // "its own follow-up once clicking is confirmed
                        // solid" -- takes a different path: a fully custom
                        // ButtonStyle. Unlike .plain (an Apple-provided style
                        // that still injects some baseline chrome on tvOS,
                        // per the .plain quirk above), a from-scratch style
                        // renders exactly and only configuration.label, with
                        // no built-in chrome to bleed through -- and it
                        // doesn't touch .focusEffectDisabled() at all, so
                        // Select delivery is unaffected. GameLabTVUITests'
                        // automated Select/Play-Pause checks are the safety
                        // net confirming that on every future PR, which
                        // didn't exist yet during the four earlier attempts.
                        Button {
                            #if DEBUG
                            debugMark("Select", game)
                            #endif
                            pick(game)
                        } label: {
                            TVGameCard(game: game, isFocused: focusedGame == game)
                        }
                        .buttonStyle(NoChromeButtonStyle())
                        .focused($focusedGame, equals: game)
                        .accessibilityIdentifier("gameCard_\(game.rawValue)")
                        .onPlayPauseCommand {
                            #if DEBUG
                            debugMark("Play/Pause", game)
                            #endif
                            pick(game)
                        }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 60)
                .padding(.trailing, 60)
                .animation(.easeInOut(duration: 0.25), value: selectedCategory)
            }
            .focusSection()
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 16)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { hasAppeared = true }
            // Imperatively assign initial focus onto the first card, on the
            // same $focusedGame binding swipe navigation already uses
            // successfully -- see this property's own doc comment for why
            // this replaced .prefersDefaultFocus(_:in:).
            if focusedGame == nil {
                focusedGame = displayedGames.first
            }
        }
        // TEMPORARY diagnostic overlay -- see debugLastInput's declaration.
        // Impossible to miss: a full-screen flash naming exactly which input
        // fired and for which game, the instant it fires, before anything
        // else runs. If this never appears no matter what's pressed, the
        // remote's input truly never reaches this view at all -- if it does
        // appear but the screen never advances past this one, the bug is
        // downstream in pick(_:)/onSelect/onSelectSolo or the server
        // round-trip, not the button/gesture mechanism this has been
        // chasing across four prior attempts.
        //
        // #if DEBUG (see debugLastInput's declaration for why): GameLabTVUITests
        // reads this Text's accessibilityIdentifier ("debugLastInput") and its
        // label to assert Select/Play-Pause actually reached pick(_:), in a
        // tvOS Simulator, on every PR -- automating the exact check this
        // banner used to require a human with a real Apple TV for.
        #if DEBUG
        .overlay {
            if let debugLastInput {
                Text(debugLastInput)
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundColor(.black)
                    .padding(40)
                    .background(Color.yellow)
                    .accessibilityIdentifier("debugLastInput")
                    .transition(.opacity)
            }
        }
        #endif
        .confirmationDialog(
            "How do you want to play?",
            isPresented: Binding(
                get: { soloChoiceGame != nil },
                set: { if !$0 { soloChoiceGame = nil } }
            ),
            titleVisibility: .visible,
            presenting: soloChoiceGame
        ) { game in
            Button("Play Solo Now") {
                soloChoiceGame = nil
                onSelectSolo?(game)
            }
            Button("Invite Friends") {
                soloChoiceGame = nil
                onSelect(game)
            }
            Button("Cancel", role: .cancel) { soloChoiceGame = nil }
        } message: { game in
            Text("Play \(game.displayName) alone with the Siri Remote, or get a room code so up to \(game.maxPlayers) friends can join on their phones.")
        }
    }

    #if DEBUG
    private func debugMark(_ source: String, _ game: GameID) {
        withAnimation(.easeIn(duration: 0.05)) {
            debugLastInput = "\(source) fired: \(game.rawValue)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.3)) { debugLastInput = nil }
        }
    }
    #endif

    private func selectCategory(_ category: GameCategory?) {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedCategory = category
        }
    }

    /// A solo-capable game prompts for Solo vs. Invite Friends (see
    /// soloChoiceGame's own doc comment); everything else goes straight
    /// through the normal join flow. Falls back to the normal flow too when
    /// no solo path was even wired up by the caller.
    private func pick(_ game: GameID) {
        guard game.soloPlayable, onSelectSolo != nil else {
            onSelect(game)
            return
        }
        soloChoiceGame = game
    }
}

// MARK: - Subviews

/// One game tile.
///
/// Reported twice, verbatim: "Game icons are still the emoji with the names
/// which feels too basic. Can I have some animations." So the flat purple
/// rectangle is gone: every card now wears its `GameCategory`'s own gradient
/// (see `TVCategoryStyle`), a category-tinted spotlight and ring behind the
/// emoji, and a category glyph in the corner -- all drawn procedurally, no
/// image assets.
///
/// The motion budget is spent deliberately, and only on the focused card:
///
///   * Unfocused cards are completely still. Every continuous effect below is
///     gated on `isFocused`, and its driving `@State` is only ever animated
///     while this card holds focus. Forty-one cards shimmering at once would
///     be visual noise on a TV and a pointless GPU load on an Apple TV, and
///     `LazyVGrid` keeps offscreen ones from existing at all.
///   * Exactly one card is focusable at a time, so at most one card is ever
///     running these four cheap, GPU-friendly effects: an emoji float, a
///     breathing ring/glow, a diagonal sheen sweep, and a slow 3D sway.
///   * No `Timer` anywhere -- everything is a SwiftUI `repeatForever`
///     animation, so it stops with the view and costs nothing when idle.
///
/// Legibility is protected independently of all of that: the title and player
/// count sit above a bottom scrim and carry their own drop shadow, so no
/// gradient or sheen can wash them out.
///
/// Note what this deliberately does NOT touch: the enclosing `Button`,
/// `NoChromeButtonStyle`, `.focused`, `.accessibilityIdentifier` and
/// `.onPlayPauseCommand` wiring in the grid above. That combination took
/// roughly fifteen rounds of on-device debugging to land (see the grid's own
/// comment for the four configurations that each broke Select delivery or
/// focus), and this is purely a restyling of the Button's *label*.
private struct TVGameCard: View {
    let game: GameID
    let isFocused: Bool

    // Continuous-motion drivers. Each is only ever animated (and only ever
    // non-default) while this card is focused -- see `setMotion(_:)`.
    @State private var bob = false      // emoji float
    @State private var halo = false     // ring + glow breathing
    @State private var sheenSweep = false
    @State private var sway = false     // slow 3D parallax tilt

    private static let cardWidth: CGFloat = 240
    private static let cardHeight: CGFloat = 244
    private static let corner: CGFloat = 24

    private var style: TVCategoryStyle { game.category.tvStyle }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
    }

    var body: some View {
        ZStack {
            backgroundLayers
            cardContent
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        // Overlays (not ZStack siblings) so the oversized sheen rect can
        // overflow the card and be cut back by the clipShape below, instead
        // of stretching the ZStack and squashing the gradients with it.
        .overlay { sheen }
        .overlay(alignment: .topLeading) { categoryGlyph }
        // Small fixed-size icon badges pinned to a corner, entirely
        // independent of the text layout -- unlike the old full-text Label
        // row, these can never grow wider than the card and spill past its
        // rounded-rectangle background.
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 6) {
                if game.hasPrivateInfo {
                    GameBadge(systemImage: "eye.slash.fill", color: .cyan)
                }
                if game.supportsRemote {
                    GameBadge(systemImage: "av.remote.fill", color: .green)
                }
            }
            .padding(10)
        }
        .clipShape(shape)
        .overlay { borderStroke }
        // One composited layer, so the glow below is a single shadow of the
        // finished card rather than a separate shadow per sublayer.
        .compositingGroup()
        .shadow(color: style.accent.opacity(isFocused ? (halo ? 0.7 : 0.32) : 0),
                radius: isFocused ? (halo ? 30 : 18) : 0,
                y: isFocused ? 10 : 0)
        .rotation3DEffect(.degrees(isFocused ? 6 : 0),
                          axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .rotation3DEffect(.degrees(isFocused ? (sway ? 3 : -3) : 0),
                          axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.68), value: isFocused)
        .onChange(of: isFocused) { _, focused in setMotion(focused) }
        // A card can be created by LazyVGrid *after* the grid has already
        // handed it focus (initial focus is assigned in the parent's
        // .onAppear), in which case no isFocused change ever arrives here.
        .onAppear { if isFocused { setMotion(true) } }
    }

    // MARK: Layers

    private var backgroundLayers: some View {
        ZStack {
            shape.fill(Color.white.opacity(0.06))

            shape.fill(
                LinearGradient(colors: [style.top, style.bottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .opacity(isFocused ? 0.5 : 0.16)

            // Soft category-tinted spotlight behind the emoji.
            RadialGradient(
                colors: [style.accent.opacity(isFocused ? 0.45 : 0.14), .clear],
                center: UnitPoint(x: 0.5, y: 0.34),
                startRadius: 6,
                endRadius: isFocused ? 150 : 115
            )

            // Bottom scrim: guarantees the title and player count stay legible
            // no matter how bright a category's gradient or the sheen gets.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: .black.opacity(0.45), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var cardContent: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 104, height: 104)

                Circle()
                    .strokeBorder(
                        AngularGradient(colors: [style.top, style.bottom, style.top],
                                        center: .center),
                        lineWidth: isFocused ? 3 : 1.5
                    )
                    .frame(width: 104, height: 104)
                    .opacity(isFocused ? (halo ? 1.0 : 0.45) : 0.28)
                    .scaleEffect(isFocused && halo ? 1.06 : 1.0)

                Image(systemName: game.sfSymbol)
                    .font(.system(size: 52))
                    .foregroundColor(.white)
                    .shadow(color: style.accent.opacity(isFocused ? 0.85 : 0), radius: 14)
                    .offset(y: bob ? -5 : 0)
            }
            .frame(height: 108)

            Text(game.displayName)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 1)

            Text("\(game.minPlayers)–\(game.maxPlayers) players")
                .font(.system(size: 19, weight: .medium))
                .foregroundColor(.white.opacity(isFocused ? 0.85 : 0.55))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    /// A diagonal highlight that slides across the focused card. The rect is
    /// deliberately far larger than the card so the bright band is fully
    /// offscreen at both ends of the loop -- which is why restarting it (an
    /// un-autoreversed `repeatForever`) is invisible, and why snapping it back
    /// to its start when focus leaves is invisible too.
    ///
    /// Built only while focused rather than kept at `.opacity(0)`, so the
    /// other forty cards don't each carry an oversized (if invisible) gradient
    /// layer around for nothing.
    @ViewBuilder
    private var sheen: some View {
        if isFocused {
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0),    location: 0.34),
                    .init(color: .white.opacity(0.22), location: 0.50),
                    .init(color: .white.opacity(0),    location: 0.66)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: Self.cardWidth * 2.2, height: Self.cardHeight * 2.2)
            .rotationEffect(.degrees(-20))
            .offset(x: sheenSweep ? Self.cardWidth * 1.3 : -Self.cardWidth * 1.3)
            .allowsHitTesting(false)
        }
    }

    private var categoryGlyph: some View {
        Image(systemName: style.symbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white.opacity(isFocused ? 0.95 : 0.5))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.3)))
            .padding(10)
    }

    private var borderStroke: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [style.top.opacity(isFocused ? 0.95 : 0.30),
                         style.bottom.opacity(isFocused ? 0.6 : 0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            lineWidth: isFocused ? 2.5 : 1.2
        )
    }

    // MARK: Motion

    /// Starts or stops every continuous effect in one place, so "only the
    /// focused card moves" is a single invariant rather than something each
    /// modifier has to be trusted to re-derive.
    private func setMotion(_ running: Bool) {
        guard running else {
            withAnimation(.easeOut(duration: 0.3)) {
                bob = false
                halo = false
                sway = false
            }
            // Not animated: this only rearms the sweep for the next time this
            // card is focused. The sheen view itself is already gone by now
            // (it only exists while focused), so nothing visible snaps.
            sheenSweep = false
            return
        }
        withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
            bob = true
        }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            halo = true
        }
        withAnimation(.easeInOut(duration: 3.1).repeatForever(autoreverses: true)) {
            sway = true
        }
        withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
            sheenSweep = true
        }
    }
}

/// Renders exactly `configuration.label` -- nothing else. `.buttonStyle(.plain)`
/// is Apple-provided and, on tvOS, still draws some of its own default
/// focus/pressed chrome underneath a Button's content regardless of style;
/// a style built from scratch has no such built-in chrome to bleed through,
/// so TVGameCard's own isFocused-driven purple background/glow/scale is the
/// only visual effect. See the game grid's own comment for why this
/// replaced .plain instead of .focusEffectDisabled().
private struct NoChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct GameBadge: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption2.bold())
            .foregroundColor(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(color.opacity(0.85)))
    }
}

private struct CategoryPill: View {
    let label: String
    /// The same accent this category's cards use, so the sidebar reads as the
    /// grid's legend. Filled when selected; shown as a leading dot otherwise.
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(accent)
                    .frame(width: 10, height: 10)
                    .opacity(isSelected ? 0 : 1)
                Text(label)
                    .font(.body)
                    .foregroundColor(isSelected ? .black : .white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isSelected ? accent : Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

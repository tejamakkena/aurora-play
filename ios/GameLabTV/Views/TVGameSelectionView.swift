import SwiftUI

struct TVGameSelectionView: View {
    let onSelect: (GameID) -> Void
    /// Starts a game with no phones at all — the Siri Remote is the controller.
    var onSelectSolo: ((GameID) -> Void)? = nil
    /// Starts a Game Night room (a playlist with one scoreboard). The card
    /// is hidden when nil.
    var onGameNight: (() -> Void)? = nil

    @State private var selectedCategory: GameCategory? = nil
    @FocusState private var focusedGame: GameID?
    @State private var hasAppeared = false
    @State private var isPulsing = false

    // Every soloPlayable game also supports more than one player (Neon
    // Snake, 2048, Simon Says: up to 4; Brick Breaker: up to 2) -- picking
    // one used to always start it solo immediately with no way to invite
    // anyone, despite the card's own "N–M players" caption advertising
    // otherwise. Reported directly: Neon Snake showed no room code and no
    // controller access at all, and Atlas (back when it was a typed solo
    // game; it is now a spoken party game that always needs phones) had no
    // way to answer because no phone could ever join. This prompt gives a
    // real choice instead of assuming solo.
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
            return GameID.listed.filter { $0.category == cat }
        }
        return GameID.listed
    }

    /// The game the hero banner above the grid is showing: whichever card
    /// last held focus, so the banner keeps its content while focus is over
    /// in the sidebar. Purely visual -- never feeds back into focus.
    @State private var heroGame: GameID = .trivia

    /// Four fixed columns, each a little wider than a card so a focused
    /// card's scale-up has room; the hero banner matches this width so both
    /// share the same edges.
    private static let columnCount: Int = 4
    private static let columnSpacing: CGFloat = 26
    private static var columnWidth: CGFloat { TVGameCard.cardWidth + 24 }
    private static var gridWidth: CGFloat {
        CGFloat(columnCount) * columnWidth + CGFloat(columnCount - 1) * columnSpacing
    }

    var body: some View {
        // tvOS already insets everything by its overscan safe area (90pt
        // left/right, 60pt top/bottom), so the paddings here stay small.
        HStack(alignment: .top, spacing: 40) {
            sidebar

            // Right -- hero banner for the focused game, then the grid.
            VStack(alignment: .center, spacing: 18) {
                heroBanner
                gameGrid
            }
            .frame(maxWidth: .infinity)
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
        .onChange(of: focusedGame) { _, newValue in
            if let newValue {
                heroGame = newValue
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
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                    .padding(40)
                    .background(TVTheme.yellow)
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

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuroraLogo()

            Text("Pick a game")
                .font(ShellTheme.display(28, weight: .semibold))
                .foregroundColor(ShellTheme.textSecondary)

            Capsule()
                .fill(ShellTheme.brandGradient)
                .frame(width: 120, height: 4)
                .opacity(0.8)
                .padding(.vertical, 2)

            // Game Night: a playlist of games with one running scoreboard.
            // Not part of the grid (and never handed initial focus), so the
            // grid's first-card focus and GameLabTVUITests are unaffected.
            if let onGameNight {
                Button(action: onGameNight) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Game Night")
                            .font(ShellTheme.display(28, weight: .heavy))
                        Text("A playlist, one scoreboard")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .buttonStyle(TVGameNightCardStyle())
                .accessibilityIdentifier("gameNightCard")
                .padding(.bottom, 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                CategoryPill(label: "All", accent: ShellTheme.cyan, isSelected: selectedCategory == nil) {
                    selectCategory(nil)
                }
                // Each pill carries its category's own accent (the same one
                // its cards wear), so the sidebar doubles as the grid's
                // colour legend rather than nine identical cyan pills.
                ForEach(GameID.listedCategories, id: \.self) { cat in
                    CategoryPill(label: cat.rawValue,
                                 accent: cat.tvStyle.accent,
                                 isSelected: selectedCategory == cat) {
                        selectCategory(selectedCategory == cat ? nil : cat)
                    }
                }
            }

            Spacer(minLength: 0)

            // Connection status dot -- breathes gently while reconnecting
            // so the state reads as "actively retrying", not stuck.
            HStack(spacing: 8) {
                Circle()
                    .fill(socket.isConnected ? TVTheme.green : TVTheme.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: socket.isConnected ? TVTheme.green : TVTheme.red, radius: 5)
                    .opacity(socket.isConnected ? 1 : (isPulsing ? 1 : 0.3))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
                Text(socket.isConnected ? "Server connected" : "Reconnecting…")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))

                // Build stamp -- which commit this build came from, so a
                // glance at the TV answers "is this running the new code?".
                Text(BuildStamp.displayString)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.top, 2)
            }
        }
        .frame(width: 290, alignment: .leading)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .padding(.leading, 24)
        // Gives the focus engine a clear boundary: moving right off the
        // last category jumps into the grid's own section below, rather
        // than the engine guessing at a target across two sibling stacks.
        .focusSection()
    }

    // MARK: Hero

    /// Not focusable: a live preview of whichever card holds focus. Each game
    /// change swaps the banner with a short rise-and-fade.
    private var heroBanner: some View {
        ZStack {
            TVGameHero(game: heroGame)
                .id(heroGame)
                .transition(.asymmetric(
                    insertion: .offset(y: 24).combined(with: .opacity),
                    removal: .opacity
                ))
        }
        .frame(width: Self.gridWidth, height: 220)
        .padding(.top, 20)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: heroGame)
    }

    // MARK: Grid

    private var gameGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(Self.columnWidth), spacing: Self.columnSpacing),
                               count: Self.columnCount),
                spacing: 40
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
                    //
                    // The 3D shell redesign deliberately left this
                    // Button/style/focused/identifier/Play-Pause chain
                    // exactly as it was: every new effect (depth slab,
                    // tilt, hop, shine, curved scroll) lives inside
                    // TVGameCard, i.e. inside the label.
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
            // Room above and below for the focused card's lift, scale and
            // glow, which the scroll view would otherwise clip.
            .padding(.top, 34)
            .padding(.bottom, 80)
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.25), value: selectedCategory)
        }
        .focusSection()
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

/// One game tile, styled as a chunky 3D block in the Swift Playgrounds idiom.
///
/// History: reported twice, verbatim, "Game icons are still the emoji with the
/// names which feels too basic", and later "the UI/UX is super basic". So each
/// card is now a physical-looking object: a coloured face in its
/// `GameCategory`'s gradient (see `TVCategoryStyle`) sitting on a darker slab
/// that reads as thickness, a glossy icon orb, a top-edge highlight and layered
/// contact + glow shadows. All drawn procedurally, no image assets.
///
/// Motion is spent only where the eye is:
///
///   * Every card bends with the scroll position (`scrollTransition`): rows
///     entering or leaving the top/bottom edge tilt back and shrink, so the
///     grid reads as a curved wall rather than a flat sheet.
///   * Only the focused card animates: it lifts toward the viewer, tilts
///     back, sways in 3D with the icon counter-moving for parallax, breathes a
///     category-coloured glow, gets a holographic shine sweep, and its icon
///     hops (KeyframeAnimator: anticipate, jump, squash, settle) the moment
///     focus lands. Unfocused cards hold still; offscreen ones do not exist
///     (LazyVGrid).
///   * No `Timer`: repeatForever animations and TimelineViews that only exist
///     while focused, so an idle card costs nothing.
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
    @State private var halo = false     // glow breathing
    @State private var sway = false     // slow 3D parallax tilt
    @State private var hopTrigger: Int = 0

    static let cardWidth: CGFloat = 280
    static let cardHeight: CGFloat = 268
    private static let corner: CGFloat = 30

    private var style: TVCategoryStyle { game.category.tvStyle }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
    }

    /// How far the slab peeks out below the face -- deeper when lifted.
    private var depth: CGFloat { isFocused ? 13 : 8 }

    var body: some View {
        cardBody
        .rotation3DEffect(.degrees(isFocused ? 8 : 0),
                          axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .rotation3DEffect(.degrees(isFocused ? (sway ? 5 : -5) : 0),
                          axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .offset(y: isFocused ? -8 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.66), value: isFocused)
        // Performance: the per-card scrollTransition "curved wall" and the
        // two blurred shadows on EVERY card made swiping through the grid
        // stutter on Apple TV (each was an offscreen render per card per
        // frame). Now unfocused cards are flat layers with a cheap,
        // unblurred contact shadow; only the focused card pays for
        // compositing and real shadows.
        .onChange(of: isFocused) { _, focused in setMotion(focused) }
        // A card can be created by LazyVGrid *after* the grid has already
        // handed it focus (initial focus is assigned in the parent's
        // .onAppear), in which case no isFocused change ever arrives here.
        .onAppear { if isFocused { setMotion(true) } }
    }

    // MARK: Layers

    @ViewBuilder
    private var cardBody: some View {
        if isFocused {
            ZStack {
                slab
                face
            }
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            // One composited layer, so the shadows below are cast by the
            // finished card rather than separately by each sublayer.
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.55), radius: 26, x: 0, y: 28)
            .shadow(color: style.accent.opacity(halo ? 0.75 : 0.4),
                    radius: halo ? 42 : 26, x: 0, y: 0)
        } else {
            ZStack {
                // Unblurred contact shadow: a dark copy of the shape.
                shape
                    .fill(Color.black.opacity(0.35))
                    .frame(width: Self.cardWidth, height: Self.cardHeight)
                    .offset(y: 14)
                slab
                face
            }
            .frame(width: Self.cardWidth, height: Self.cardHeight)
        }
    }

    /// The card's "thickness": a darker copy of its shape peeking out below.
    private var slab: some View {
        shape
            .fill(style.bottom)
            .overlay { shape.fill(Color.black.opacity(0.5)) }
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .offset(y: depth)
    }

    private var face: some View {
        ZStack {
            backgroundLayers
            cardContent
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .shellShine(isActive: isFocused, cornerRadius: Self.corner, period: 3.0, intensity: 0.32)
        .overlay(alignment: .topLeading) { categoryGlyph }
        // Small fixed-size icon badges pinned to a corner, entirely
        // independent of the text layout.
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 6) {
                if game.hasPrivateInfo {
                    GameBadge(systemImage: "eye.slash.fill", color: TVTheme.cyan)
                }
                if game.supportsRemote {
                    GameBadge(systemImage: "av.remote.fill", color: TVTheme.green)
                }
            }
            .padding(12)
        }
        .clipShape(shape)
        .overlay { borderStroke }
    }

    private var backgroundLayers: some View {
        ZStack {
            shape.fill(Color(hex: "150F30"))

            shape.fill(
                LinearGradient(colors: [style.top, style.bottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .opacity(isFocused ? 0.95 : 0.55)

            // Glossy top: light falling on the upper half of the block.
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(isFocused ? 0.26 : 0.14), location: 0.0),
                    .init(color: Color.white.opacity(0), location: 0.45)
                ],
                startPoint: .top, endPoint: .bottom
            )

            // Soft category-tinted spotlight behind the icon.
            RadialGradient(
                colors: [style.accent.opacity(isFocused ? 0.5 : 0.18), .clear],
                center: UnitPoint(x: 0.5, y: 0.36),
                startRadius: 6,
                endRadius: isFocused ? 160 : 120
            )

            // Bottom scrim: guarantees the title and player count stay legible
            // no matter how bright a category's gradient or the shine gets.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(0.5), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var cardContent: some View {
        VStack(spacing: 12) {
            ShellIconOrb(symbol: game.sfSymbol,
                         top: style.bottom,
                         bottom: style.top,
                         accent: style.accent,
                         size: 112,
                         isLit: isFocused)
                .shellHop(trigger: hopTrigger, height: 26)
                // Parallax: the icon drifts against the card's sway, so it
                // reads as floating above the face.
                .offset(x: isFocused ? (sway ? -7 : 7) : 0)
                .frame(height: 124)

            Text(game.displayName)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 1)

            Text("\(game.minPlayers)–\(game.maxPlayers) players")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(isFocused ? 0.9 : 0.6))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private var categoryGlyph: some View {
        Image(systemName: style.symbol)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(isFocused ? 0.95 : 0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background { Capsule().fill(Color.black.opacity(0.3)) }
            .padding(12)
    }

    private var borderStroke: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [Color.white.opacity(isFocused ? 0.85 : 0.35),
                         style.top.opacity(isFocused ? 0.6 : 0.2),
                         style.bottom.opacity(isFocused ? 0.5 : 0.1)],
                startPoint: .top, endPoint: .bottom
            ),
            lineWidth: isFocused ? 2.5 : 1.4
        )
    }

    // MARK: Motion

    /// Starts or stops every continuous effect in one place, so "only the
    /// focused card moves" is a single invariant rather than something each
    /// modifier has to be trusted to re-derive.
    private func setMotion(_ running: Bool) {
        guard running else {
            withAnimation(.easeOut(duration: 0.3)) {
                halo = false
                sway = false
            }
            return
        }
        hopTrigger += 1
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            halo = true
        }
        withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
            sway = true
        }
    }
}

/// Large, non-focusable preview of the focused game above the grid: a
/// slowly turning 3D icon orb, the title, and what the game needs.
private struct TVGameHero: View {
    let game: GameID

    private var style: TVCategoryStyle { game.category.tvStyle }

    var body: some View {
        HStack(spacing: 40) {
            ShellIconOrb(symbol: game.sfSymbol,
                         top: style.top,
                         bottom: style.bottom,
                         accent: style.accent,
                         size: 150,
                         isLit: true)
                .phaseAnimator([false, true]) { content, phase in
                    content
                        .rotation3DEffect(.degrees(phase ? 16 : -16),
                                          axis: (x: 0, y: 1, z: 0),
                                          perspective: 0.5)
                        .offset(y: phase ? -6 : 6)
                } animation: { _ in
                    Animation.easeInOut(duration: 2.6)
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: style.symbol)
                    Text(game.category.rawValue.uppercased())
                        .tracking(4)
                }
                .font(ShellTheme.eyebrow(20))
                .foregroundColor(style.accent)

                Text(game.displayName)
                    .font(ShellTheme.display(58))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(color: style.accent.opacity(0.5), radius: 16)

                HStack(spacing: 12) {
                    ShellChip(systemImage: "person.2.fill",
                              text: "\(game.minPlayers)–\(game.maxPlayers) players",
                              tint: Color.white.opacity(0.85))
                    if game.supportsRemote {
                        ShellChip(systemImage: "av.remote.fill", text: "Remote ready", tint: ShellTheme.mint)
                    }
                    if game.soloPlayable {
                        ShellChip(systemImage: "person.fill", text: "Solo", tint: ShellTheme.gold)
                    }
                    if game.hasPrivateInfo {
                        ShellChip(systemImage: "eye.slash.fill", text: "Secret hands", tint: ShellTheme.cyan)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundColor(style.accent)
                    .shadow(color: style.accent.opacity(0.7), radius: 12)
                Text("Select to play")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(ShellTheme.textTertiary)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ShellGlassSurface(cornerRadius: ShellTheme.cardRadius, tint: style.accent)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The wordmark, extruded: stacked hard-edged shadows give it a few pixels
/// of solid depth under a gradient face.
private struct AuroraLogo: View {
    var body: some View {
        Text("Aurora")
            .font(ShellTheme.display(60, weight: .black))
            .foregroundStyle(ShellTheme.brandGradient)
            .shadow(color: Color(hex: "3B1C7A"), radius: 0, x: 0, y: 2)
            .shadow(color: Color(hex: "2A1358"), radius: 0, x: 0, y: 4)
            .shadow(color: Color(hex: "1A0B3A"), radius: 0, x: 0, y: 6)
            .shadow(color: ShellTheme.violet.opacity(0.6), radius: 24, x: 0, y: 8)
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
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(color.opacity(0.85)))
    }
}

/// Sidebar category filter. Each carries its category's accent (the same one
/// its cards wear), as a glowing dot when idle and a full fill when selected,
/// so the sidebar doubles as the grid's colour legend. Drawn entirely by
/// ShellPillButtonStyle, which reads focus from the environment.
private struct CategoryPill: View {
    let label: String
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(isSelected ? Color.black.opacity(0.55) : accent)
                    .frame(width: 11, height: 11)
                    .shadow(color: accent.opacity(isSelected ? 0 : 0.8), radius: 4)
                Text(label)
                    .lineLimit(1)
            }
        }
        .buttonStyle(ShellPillButtonStyle(accent: accent, isSelected: isSelected))
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

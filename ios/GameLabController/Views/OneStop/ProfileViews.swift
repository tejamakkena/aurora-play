import SwiftUI

// MARK: - Player profile: name, colour, avatar, lifetime stats
//
// Server: games/profiles.py (GET/PUT /api/profile/<device>). The phone
// keeps its own copy in UserDefaults so the profile works offline and
// survives the free host wiping its JSON file; when the server comes back
// with something different, the local copy is re-sent.

enum ProfilePalette {
    /// Must match games/profiles.py _COLORS exactly (the server drops others).
    static let colors: [String] = ["red", "orange", "yellow", "green", "teal",
                                   "blue", "indigo", "purple", "pink", "brown"]

    /// SF Symbol names; the server accepts ^[a-z0-9.]{1,40}$.
    static let avatars: [String] = [
        "gamecontroller.fill", "star.fill", "bolt.fill", "flame.fill",
        "crown.fill", "hare.fill", "tortoise.fill", "cat.fill",
        "dog.fill", "bird.fill", "fish.fill", "leaf.fill",
        "moon.stars.fill", "music.note", "trophy.fill", "theatermasks.fill",
    ]

    static let defaultAvatar = "person.fill"

    /// The ten swatches are the Phone Play palette, not Apple's defaults, so
    /// a profile colour sits beside the rest of the app. `teal` and `brown`
    /// are the only two the server names that Phone Play has no token for, so
    /// they get hexes mixed to the same recipe (saturated, slightly warm).
    static func color(_ name: String) -> Color {
        switch name {
        case "red":    return PhonePlayDesign.red
        case "orange": return PhonePlayDesign.orange
        case "yellow": return PhonePlayDesign.yellow
        case "green":  return PhonePlayDesign.green
        case "teal":   return Color(hex: "2BD9C0")
        case "blue":   return PhonePlayDesign.blue
        case "indigo": return PhonePlayDesign.indigo
        case "purple": return PhonePlayDesign.purple
        case "pink":   return PhonePlayDesign.pink
        case "brown":  return Color(hex: "C98A5E")
        default:       return PhonePlayDesign.cyan
        }
    }

    /// Same default the server picks for a fresh device.
    static func defaultColor(for device: String) -> String {
        let sum = device.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[sum % colors.count]
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    /// Shared with JoinRoomView's @AppStorage so the join name and the
    /// profile name stay the same thing.
    static let nameKey = "aurora_player_name"
    private static let colorKey = "aurora_profile_color"
    private static let avatarKey = "aurora_profile_avatar"

    @Published var name: String
    @Published var color: String
    @Published var avatar: String
    @Published var stats: ProfileStats?
    @Published var isSyncing = false

    init() {
        let d = UserDefaults.standard
        name = d.string(forKey: Self.nameKey) ?? ""
        let savedColor = d.string(forKey: Self.colorKey) ?? ""
        color = ProfilePalette.colors.contains(savedColor)
            ? savedColor : ProfilePalette.defaultColor(for: AppConstants.deviceID)
        avatar = d.string(forKey: Self.avatarKey) ?? ProfilePalette.defaultAvatar
    }

    var tint: Color { ProfilePalette.color(color) }
    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Player" : n
    }

    private var hasLocalProfile: Bool {
        UserDefaults.standard.string(forKey: Self.colorKey) != nil
            || UserDefaults.standard.string(forKey: Self.avatarKey) != nil
    }

    private func persistLocal() {
        let d = UserDefaults.standard
        d.set(name, forKey: Self.nameKey)
        d.set(color, forKey: Self.colorKey)
        d.set(avatar, forKey: Self.avatarKey)
    }

    /// Pull stats (and, on a fresh install, the server's copy of the profile).
    func refresh() async {
        guard !isSyncing else { return }
        isSyncing = true
        let remote = await OneStopAPI.profile()
        isSyncing = false
        guard let remote else { return }
        stats = remote.stats

        if !hasLocalProfile {
            // Fresh install on a known device: adopt what the server has.
            if ProfilePalette.colors.contains(remote.color) { color = remote.color }
            if !remote.avatar.isEmpty { avatar = remote.avatar }
            if name.trimmingCharacters(in: .whitespaces).isEmpty && !remote.name.isEmpty {
                name = remote.name
            }
            return
        }
        // The server forgot us (free-tier restart) or is out of date.
        if remote.color != color || remote.avatar != avatar
            || (!name.isEmpty && remote.name != name) {
            if let saved = await OneStopAPI.saveProfile(name: name, color: color, avatar: avatar) {
                stats = saved.stats ?? stats
            }
        }
    }

    /// Saves locally first, then to the server. Returns false when offline
    /// (the local copy is kept and re-sent on the next refresh).
    func save(name newName: String, color newColor: String, avatar newAvatar: String) async -> Bool {
        let words = newName.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        name = String(words.joined(separator: " ").prefix(20))
        color = newColor
        avatar = newAvatar
        persistLocal()
        guard let saved = await OneStopAPI.saveProfile(name: name, color: color, avatar: avatar) else {
            return false
        }
        stats = saved.stats ?? stats
        return true
    }
}

// MARK: - Avatar bubble

struct ProfileAvatarBubble: View {
    let avatar: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.55)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: max(1, size / 30))
            Image(systemName: avatar)
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundColor(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(0.45), radius: size / 6, y: 2)
    }
}

// MARK: - Chip that opens the editor (join screen and lobby)

struct ProfileChipButton: View {
    @StateObject private var store = ProfileStore()
    @State private var showEditor = false

    var body: some View {
        Button { PhonePlayHaptics.tap(); showEditor = true } label: {
            HStack(spacing: 8) {
                ProfileAvatarBubble(avatar: store.avatar, tint: store.tint, size: 30)
                Text(store.name.isEmpty ? "Profile" : store.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                Image(systemName: "pencil")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(store.tint.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(OneStopPressStyle())
        .accessibilityLabel("Edit your profile")
        .sheet(isPresented: $showEditor) {
            ProfileEditorView(store: store)
        }
        .task { await store.refresh() }
    }
}

// MARK: - Editor sheet

struct ProfileEditorView: View {
    @ObservedObject var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var draftName = ""
    @State private var draftColor = "blue"
    @State private var draftAvatar = ProfilePalette.defaultAvatar
    @State private var saving = false
    @State private var offlineNote = false
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    private var tint: Color { ProfilePalette.color(draftColor) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    preview
                    nameSection
                    colorSection
                    avatarSection
                    statsSection
                    if offlineNote {
                        Label("Saved on this phone. It will sync when the server is reachable.",
                              systemImage: "icloud.slash")
                            .font(.footnote)
                            .foregroundColor(PhonePlayDesign.orange)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    OneStopPrimaryButton(title: saving ? "Saving..." : "Save profile",
                                         systemImage: "checkmark.circle.fill",
                                         colors: [tint, tint.opacity(0.6)],
                                         enabled: !saving) {
                        Task { await save() }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(OneStopTheme.background.ignoresSafeArea())
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .toolbarBackground(OneStopTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draftName = store.name
            draftColor = store.color
            draftAvatar = store.avatar
        }
        .task {
            if store.stats == nil { await store.refresh() }
        }
    }

    // MARK: Sections

    private var preview: some View {
        VStack(spacing: 10) {
            ProfileAvatarBubble(avatar: draftAvatar, tint: tint, size: 104)
                .symbolEffect(.bounce, value: draftAvatar)
            Text(draftName.trimmingCharacters(in: .whitespaces).isEmpty ? "Your name" : draftName)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.top, 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: draftColor)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("NAME")
            TextField("", text: $draftName)
                .placeholder(when: draftName.isEmpty) {
                    Text("What should the TV call you?").foregroundColor(.white.opacity(0.25))
                }
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { nameFocused = false }
                .onChange(of: draftName) {
                    if draftName.count > 20 { draftName = String(draftName.prefix(20)) }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(nameFocused ? tint : Color.white.opacity(0.1), lineWidth: 1.5))
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("COLOUR")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                ForEach(ProfilePalette.colors, id: \.self) { name in
                    let selected = name == draftColor
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { draftColor = name }
                    } label: {
                        ZStack {
                            Circle().fill(ProfilePalette.color(name))
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.headline.weight(.heavy))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 46, height: 46)
                        .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 3).padding(-5))
                        .scaleEffect(selected ? 1.08 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                }
            }
            .padding(.vertical, 6)
        }
        .oneStopCard(tint: tint)
    }

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("AVATAR")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(ProfilePalette.avatars, id: \.self) { symbol in
                    let selected = symbol == draftAvatar
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { draftAvatar = symbol }
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(selected ? .white : .white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(selected ? tint : Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(selected ? 0.5 : 0.08), lineWidth: 1)
                            )
                            .scaleEffect(selected ? 1.05 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                }
            }
        }
        .oneStopCard(tint: tint)
    }

    @ViewBuilder
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("LIFETIME STATS")
                Spacer()
                if store.isSyncing { ProgressView().scaleEffect(0.7).tint(.white.opacity(0.6)) }
            }
            if let s = store.stats {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    statTile("Games", s.played ?? 0, "gamecontroller.fill", PhonePlayDesign.cyan)
                    statTile("Wins", s.wins ?? 0, "trophy.fill", PhonePlayDesign.yellow)
                    statTile("Podiums", s.podiums ?? 0, "medal.fill", PhonePlayDesign.orange)
                    statTile("Nights", s.nights ?? 0, "moon.stars.fill", PhonePlayDesign.purple)
                    statTile("Night wins", s.nightWins ?? 0, "crown.fill", PhonePlayDesign.pink)
                }
            } else {
                Text(store.isSyncing ? "Fetching your stats..."
                     : "Stats appear here once the server is reachable and you have played a game.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .oneStopCard(tint: .white)
    }

    private func statTile(_ title: String, _ value: Int, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption.weight(.bold)).foregroundColor(color)
            Text("\(value)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())
            Text(title).font(.caption2).foregroundColor(.white.opacity(0.55)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.12)))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundColor(PhonePlayDesign.text3)
    }

    // MARK: Save

    private func save() async {
        nameFocused = false
        saving = true
        let ok = await store.save(name: draftName, color: draftColor, avatar: draftAvatar)
        saving = false
        if ok {
            dismiss()
        } else {
            withAnimation { offlineNote = true }
        }
    }
}

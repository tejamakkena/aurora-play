import SwiftUI

struct WaitingView: View {
    let room: Room
    let onReady: () -> Void
    let onLeave: () -> Void

    @State private var isReady = false

    var body: some View {
        VStack(spacing: 36) {
            // Once you've joined a room there was no way back to the join
            // screen at all -- reported directly. A wrong code/game or a
            // change of mind had nowhere to go.
            HStack {
                Button(action: onLeave) {
                    Label("Leave", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            // Game badge
            VStack(spacing: 12) {
                Image(systemName: room.gameID.sfSymbol)
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.85))
                Text(room.gameID.displayName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }

            // Room code (small reference)
            HStack(spacing: 8) {
                Text("Room")
                    .foregroundColor(.white.opacity(0.4))
                Text(room.code)
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundColor(.cyan)
            }

            // Player list
            VStack(spacing: 10) {
                ForEach(room.players) { player in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(player.isReady ? Color.green.opacity(0.3) : Color.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                            .overlay(Text(String(player.name.prefix(1))).foregroundColor(.white).font(.caption.bold()))

                        Text(player.name)
                            .foregroundColor(.white)

                        if player.isHost { Text("HOST").font(.caption2).foregroundColor(.cyan) }

                        Spacer()

                        Image(systemName: player.isReady ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(player.isReady ? .green : .white.opacity(0.2))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                }
            }
            .padding(.horizontal, 24)

            // Private info note
            if room.gameID.hasPrivateInfo {
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                    Text("Your private info will appear here when the game starts")
                        .font(.caption)
                }
                .foregroundColor(.cyan.opacity(0.7))
                .padding(.horizontal, 32)
            }

            Spacer()

            // Ready button
            Button(action: {
                isReady = true
                onReady()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isReady ? "checkmark.circle.fill" : "hand.thumbsup.fill")
                    Text(isReady ? "Ready!" : "I'm Ready")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isReady ? Color.green.opacity(0.3) : Color.cyan)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(isReady)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}

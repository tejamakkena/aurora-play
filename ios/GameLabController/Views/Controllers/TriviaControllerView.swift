import SwiftUI

/// Trivia phone controller — big tap buttons, race to answer first.
struct TriviaControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var selectedIndex: Int? = nil
    @State private var questionID: String = ""

    private var choices: [String] {
        privateData["choices"] as? [String] ?? []
    }

    private var currentQuestionID: String {
        privateData["questionID"] as? String ?? ""
    }

    private var hasAnswered: Bool { selectedIndex != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Trivia")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if let score = privateData["score"] as? Int {
                    Text("Score: \(score)")
                        .font(.subheadline.bold())
                        .foregroundColor(.cyan)
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.04))

            Spacer()

            if !hasAnswered {
                VStack(spacing: 16) {
                    Text("Tap your answer!")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.4))

                    ForEach(Array(choices.enumerated()), id: \.offset) { idx, choice in
                        AnswerButton(label: choice, index: idx, state: .idle) {
                            submit(index: idx)
                        }
                    }
                }
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.green)
                    Text("Answer submitted!")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text("Watch the TV for results")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
        .onChange(of: currentQuestionID) { newID in
            // New question — reset answer state
            if newID != questionID {
                selectedIndex = nil
                questionID = newID
            }
        }
        .onAppear { questionID = currentQuestionID }
    }

    private func submit(index: Int) {
        guard !hasAnswered else { return }
        selectedIndex = index
        onAction("answer", ["choiceIndex": index, "questionID": questionID])
    }
}

// MARK: - Answer button

struct AnswerButton: View {
    enum AnswerState { case idle, selected, correct, wrong }

    let label: String
    let index: Int
    let state: AnswerState
    let action: () -> Void

    private let letters = ["A", "B", "C", "D"]

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(letters[min(index, 3)])
                    .font(.headline.bold())
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(letterBG))
                    .foregroundColor(.white)

                Text(label)
                    .font(.body)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(tileBG)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(tileBorder, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(state == .selected ? 0.97 : 1.0)
        .animation(.spring(response: 0.2), value: state)
    }

    private var letterBG: Color {
        switch state {
        case .idle:     return Color.white.opacity(0.15)
        case .selected: return Color.cyan
        case .correct:  return Color.green
        case .wrong:    return Color.red
        }
    }

    private var tileBG: Color {
        switch state {
        case .idle:     return Color.white.opacity(0.06)
        case .selected: return Color.cyan.opacity(0.1)
        case .correct:  return Color.green.opacity(0.1)
        case .wrong:    return Color.red.opacity(0.08)
        }
    }

    private var tileBorder: Color {
        switch state {
        case .idle:     return Color.white.opacity(0.08)
        case .selected: return Color.cyan.opacity(0.5)
        case .correct:  return Color.green.opacity(0.7)
        case .wrong:    return Color.red.opacity(0.5)
        }
    }
}

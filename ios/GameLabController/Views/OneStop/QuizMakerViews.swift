import SwiftUI

// MARK: - Make-your-own quiz (host only, lobby)
//
// The host types a topic, the server's AI writes the questions
// (POST /api/decks/generate kind=quiz, games/ai_decks.py), the host
// tweaks them here and "Use these questions" sends them to the room with
// set_custom_questions. Trivia then plays them first.

/// Editable copy of a QuizQuestion. QuizQuestion's own id is its text, which
/// changes while typing, so the editor keys rows by a stable UUID instead.
struct QuizDraft: Identifiable, Equatable {
    let id: UUID
    var question: String
    var options: [String]
    var correct: Int

    init(_ q: QuizQuestion) {
        id = UUID()
        question = q.question
        var opts = Array(q.options.prefix(4))
        while opts.count < 4 { opts.append("") }
        options = opts
        correct = (0...3).contains(q.correct_answer) ? q.correct_answer : 0
    }

    var asQuestion: QuizQuestion {
        QuizQuestion(question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                     options: options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                     correct_answer: correct)
    }

    var isComplete: Bool { asQuestion.isComplete }
}

// MARK: Lobby entry card

struct QuizMakerCard: View {
    let room: Room

    @State private var showMaker = false
    @State private var loadedCount = 0
    @State private var loadedTopic = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(LinearGradient(colors: OneStopTheme.quizGradient,
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolEffect(.bounce, value: loadedCount)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Make a quiz")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(room.gameID == .trivia
                         ? "Any topic. Your questions play first."
                         : "Any topic. Your questions play first in Trivia.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
            }

            if loadedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                    Text(loadedSummary)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                    Spacer()
                    Button {
                        OneStopEvents.setCustomQuestions(roomCode: room.code, questions: [])
                        withAnimation { loadedCount = 0; loadedTopic = "" }
                    } label: {
                        Text("Clear")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.pink)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.green.opacity(0.12)))
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            OneStopSecondaryButton(title: loadedCount > 0 ? "Make another quiz" : "Write a quiz with AI",
                                   systemImage: "sparkles", tint: .cyan) {
                showMaker = true
            }
        }
        .oneStopCard(tint: .cyan)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: loadedCount)
        .sheet(isPresented: $showMaker) {
            QuizMakerView(roomCode: room.code) { count, topic in
                loadedCount = count
                loadedTopic = topic
            }
        }
    }

    private var loadedSummary: String {
        let noun = loadedCount == 1 ? "question" : "questions"
        return loadedTopic.isEmpty ? "\(loadedCount) custom \(noun) loaded"
            : "\(loadedCount) \(noun) on \(loadedTopic) loaded"
    }
}

// MARK: Maker sheet

struct QuizMakerView: View {
    let roomCode: String
    /// Called after the questions were sent: (count, topic).
    let onUsed: (Int, String) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Stage: Equatable {
        case compose
        case loading
        case preview
        case failed(String)
    }

    @State private var stage: Stage = .compose
    @State private var topic = ""
    @State private var count = 10
    @State private var familySafe = true
    @State private var language: ContentPack = .en
    @State private var drafts: [QuizDraft] = []
    @State private var expandedID: UUID? = nil
    @State private var slowServer = false
    @State private var retrying = false
    @State private var generateTask: Task<Void, Never>? = nil
    @FocusState private var topicFocused: Bool

    private static let counts = [5, 10, 15]
    private static let suggestions = ["Cricket", "Bollywood 90s", "Space", "Telugu cinema",
                                      "Animals", "World capitals", "Food", "Science"]

    private var trimmedTopic: String { topic.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var completeCount: Int { drafts.filter(\.isComplete).count }

    var body: some View {
        NavigationStack {
            ZStack {
                OneStopTheme.background.ignoresSafeArea()
                switch stage {
                case .compose:
                    composeView
                        .transition(.opacity)
                case .loading:
                    loadingView
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                case .preview:
                    previewView
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .failed(let message):
                    failedView(message)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: stage)
            .navigationTitle("Make a quiz")
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
        .onDisappear { generateTask?.cancel() }
    }

    // MARK: Compose

    private var composeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    label("TOPIC")
                    TextField("", text: $topic)
                        .placeholder(when: topic.isEmpty) {
                            Text("e.g. Tollywood 2000s").foregroundColor(.white.opacity(0.25))
                        }
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .focused($topicFocused)
                        .submitLabel(.go)
                        .onSubmit { startGenerating() }
                        .onChange(of: topic) {
                            if topic.count > 80 { topic = String(topic.prefix(80)) }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(topicFocused ? Color.cyan : Color.white.opacity(0.1), lineWidth: 1.5))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.suggestions, id: \.self) { s in
                                OneStopChip(title: s, selected: trimmedTopic == s, tint: .cyan) {
                                    topic = s
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        label("QUESTIONS")
                        Spacer()
                        ForEach(Self.counts, id: \.self) { c in
                            OneStopChip(title: "\(c)", selected: count == c, tint: .purple) { count = c }
                        }
                    }
                    Divider().overlay(Color.white.opacity(0.1))
                    VStack(alignment: .leading, spacing: 8) {
                        label("LANGUAGE")
                        HStack(spacing: 8) {
                            ForEach(ContentPack.allCases) { pack in
                                OneStopChip(title: pack.label, selected: language == pack, tint: .orange) {
                                    language = pack
                                }
                            }
                        }
                    }
                    Divider().overlay(Color.white.opacity(0.1))
                    Toggle(isOn: $familySafe) {
                        Label("Family safe", systemImage: "figure.2.and.child.holdinghands")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .tint(.green)
                }
                .oneStopCard(tint: .purple)

                OneStopPrimaryButton(title: "Write my quiz", systemImage: "wand.and.stars",
                                     colors: OneStopTheme.quizGradient,
                                     enabled: !trimmedTopic.isEmpty) {
                    startGenerating()
                }

                Text("The first request can take up to a minute while the server wakes up.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "wand.and.stars")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: OneStopTheme.quizGradient,
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text("Writing \(count) questions about \(trimmedTopic)")
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            ProgressView().tint(.cyan)
            if slowServer {
                Text(retrying
                     ? "Almost there. The server just woke up, asking again."
                     : "The server is waking up. This can take up to a minute the first time.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            Spacer()
            OneStopSecondaryButton(title: "Cancel", systemImage: "xmark", tint: .white) {
                generateTask?.cancel()
                stage = .compose
            }
        }
        .padding(28)
        .animation(.easeInOut, value: slowServer)
        .animation(.easeInOut, value: retrying)
    }

    // MARK: Failed

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cloud.drizzle.fill")
                .font(.system(size: 56))
                .foregroundColor(.orange)
            Text("No questions this time")
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
            Spacer()
            OneStopPrimaryButton(title: "Try again", systemImage: "arrow.clockwise",
                                 colors: OneStopTheme.quizGradient) {
                startGenerating()
            }
            OneStopSecondaryButton(title: "Change topic", systemImage: "pencil", tint: .white) {
                stage = .compose
            }
        }
        .padding(28)
    }

    // MARK: Preview and edit

    private var previewView: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trimmedTopic)
                                .font(.title3.weight(.heavy))
                                .foregroundColor(.white)
                            Text("Tap a question to edit it. Tap an answer to mark it correct.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(.bottom, 4)

                    ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                        QuizDraftCard(draft: binding(for: draft),
                                      number: index + 1,
                                      expanded: expandedID == draft.id,
                                      onToggle: {
                                          withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                              expandedID = expandedID == draft.id ? nil : draft.id
                                          }
                                      },
                                      onDelete: {
                                          withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                              drafts.removeAll { $0.id == draft.id }
                                              if expandedID == draft.id { expandedID = nil }
                                          }
                                      })
                        .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.9).combined(with: .opacity)))
                    }

                    if drafts.isEmpty {
                        Text("All questions deleted. Start over to write a new set.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.top, 20)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 10) {
                if completeCount < drafts.count {
                    Text("\(drafts.count - completeCount) unfinished question\(drafts.count - completeCount == 1 ? "" : "s") will be skipped.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                OneStopPrimaryButton(title: completeCount == 1 ? "Use this question" : "Use these \(completeCount) questions",
                                     systemImage: "paperplane.fill",
                                     colors: [.green, .teal],
                                     enabled: completeCount > 0) {
                    useQuestions()
                }
                Button {
                    stage = .compose
                } label: {
                    Text("Start over")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(OneStopTheme.background.opacity(0.96).ignoresSafeArea(edges: .bottom))
        }
    }

    private func binding(for draft: QuizDraft) -> Binding<QuizDraft> {
        let id = draft.id
        return Binding(
            get: { drafts.first(where: { $0.id == id }) ?? draft },
            set: { newValue in
                if let i = drafts.firstIndex(where: { $0.id == id }) { drafts[i] = newValue }
            }
        )
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .tracking(2)
            .foregroundColor(.white.opacity(0.5))
    }

    // MARK: Actions

    private func startGenerating() {
        guard !trimmedTopic.isEmpty else { return }
        topicFocused = false
        generateTask?.cancel()
        generateTask = Task { await generate() }
    }

    /// Render's free tier can take 30-60 s to wake, and a cold first request
    /// may time out or come back empty. One automatic retry covers that
    /// without making the host tap again.
    private func generate() async {
        let subject = trimmedTopic
        stage = .loading
        slowServer = false
        retrying = false
        let started = Date()
        let slowNote = Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if !Task.isCancelled { slowServer = true }
        }
        defer { slowNote.cancel() }

        var items = await OneStopAPI.quiz(topic: subject, count: count,
                                          familySafe: familySafe, language: language.rawValue)
        if Task.isCancelled { return }
        if items.isEmpty && Date().timeIntervalSince(started) > 15 {
            slowServer = true
            retrying = true
            items = await OneStopAPI.quiz(topic: subject, count: count,
                                          familySafe: familySafe, language: language.rawValue)
            if Task.isCancelled { return }
        }

        if items.isEmpty {
            stage = .failed("The quiz writer did not answer. The server may still be waking up, "
                            + "or AI questions are switched off. Wait a moment and try again, "
                            + "or try a different topic.")
        } else {
            drafts = items.map { QuizDraft($0) }
            expandedID = nil
            stage = .preview
        }
    }

    private func useQuestions() {
        let ready = drafts.filter(\.isComplete).map(\.asQuestion)
        guard !ready.isEmpty else { return }
        OneStopEvents.setCustomQuestions(roomCode: roomCode, questions: ready)
        onUsed(ready.count, trimmedTopic)
        dismiss()
    }
}

// MARK: - One editable question

struct QuizDraftCard: View {
    @Binding var draft: QuizDraft
    let number: Int
    let expanded: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    private static let letters = ["A", "B", "C", "D"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(number)")
                        .font(.caption.weight(.heavy))
                        .foregroundColor(.black)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(draft.isComplete ? Color.cyan : Color.orange))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.question.isEmpty ? "Untitled question" : draft.question)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(expanded ? nil : 2)
                        if !expanded {
                            Label(correctText, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.45))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                editor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .oneStopCard(tint: draft.isComplete ? .cyan : .orange, padding: 14)
    }

    private var correctText: String {
        guard draft.options.indices.contains(draft.correct) else { return "No answer marked" }
        let answer = draft.options[draft.correct].trimmingCharacters(in: .whitespaces)
        return answer.isEmpty ? "No answer marked" : answer
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Question", text: $draft.question, axis: .vertical)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(1...4)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))

            ForEach(0..<4, id: \.self) { i in
                let isCorrect = draft.correct == i
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { draft.correct = i }
                    } label: {
                        ZStack {
                            Circle().fill(isCorrect ? Color.green : Color.white.opacity(0.08))
                            if isCorrect {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.heavy))
                                    .foregroundColor(.black)
                            } else {
                                Text(Self.letters[i])
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mark option \(Self.letters[i]) correct")

                    TextField("Option \(Self.letters[i])", text: option(i))
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isCorrect ? Color.green.opacity(0.15) : Color.white.opacity(0.05))
                        )
                }
            }

            HStack {
                if !draft.isComplete {
                    Label("Needs a question and 4 different answers", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.pink)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func option(_ i: Int) -> Binding<String> {
        Binding(
            get: { draft.options.indices.contains(i) ? draft.options[i] : "" },
            set: { newValue in
                guard draft.options.indices.contains(i) else { return }
                draft.options[i] = String(newValue.prefix(80))
            }
        )
    }
}

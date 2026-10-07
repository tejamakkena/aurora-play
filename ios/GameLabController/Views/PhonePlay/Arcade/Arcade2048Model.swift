import SwiftUI

// MARK: - 2048 (Pocket Arcade)
//
// The classic 4x4 sliding puzzle. Swipe to slide every tile; two tiles of
// the same value that meet merge into one of double the value, and a new
// 2 (sometimes a 4) drops in after every move that changed the board.
// Reach 2048 to win, then keep going if you like. One undo per game; the
// best score lives in PocketArcadeStore.
//
// Tiles keep a stable id across moves so the view can slide the same tile
// view to its new cell. A tile swallowed by a merge is kept for a moment,
// parked on the cell it merged into, so it visibly slides there before it
// disappears.

enum Arcade2048Direction {
    case up, down, left, right
}

struct Arcade2048Tile: Identifiable, Equatable {
    let id: Int
    var value: Int
    var row: Int
    var col: Int
}

/// Points scored by one move, for the floating "+N" by the score.
struct Arcade2048Gain: Equatable {
    let id: Int
    let points: Int
}

struct Arcade2048Board: Equatable {
    static let size: Int = 4
    static let goal: Int = 2048

    private(set) var tiles: [Arcade2048Tile] = []
    private var nextID: Int = 1

    /// What one slide did.
    struct Slide {
        var moved: Bool = false
        var gained: Int = 0
        /// Tiles eaten by a merge, parked on the cell they merged into.
        var swallowed: [Arcade2048Tile] = []
    }

    var maxValue: Int { tiles.map { $0.value }.max() ?? 0 }

    /// A new board with two starting tiles.
    static func fresh() -> Arcade2048Board {
        var board = Arcade2048Board()
        _ = board.spawn()
        _ = board.spawn()
        return board
    }

    func tile(row: Int, col: Int) -> Arcade2048Tile? {
        tiles.first { $0.row == row && $0.col == col }
    }

    /// Drops a 2 (one time in ten a 4) on a random empty cell and returns
    /// the new tile's id, or nil when the board is full.
    @discardableResult
    mutating func spawn() -> Int? {
        var empty: [(row: Int, col: Int)] = []
        for row in 0..<Arcade2048Board.size {
            for col in 0..<Arcade2048Board.size where tile(row: row, col: col) == nil {
                empty.append((row: row, col: col))
            }
        }
        guard let cell = empty.randomElement() else { return nil }
        let id = nextID
        nextID += 1
        let value = Int.random(in: 0..<10) == 0 ? 4 : 2
        tiles.append(Arcade2048Tile(id: id, value: value, row: cell.row, col: cell.col))
        return id
    }

    /// Slides every tile towards `direction`, merging equal neighbours
    /// once per move. The board only changes when something moved.
    mutating func slide(_ direction: Arcade2048Direction) -> Slide {
        var result = Slide()
        var out: [Arcade2048Tile] = []
        for line in 0..<Arcade2048Board.size {
            // This row or column, the tile nearest the leading edge first.
            let inLine: [Arcade2048Tile] = tiles
                .filter { Arcade2048Board.line(of: $0, direction) == line }
                .sorted { Arcade2048Board.depth(of: $0, direction) < Arcade2048Board.depth(of: $1, direction) }
            var placed: [Arcade2048Tile] = []
            var lastMerged: Bool = false
            for tile in inLine {
                if let last = placed.last, !lastMerged, last.value == tile.value {
                    let index = placed.count - 1
                    placed[index].value *= 2
                    result.gained += placed[index].value
                    var eaten = tile
                    eaten.row = placed[index].row
                    eaten.col = placed[index].col
                    result.swallowed.append(eaten)
                    result.moved = true
                    lastMerged = true
                } else {
                    let cell = Arcade2048Board.cell(line: line, depth: placed.count, direction)
                    var moved = tile
                    if moved.row != cell.row || moved.col != cell.col {
                        result.moved = true
                    }
                    moved.row = cell.row
                    moved.col = cell.col
                    placed.append(moved)
                    lastMerged = false
                }
            }
            out.append(contentsOf: placed)
        }
        if result.moved {
            tiles = out
        }
        return result
    }

    /// False when the board is full and no two neighbours match.
    var canMove: Bool {
        let n = Arcade2048Board.size
        if tiles.count < n * n { return true }
        var grid: [[Int]] = Array(repeating: Array(repeating: 0, count: n), count: n)
        for tile in tiles where (0..<n).contains(tile.row) && (0..<n).contains(tile.col) {
            grid[tile.row][tile.col] = tile.value
        }
        for row in 0..<n {
            for col in 0..<n {
                let value = grid[row][col]
                if value == 0 { return true }
                if col + 1 < n && grid[row][col + 1] == value { return true }
                if row + 1 < n && grid[row + 1][col] == value { return true }
            }
        }
        return false
    }

    // MARK: Geometry of a slide

    /// Which row (left/right) or column (up/down) a tile slides along.
    private static func line(of tile: Arcade2048Tile, _ direction: Arcade2048Direction) -> Int {
        switch direction {
        case .left, .right: return tile.row
        case .up, .down:    return tile.col
        }
    }

    /// How far a tile is from the edge it slides towards.
    private static func depth(of tile: Arcade2048Tile, _ direction: Arcade2048Direction) -> Int {
        switch direction {
        case .left:  return tile.col
        case .right: return size - 1 - tile.col
        case .up:    return tile.row
        case .down:  return size - 1 - tile.row
        }
    }

    private static func cell(line: Int, depth: Int, _ direction: Arcade2048Direction) -> (row: Int, col: Int) {
        switch direction {
        case .left:  return (row: line, col: depth)
        case .right: return (row: line, col: size - 1 - depth)
        case .up:    return (row: depth, col: line)
        case .down:  return (row: size - 1 - depth, col: line)
        }
    }
}

// MARK: - Game state

@MainActor
final class Arcade2048Model: ObservableObject {
    @Published private(set) var board: Arcade2048Board = Arcade2048Board()
    /// Tiles eaten by the last move, still sliding into their merge.
    @Published private(set) var swallowed: [Arcade2048Tile] = []
    @Published private(set) var score: Int = 0
    @Published private(set) var best: Int = PocketArcadeStore.bestTiles
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var undoUsed: Bool = false
    /// The board is full and nothing can merge.
    @Published private(set) var stuck: Bool = false
    /// The "You made 2048" banner is up.
    @Published private(set) var showGoal: Bool = false
    @Published private(set) var moves: Int = 0
    @Published private(set) var gain: Arcade2048Gain? = nil

    private var undoBoard: Arcade2048Board? = nil
    private var undoScore: Int = 0
    private var reachedGoal: Bool = false
    private var ghostToken: Int = 0
    private var isActive: Bool = true

    /// The best to show while playing: this game counts once it beats it.
    var shownBest: Int { max(best, score) }
    var biggestTile: Int { board.maxValue }

    /// Everything to draw: swallowed tiles underneath, live tiles on top.
    var drawn: [Arcade2048Tile] { swallowed + board.tiles }

    func newGame() {
        ghostToken += 1
        board = Arcade2048Board.fresh()
        swallowed = []
        score = 0
        best = PocketArcadeStore.bestTiles
        canUndo = false
        undoUsed = false
        undoBoard = nil
        undoScore = 0
        stuck = false
        showGoal = false
        reachedGoal = false
        moves = 0
        gain = nil
        isActive = true
    }

    func swipe(_ direction: Arcade2048Direction) {
        guard isActive, !stuck, !showGoal else { return }
        var next = board
        let slide = next.slide(direction)
        guard slide.moved else { return }
        let before = board
        let beforeScore = score
        next.spawn()

        ghostToken += 1
        swallowed = slide.swallowed
        board = next
        score += slide.gained
        moves += 1
        if slide.gained > 0 {
            gain = Arcade2048Gain(id: moves, points: slide.gained)
        }
        if !undoUsed {
            undoBoard = before
            undoScore = beforeScore
            canUndo = true
        }

        if slide.gained > 0 {
            PhonePlayHaptics.rigid()
        } else {
            PhonePlayHaptics.tap()
        }
        if !reachedGoal && next.maxValue >= Arcade2048Board.goal {
            reachedGoal = true
            showGoal = true
            PhonePlayHaptics.success()
        } else if !next.canMove {
            stuck = true
            PhonePlayHaptics.error()
        }
        clearSwallowedSoon()
    }

    /// Takes back the last move. Once per game.
    func undo() {
        guard canUndo, let previous = undoBoard else { return }
        ghostToken += 1
        swallowed = []
        board = previous
        score = undoScore
        undoBoard = nil
        canUndo = false
        undoUsed = true
        stuck = false
        showGoal = false
        gain = nil
        PhonePlayHaptics.warning()
    }

    /// Past 2048 and playing on.
    func keepGoing() {
        guard showGoal else { return }
        showGoal = false
        if !board.canMove {
            stuck = true
        }
        PhonePlayHaptics.tap()
    }

    /// Saves the score if it is a new best and says whether it was.
    @discardableResult
    func commitBest() -> Bool {
        let isNew = PocketArcadeStore.submitTiles(score)
        best = PocketArcadeStore.bestTiles
        return isNew
    }

    func shutdown() {
        isActive = false
        ghostToken += 1
    }

    /// Lets the swallowed tiles finish sliding, then fades them out.
    private func clearSwallowedSoon() {
        guard !swallowed.isEmpty else { return }
        let token = ghostToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard let self, token == self.ghostToken else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                self.swallowed = []
            }
        }
    }
}

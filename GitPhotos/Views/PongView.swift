import SwiftUI

// MARK: - Game model

/// "Photon Pong" — classic Pong with a twist: the ball trails light, speeds up on
/// every rally, and your paddle shrinks the longer you survive.
@Observable
final class PongGame {
    enum Phase { case ready, playing, over }

    struct Ball {
        var pos: CGPoint
        var vel: CGVector
    }

    var phase: Phase = .ready
    var score = 0
    var best = Leaderboard.shared.top?.score ?? 0

    private(set) var ball = Ball(pos: .zero, vel: .zero)
    private(set) var trail: [CGPoint] = []
    private(set) var playerX: CGFloat = 0
    private(set) var aiX: CGFloat = 0
    private(set) var size: CGSize = .zero

    private var speedMul: CGFloat = 1
    private var lastDate: Date?

    // Geometry
    let radius: CGFloat = 11
    let paddleH: CGFloat = 16
    private let baseSpeed: CGFloat = 380
    private var topY: CGFloat { 130 }
    private var bottomY: CGFloat { size.height - 130 }
    var paddleW: CGFloat { max(70, 150 - CGFloat(score) * 4) }

    // Colors
    static let player = Color(red: 0.20, green: 0.95, blue: 1.0)
    static let ai = Color(red: 1.0, green: 0.25, blue: 0.7)

    func configure(size: CGSize) {
        self.size = size
        if phase == .ready { resetBall(); centerPaddles() }
    }

    private func centerPaddles() {
        playerX = size.width / 2
        aiX = size.width / 2
    }

    private func resetBall() {
        speedMul = 1
        trail.removeAll()
        let angle = CGFloat.random(in: -0.5...0.5)
        let dir: CGFloat = Bool.random() ? 1 : -1
        ball = Ball(
            pos: CGPoint(x: size.width / 2, y: size.height / 2),
            vel: CGVector(dx: sin(angle) * baseSpeed, dy: dir * cos(angle) * baseSpeed))
    }

    func tap() {
        switch phase {
        case .ready, .over:
            score = 0
            centerPaddles()
            resetBall()
            phase = .playing
            lastDate = nil
        case .playing:
            break
        }
    }

    func movePlayer(to x: CGFloat) {
        let half = paddleW / 2
        playerX = min(max(x, half), size.width - half)
    }

    func tick(date: Date, size: CGSize) {
        self.size = size
        guard phase == .playing else { lastDate = date; return }
        let dt = min(max(date.timeIntervalSince(lastDate ?? date), 0), 1.0 / 30.0)
        lastDate = date
        guard dt > 0 else { return }
        let d = CGFloat(dt)

        var b = ball
        b.pos.x += b.vel.dx * d
        b.pos.y += b.vel.dy * d

        // Side walls
        if b.pos.x < radius { b.pos.x = radius; b.vel.dx = abs(b.vel.dx) }
        if b.pos.x > size.width - radius { b.pos.x = size.width - radius; b.vel.dx = -abs(b.vel.dx) }

        // AI paddle (top): track the ball, but imperfectly so it's beatable.
        let aiSpeed = baseSpeed * 0.78
        let aiTarget = b.pos.x
        if abs(aiTarget - aiX) > 4 {
            aiX += (aiTarget > aiX ? 1 : -1) * min(aiSpeed * d, abs(aiTarget - aiX))
        }
        aiX = min(max(aiX, paddleW / 2), size.width - paddleW / 2)

        // Player paddle (bottom)
        if b.vel.dy > 0, b.pos.y + radius >= bottomY - paddleH / 2, b.pos.y < bottomY,
           abs(b.pos.x - playerX) <= paddleW / 2 + radius {
            b = bounce(b, off: playerX, atY: bottomY - paddleH / 2 - radius, downward: false)
            score += 1
            if score > best { best = score }
        }

        // AI paddle
        if b.vel.dy < 0, b.pos.y - radius <= topY + paddleH / 2, b.pos.y > topY,
           abs(b.pos.x - aiX) <= paddleW / 2 + radius {
            b = bounce(b, off: aiX, atY: topY + paddleH / 2 + radius, downward: true)
        }

        // Scoring / death
        if b.pos.y - radius < 0 {
            // AI missed — you scored. New ball.
            ball = b
            resetBall()
            return
        }
        if b.pos.y - radius > size.height {
            // You missed — game over.
            ball = b
            phase = .over
            return
        }

        trail.append(b.pos)
        if trail.count > 16 { trail.removeFirst(trail.count - 16) }
        ball = b
    }

    private func bounce(_ ball: Ball, off paddleCenter: CGFloat, atY y: CGFloat, downward: Bool) -> Ball {
        var b = ball
        b.pos.y = y
        speedMul = min(speedMul + 0.05, 2.6)
        let offset = (b.pos.x - paddleCenter) / (paddleW / 2)   // -1...1
        let speed = baseSpeed * speedMul
        let vx = offset * speed * 0.75
        let vy = sqrt(max(speed * speed - vx * vx, 1)) * (downward ? 1 : -1)
        b.vel = CGVector(dx: vx, dy: vy)
        return b
    }

    // MARK: Rendering

    func render(into ctx: inout GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.03, green: 0.04, blue: 0.10)))

        // Center net
        var net = Path()
        var y: CGFloat = 0
        while y < size.height {
            net.addRect(CGRect(x: size.width / 2 - 1.5, y: y, width: 3, height: 16))
            y += 30
        }
        ctx.fill(net, with: .color(.white.opacity(0.08)))

        // Score, faint and large behind play
        let scoreText = Text("\(score)").font(.system(size: 120, weight: .heavy, design: .rounded))
        ctx.draw(scoreText.foregroundColor(.white.opacity(0.05)), at: CGPoint(x: size.width / 2, y: size.height / 2))

        // Ball trail
        for (i, p) in trail.enumerated() {
            let t = CGFloat(i) / CGFloat(max(trail.count - 1, 1))
            let r = radius * (0.3 + 0.7 * t)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(Self.player.opacity(0.06 + 0.25 * t)))
        }

        // Paddles
        let player = roundedBar(centerX: playerX, centerY: bottomY)
        let ai = roundedBar(centerX: aiX, centerY: topY)
        ctx.fill(player, with: .color(Self.player.opacity(0.25)))   // glow
        ctx.fill(player.strokedPath(.init(lineWidth: 0)), with: .color(Self.player))
        ctx.fill(roundedBar(centerX: playerX, centerY: bottomY, inset: 3), with: .color(Self.player))
        ctx.fill(ai, with: .color(Self.ai.opacity(0.25)))
        ctx.fill(roundedBar(centerX: aiX, centerY: topY, inset: 3), with: .color(Self.ai))

        // Ball with glow
        for (r, a) in [(radius * 2.4, 0.18), (radius * 1.6, 0.3), (radius, 1.0)] {
            ctx.fill(Path(ellipseIn: CGRect(x: ball.pos.x - r, y: ball.pos.y - r, width: r * 2, height: r * 2)),
                     with: .color(.white.opacity(a)))
        }
    }

    private func roundedBar(centerX: CGFloat, centerY: CGFloat, inset: CGFloat = 0) -> Path {
        let rect = CGRect(x: centerX - paddleW / 2 + inset, y: centerY - paddleH / 2 + inset,
                          width: paddleW - inset * 2, height: paddleH - inset * 2)
        return Path(roundedRect: rect, cornerRadius: (paddleH - inset * 2) / 2)
    }
}

// MARK: - Leaderboard

struct ScoreEntry: Codable, Identifiable {
    var id = UUID()
    var initials: String
    var score: Int
}

final class Leaderboard {
    static let shared = Leaderboard()
    private let key = "pongLeaderboard"

    private(set) var entries: [ScoreEntry] = []
    var top: ScoreEntry? { entries.first }

    init() { load() }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ScoreEntry].self, from: data) {
            entries = decoded
        }
    }

    func submit(initials: String, score: Int) {
        let clean = String(initials.uppercased().prefix(3))
        entries.append(ScoreEntry(initials: clean.isEmpty ? "AAA" : clean, score: score))
        entries.sort { $0.score > $1.score }
        entries = Array(entries.prefix(10))
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func isHighScore(_ score: Int) -> Bool {
        score > 0 && (entries.count < 10 || score > (entries.last?.score ?? 0))
    }
}

// MARK: - View

@MainActor
struct PongView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var game = PongGame()
    @State private var initials = ""
    @State private var submitted = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, size in
                        game.render(into: &ctx, size: size)
                    }
                    .onChange(of: timeline.date) { _, date in
                        game.tick(date: date, size: geo.size)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in game.movePlayer(to: value.location.x) }
                )
                .onTapGesture { game.tap() }

                overlay
            }
            .ignoresSafeArea()
            .onAppear { game.configure(size: geo.size) }
            .onChange(of: geo.size) { _, newValue in game.configure(size: newValue) }
        }
        .background(.black)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }.tint(.white)
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("Photon Pong")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var overlay: some View {
        switch game.phase {
        case .ready:
            banner {
                Text("PHOTON PONG").font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(PongGame.player)
                Text("Drag to move your paddle.\nThe ball speeds up every rally — your paddle shrinks. Survive.")
                    .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
                Label("Tap to start", systemImage: "hand.tap").foregroundStyle(.white)
            }
        case .playing:
            EmptyView()
        case .over:
            gameOver
        }
    }

    private var gameOver: some View {
        banner {
            Text("GAME OVER").font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(PongGame.ai)
            Text("Score \(game.score)   ·   Best \(game.best)")
                .font(.headline).foregroundStyle(.white)

            if Leaderboard.shared.isHighScore(game.score) && !submitted {
                VStack(spacing: 10) {
                    Text("New high score! Enter your initials:")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    TextField("AAA", text: $initials)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(width: 140)
                        .padding(8)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                        .onChange(of: initials) { _, v in initials = String(v.uppercased().prefix(3)) }
                    Button("Save score") {
                        Leaderboard.shared.submit(initials: initials, score: game.score)
                        submitted = true
                    }.buttonStyle(.borderedProminent)
                }
            } else {
                leaderboardList
            }

            Button {
                initials = ""; submitted = false
                game.tap()
            } label: {
                Label("Play again", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(PongGame.player)
        }
    }

    private var leaderboardList: some View {
        VStack(spacing: 4) {
            ForEach(Array(Leaderboard.shared.entries.prefix(5).enumerated()), id: \.element.id) { i, entry in
                HStack {
                    Text("\(i + 1).").foregroundStyle(.white.opacity(0.5))
                    Text(entry.initials).font(.system(.body, design: .monospaced).bold())
                    Spacer()
                    Text("\(entry.score)").foregroundStyle(PongGame.player)
                }
                .foregroundStyle(.white)
            }
        }
        .frame(width: 200)
    }

    private func banner<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 18) { content() }
            .padding(28)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.1)))
            .padding(32)
    }
}

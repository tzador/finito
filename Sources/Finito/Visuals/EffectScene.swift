import SpriteKit

/// Base class for every visual effect. Handles frame timing, timed one-shot events, rate-based
/// spawners and the "everything is gone" notification. Subclasses override `fire()` to kick off
/// the show, `step(dt:)` to advance it and `liveCount` to report how much is still on screen.
class EffectScene: SKScene {
    var onIdle: (() -> Void)?
    var isIdle: Bool { spawners.isEmpty && timers.isEmpty && liveCount == 0 }

    /// Number of things still animating. The scene is idle once this hits zero and no spawners
    /// or timers are pending.
    var liveCount: Int { 0 }
    /// Upper bound on `liveCount`; spawners stop emitting while it is reached.
    var maxLive: Int { 1500 }

    private struct Spawner {
        var remaining: CGFloat
        var rate: CGFloat
        var accumulator: CGFloat = 0
        let make: () -> Void
    }

    private struct TimedEvent {
        let fireAt: CGFloat
        let block: () -> Void
    }

    private(set) var elapsed: CGFloat = 0
    private var spawners: [Spawner] = []
    private var timers: [TimedEvent] = []
    private var lastTime: TimeInterval?
    private var notifiedIdle = true

    var width: CGFloat { size.width }
    var height: CGFloat { size.height }

    // MARK: - Lifecycle

    func burst() {
        notifiedIdle = false
        fire()
    }

    /// Start the effect: add spawners, timers and nodes.
    func fire() {}

    /// Advance the simulation by `dt` seconds.
    func step(dt: CGFloat) {}

    // MARK: - Scheduling helpers

    /// Calls `make` `rate` times per second for `seconds`.
    func emit(for seconds: CGFloat, rate: CGFloat, _ make: @escaping () -> Void) {
        spawners.append(Spawner(remaining: seconds, rate: rate, make: make))
    }

    /// Calls `make` `count` times spread evenly over `seconds` (or all at once when `seconds` is 0).
    func emit(count: Int, over seconds: CGFloat, _ make: @escaping () -> Void) {
        guard seconds > 0 else { for _ in 0..<count { make() }; return }
        spawners.append(Spawner(remaining: seconds, rate: CGFloat(count) / seconds, accumulator: 0.999, make: make))
    }

    /// Runs `block` once, `seconds` from now.
    func after(_ seconds: CGFloat, _ block: @escaping () -> Void) {
        timers.append(TimedEvent(fireAt: elapsed + seconds, block: block))
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(min(1.0 / 30.0, lastTime.map { currentTime - $0 } ?? 1.0 / 60.0))
        lastTime = currentTime
        elapsed += dt

        let due = timers.filter { $0.fireAt <= elapsed }
        timers.removeAll { $0.fireAt <= elapsed }
        due.forEach { $0.block() }

        for i in spawners.indices.reversed() {
            spawners[i].remaining -= dt
            spawners[i].accumulator += spawners[i].rate * dt
            while spawners[i].accumulator >= 1, liveCount < maxLive {
                spawners[i].accumulator -= 1
                spawners[i].make()
            }
            if spawners[i].remaining <= 0 { spawners.remove(at: i) }
        }

        step(dt: dt)

        if isIdle, !notifiedIdle {
            notifiedIdle = true
            onIdle?()
        }
    }
}

// MARK: - Small math helpers shared by the effects

extension CGFloat {
    static func random(_ range: ClosedRange<CGFloat>) -> CGFloat { .random(in: range) }
    static var randomAngle: CGFloat { .random(in: 0...(2 * .pi)) }
    static var randomSign: CGFloat { Bool.random() ? 1 : -1 }
}

func smoothstep(_ x: CGFloat) -> CGFloat {
    let t = min(1, max(0, x))
    return t * t * (3 - 2 * t)
}

func easeOut(_ x: CGFloat) -> CGFloat {
    let t = min(1, max(0, x))
    return 1 - (1 - t) * (1 - t) * (1 - t)
}

/// Fade-in over `inSeconds`, fade-out during the last `outSeconds` of `life`.
func lifeEnvelope(age: CGFloat, life: CGFloat, inSeconds: CGFloat, outSeconds: CGFloat) -> CGFloat {
    let fadeIn = inSeconds > 0 ? min(1, age / inSeconds) : 1
    let fadeOut = outSeconds > 0 ? min(1, max(0, life - age) / outSeconds) : 1
    return fadeIn * fadeOut
}

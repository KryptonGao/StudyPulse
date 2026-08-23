//
//  TagGraphLayout.swift
//  StudyPulse
//
//  Force-directed layout for the tag graph.
//  Implements a simplified Fruchterman-Reingold algorithm in pure Swift.
//
//  Usage:
//      let layout = TagGraphLayout.layout(
//          tags: tagList,        // ["函数", "三角", ...]
//          edges: edgeList,      // [(a, b, weight)]
//          size: canvasSize,
//          iterations: 100
//      )
//      let point = layout["函数"]
//
//

import CoreGraphics
import Foundation

/// Pure-Swift 2D force-directed layout (Fruchterman-Reingold flavor).
/// - Repulsion between all pairs (1/d²)
/// - Attraction along edges (proportional to log(weight+1) × d)
/// - Step length cooled over iterations
/// - Positions clamped to canvas bounds (with a small margin so labels don't clip)
enum TagGraphLayout {

    /// Edge between two tags with shared-mistake weight.
    /// `weight` is the number of mistakes carrying both tags.
    struct Edge: Equatable {
        let a: String
        let b: String
        let weight: Int
    }

    /// Layout result: dictionary from tag → position in canvas coordinates.
    typealias Result = [String: CGPoint]

    /// Run the layout.
    /// - Parameters:
    ///   - tags: List of unique tag names.
    ///   - edges: Weighted edges. Self-loops and unknown endpoints are ignored.
    ///   - size: Canvas size.
    ///   - iterations: Force-iteration count (default 100).
    ///   - margin: Padding inside canvas (default 60pt) so labels don't clip.
    /// - Returns: Map of tag → CGPoint in canvas space.
    static func layout(
        tags: [String],
        edges: [Edge],
        size: CGSize,
        iterations: Int = 100,
        margin: CGFloat = 60
    ) -> Result {
        guard !tags.isEmpty else { return [:] }

        // Force-directed: only meaningful for ≥2 nodes. For 1 node, center it.
        if tags.count == 1, let only = tags.first {
            return [only: CGPoint(x: size.width / 2, y: size.height / 2)]
        }

        // Initial positions: evenly distributed on a circle of radius r.
        // Deterministic for a given set so consecutive "Recenter" runs are stable.
        let positions = initialPositions(tags: tags, size: size, margin: margin)

        // Edges keyed by sorted tuple, deduped (sum weights).
        let edgeMap = buildEdgeMap(tags: tags, edges: edges)

        let k = idealEdgeLength(for: tags.count, size: size, margin: margin)
        let initialTemperature = max(20.0, min(size.width, size.height) * 0.10)
        let cooling = coolingFactor(initial: initialTemperature, iterations: iterations)

        var current = positions
        let minX = margin
        let maxX = max(margin + 1, size.width - margin)
        let minY = margin
        let maxY = max(margin + 1, size.height - margin)

        for iter in 0..<iterations {
            let temperature = initialTemperature * pow(cooling, Double(iter) / Double(max(1, iterations - 1)))
            var forces: [String: CGPoint] = Dictionary(tags.map { ($0, .zero) }, uniquingKeysWith: { first, _ in first })

            // 1) Repulsion between every pair.
            for i in 0..<tags.count {
                let ti = tags[i]
                let pi = current[ti] ?? .zero
                for j in (i + 1)..<tags.count {
                    let tj = tags[j]
                    let pj = current[tj] ?? .zero
                    let dx = pi.x - pj.x
                    let dy = pi.y - pj.y
                    let dist = max(0.5, sqrt(dx * dx + dy * dy))
                    let f = (k * k) / dist
                    let ux = dx / dist
                    let uy = dy / dist
                    forces[ti, default: .zero].x += f * ux
                    forces[ti, default: .zero].y += f * uy
                    forces[tj, default: .zero].x -= f * ux
                    forces[tj, default: .zero].y -= f * uy
                }
            }

            // 2) Attraction along edges (log-scaled weight so heavy edges pull harder).
            for (key, w) in edgeMap {
                let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let a = String(parts[0])
                let b = String(parts[1])
                guard let pa = current[a], let pb = current[b] else { continue }
                let dx = pa.x - pb.x
                let dy = pa.y - pb.y
                let dist = max(0.5, sqrt(dx * dx + dy * dy))
                let f = (dist * dist) / k * log2(Double(w) + 1.0)
                let ux = dx / dist
                let uy = dy / dist
                forces[a, default: .zero].x -= f * ux
                forces[a, default: .zero].y -= f * uy
                forces[b, default: .zero].x += f * ux
                forces[b, default: .zero].y += f * uy
            }

            // 3) Apply forces with cooling temperature.
            for tag in tags {
                let f = forces[tag] ?? .zero
                let mag = sqrt(f.x * f.x + f.y * f.y)
                if mag < 0.0001 { continue }
                let cap = min(mag, temperature)
                let ux = f.x / mag
                let uy = f.y / mag
                var p = current[tag] ?? .zero
                p.x += ux * cap
                p.y += uy * cap
                p.x = min(maxX, max(minX, p.x))
                p.y = min(maxY, max(minY, p.y))
                current[tag] = p
            }
        }

        return current
    }

    // MARK: - Helpers / 辅助函数

    /// 均匀圆形初始化位置(确定性 + hash 抖动)
    /// Deterministic initial positions: even spacing on a circle centered in the canvas.
    private static func initialPositions(
        tags: [String],
        size: CGSize,
        margin: CGFloat
    ) -> Result {
        let cx = size.width / 2
        let cy = size.height / 2
        let r = min(size.width, size.height) / 2 - margin
        var out: Result = [:]
        for (i, tag) in tags.enumerated() {
            // Use a stable per-tag angle so the same set yields the same starting layout.
            let baseAngle = (Double(i) / Double(tags.count)) * 2 * .pi
            // Hash-driven tiny jitter so non-symmetric tag sets don't all start on a single spoke.
            let jitter = Double((abs(tag.hashValue) % 1000)) / 1000.0 * 0.2 - 0.1
            let angle = baseAngle + jitter
            out[tag] = CGPoint(
                x: cx + r * CGFloat(cos(angle)),
                y: cy + r * CGFloat(sin(angle))
            )
        }
        return out
    }

    /// Ideal edge length k: typical Fruchterman-Reingold choice √(area / n).
    private static func idealEdgeLength(
        for count: Int,
        size: CGSize,
        margin: CGFloat
    ) -> CGFloat {
        let area = max(1, (size.width - margin * 2) * (size.height - margin * 2))
        let k = CGFloat(sqrt(Double(area) / Double(max(1, count))))
        return max(40, min(k, 220))
    }

    /// Cooling schedule: from 1.0 to ~0.01 over the iterations.
    private static func coolingFactor(initial: Double, iterations: Int) -> Double {
        guard iterations > 1 else { return 0.01 }
        return pow(0.01 / initial, 1.0 / Double(iterations - 1))
    }

    /// Build a deduped edge map keyed by "lowercaseA|lowercaseB" (sorted).
    private static func buildEdgeMap(tags: [String], edges: [Edge]) -> [String: Int] {
        var map: [String: Int] = [:]
        let valid = Set(tags.map { $0.lowercased() })
        for e in edges {
            let aLow = e.a.lowercased()
            let bLow = e.b.lowercased()
            if aLow == bLow { continue }
            guard valid.contains(aLow), valid.contains(bLow) else { continue }
            let key = [aLow, bLow].sorted().joined(separator: "|")
            map[key, default: 0] += max(1, e.weight)
        }
        return map
    }
}

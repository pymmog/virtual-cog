import Foundation

struct CoursePoint: Equatable {
    var distanceMeters: Double
    var elevationMeters: Double
    var latitude: Double?
    var longitude: Double?
    var gradePercent: Double
}

struct Course: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var points: [CoursePoint]
    var sourceURL: URL?

    var totalDistanceMeters: Double { points.last?.distanceMeters ?? 0 }
    var totalElevationGainMeters: Double {
        zip(points, points.dropFirst()).reduce(0) { partial, pair in
            let delta = pair.1.elevationMeters - pair.0.elevationMeters
            return partial + max(0, delta)
        }
    }

    func grade(atDistance meters: Double) -> Double {
        guard !points.isEmpty else { return 0 }
        if meters <= points.first!.distanceMeters { return points.first!.gradePercent }
        if meters >= points.last!.distanceMeters { return points.last!.gradePercent }
        // Binary search segment
        var lo = 0
        var hi = points.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if points[mid].distanceMeters <= meters { lo = mid } else { hi = mid }
        }
        let a = points[lo]
        let b = points[hi]
        let span = max(0.001, b.distanceMeters - a.distanceMeters)
        let t = (meters - a.distanceMeters) / span
        return a.gradePercent + (b.gradePercent - a.gradePercent) * t
    }
}

enum GPXParser {
    static func parse(data: Data, name hint: String? = nil) throws -> Course {
        let xml = String(data: data, encoding: .utf8) ?? ""
        let trkpts = extractTrackPoints(from: xml)
        guard trkpts.count >= 2 else { throw CourseError.notEnoughPoints }

        var distance = 0.0
        var raw: [(d: Double, e: Double, lat: Double?, lon: Double?)] = []
        raw.append((0, trkpts[0].ele, trkpts[0].lat, trkpts[0].lon))
        for i in 1..<trkpts.count {
            let prev = trkpts[i - 1]
            let cur = trkpts[i]
            if let la0 = prev.lat, let lo0 = prev.lon, let la1 = cur.lat, let lo1 = cur.lon {
                distance += haversineMeters(lat1: la0, lon1: lo0, lat2: la1, lon2: lo1)
            } else {
                distance += 5.0 // fallback spacing when lat/lon missing
            }
            raw.append((distance, cur.ele, cur.lat, cur.lon))
        }

        let smoothed = smoothElevation(raw.map(\.e), window: 5)
        let gradeWindowMeters = 25.0
        var points: [CoursePoint] = []
        for i in raw.indices {
            let grade = gradeAt(index: i, distances: raw.map(\.d), elevations: smoothed, windowMeters: gradeWindowMeters)
            points.append(
                CoursePoint(
                    distanceMeters: raw[i].d,
                    elevationMeters: smoothed[i],
                    latitude: raw[i].lat,
                    longitude: raw[i].lon,
                    gradePercent: grade
                )
            )
        }

        let name = hint
            ?? extractTag(xml, "name")
            ?? "Imported Course"
        return Course(name: name, points: points)
    }

    static func parse(url: URL) throws -> Course {
        let data = try Data(contentsOf: url)
        return try parse(data: data, name: url.deletingPathExtension().lastPathComponent)
    }

    private struct RawPoint {
        var lat: Double?
        var lon: Double?
        var ele: Double
    }

    private static func extractTrackPoints(from xml: String) -> [RawPoint] {
        // Lightweight GPX scrape without full XML DOM dependency.
        var points: [RawPoint] = []
        let pattern = #"<trkpt([^>]*)>([\s\S]*?)</trkpt>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return points
        }
        let ns = xml as NSString
        let matches = regex.matches(in: xml, options: [], range: NSRange(location: 0, length: ns.length))
        for match in matches {
            let attrs = ns.substring(with: match.range(at: 1))
            let body = ns.substring(with: match.range(at: 2))
            let lat = Double(attr(attrs, "lat") ?? "")
            let lon = Double(attr(attrs, "lon") ?? "")
            let ele = Double(extractTag(body, "ele") ?? "0") ?? 0
            points.append(RawPoint(lat: lat, lon: lon, ele: ele))
        }
        return points
    }

    private static func attr(_ attrs: String, _ name: String) -> String? {
        let pattern = #"\#(name)\s*=\s*\"([^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = attrs as NSString
        guard let match = regex.firstMatch(in: attrs, options: [], range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1
        else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func extractTag(_ xml: String, _ tag: String) -> String? {
        let pattern = #"<\#(tag)[^>]*>([^<]*)</\#(tag)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = xml as NSString
        guard let match = regex.firstMatch(in: xml, options: [], range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1
        else { return nil }
        return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func smoothElevation(_ values: [Double], window: Int) -> [Double] {
        guard window > 1, values.count > 1 else { return values }
        let half = window / 2
        return values.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(values.count - 1, i + half)
            let slice = values[lo...hi]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    static func gradeAt(index: Int, distances: [Double], elevations: [Double], windowMeters: Double) -> Double {
        let d0 = distances[index]
        var j = index
        while j + 1 < distances.count, distances[j] - d0 < windowMeters / 2 {
            j += 1
        }
        var i = index
        while i > 0, d0 - distances[i] < windowMeters / 2 {
            i -= 1
        }
        let dd = distances[j] - distances[i]
        guard dd > 0.1 else { return 0 }
        return ((elevations[j] - elevations[i]) / dd) * 100.0
    }

    static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let Δφ = (lat2 - lat1) * .pi / 180
        let Δλ = (lon2 - lon1) * .pi / 180
        let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}

enum CourseError: Error {
    case notEnoughPoints
}

@MainActor
final class CourseLibrary: ObservableObject {
    @Published private(set) var courses: [Course] = []
    @Published var selected: Course?

    init() {
        loadBundled()
    }

    func loadBundled() {
        var urls: [URL] = []
        urls.append(contentsOf: Bundle.main.urls(forResourcesWithExtension: "gpx", subdirectory: nil) ?? [])
        urls.append(contentsOf: Bundle.main.urls(forResourcesWithExtension: "gpx", subdirectory: "Courses") ?? [])
        #if SWIFT_PACKAGE
        urls.append(contentsOf: Bundle.module.urls(forResourcesWithExtension: "gpx", subdirectory: nil) ?? [])
        urls.append(contentsOf: Bundle.module.urls(forResourcesWithExtension: "gpx", subdirectory: "Courses") ?? [])
        #endif
        var loaded: [Course] = []
        var seen = Set<String>()
        for url in urls {
            guard seen.insert(url.lastPathComponent).inserted else { continue }
            if let course = try? GPXParser.parse(url: url) {
                loaded.append(course)
            }
        }
        if loaded.isEmpty {
            loaded.append(Self.syntheticHillRepeat())
        }
        courses = loaded
        selected = loaded.first
    }

    func importFile(url: URL) throws {
        let course = try GPXParser.parse(url: url)
        courses.append(course)
        selected = course
    }

    static func syntheticHillRepeat() -> Course {
        // 10 km course with two climbs for offline demos.
        var points: [CoursePoint] = []
        let total = 10_000.0
        var d = 0.0
        var ele = 100.0
        while d <= total {
            let grade: Double
            if d > 2000 && d < 3500 { grade = 6.0 }
            else if d > 6000 && d < 8000 { grade = 8.0 }
            else if d > 3500 && d < 4500 { grade = -3.0 }
            else { grade = 0.5 }
            ele += grade / 100.0 * 25.0
            points.append(CoursePoint(distanceMeters: d, elevationMeters: ele, latitude: nil, longitude: nil, gradePercent: grade))
            d += 25
        }
        return Course(name: "Demo Hills 10k", points: points)
    }
}

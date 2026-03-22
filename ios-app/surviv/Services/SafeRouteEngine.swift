import Foundation
import CoreLocation

// MARK: - Safe Route Engine

/// Computes the optimal walking route from the user's current location to the
/// nearest safe-zone pin while avoiding known danger zones.
///
/// Pipeline:
///   1. Parse the bundled OSM XML to extract nodes (GPS points) and ways (roads).
///   2. Build an adjacency-list graph — every consecutive node pair in a walkable
///      way becomes a bidirectional edge weighted by Haversine distance.
///   3. Run A* from the user's snapped position to the nearest safe pin, hard-blocking
///      any edge that enters a danger zone radius (node or midpoint check).
///   4. Re-run whenever the user moves or pins change.
final class SafeRouteEngine: ObservableObject {

    /// The computed route as an ordered list of coordinates, or empty if none.
    @Published private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var isCalculating = false

    private var graph = RouteGraph()
    private var osmNodes: [Int64: CLLocationCoordinate2D] = [:]
    @Published private(set) var graphReady = false

    // MARK: - Public API

    /// Call once at launch to parse the bundled OSM data and build the graph.
    private var isLoading = false

    func loadGraph() {
        guard !graphReady, !isLoading else { return }
        isLoading = true
        isCalculating = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            guard let url = Bundle.main.url(forResource: "mapUva", withExtension: "osm") else {
                print("[SafeRoute] ERROR: mapUva.osm not found in bundle")
                DispatchQueue.main.async { self.isCalculating = false; self.isLoading = false }
                return
            }

            guard let data = try? Data(contentsOf: url) else {
                print("[SafeRoute] ERROR: could not read mapUva.osm data")
                DispatchQueue.main.async { self.isCalculating = false; self.isLoading = false }
                return
            }

            let parser = OSMParser()
            parser.parse(data: data)

            var graph = RouteGraph()
            let walkableHighways: Set<String> = [
                "residential", "tertiary", "secondary", "primary", "trunk",
                "unclassified", "service", "living_street", "pedestrian",
                "footway", "path", "cycleway", "track", "steps",
                "tertiary_link", "secondary_link", "primary_link"
            ]

            for way in parser.ways {
                guard walkableHighways.contains(way.highwayType) else { continue }

                let refs = way.nodeRefs
                for i in 0 ..< refs.count - 1 {
                    let a = refs[i]
                    let b = refs[i + 1]
                    guard let coordA = parser.nodes[a],
                          let coordB = parser.nodes[b] else { continue }

                    let dist = Self.haversine(coordA, coordB)
                    graph.addEdge(from: a, to: b, distance: dist)
                }
            }

            DispatchQueue.main.async {
                self.osmNodes = parser.nodes
                self.graph = graph
                self.graphReady = true
                self.isCalculating = false
            }
        }
    }

    /// Find a route from `userLocation` to the nearest safe pin, avoiding danger pins.
    func computeRoute(
        from userLocation: CLLocationCoordinate2D,
        safePins: [RoutablePin],
        dangerPins: [RoutablePin]
    ) {
        guard graphReady, !safePins.isEmpty else {
            routeCoordinates = []
            return
        }

        isCalculating = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let startNode = self.closestNode(to: userLocation)

            var bestRoute: [CLLocationCoordinate2D]?
            var bestCost = Double.infinity

            for pin in safePins {
                let goalNode = self.closestGraphNode(
                    insideZoneAt: pin.coordinate,
                    radius: pin.radiusMeters,
                    preferCloseTo: userLocation
                )
                guard startNode != goalNode else {
                    bestRoute = [userLocation, pin.coordinate]
                    bestCost = 0
                    break
                }

                if let result = self.astar(
                    start: startNode,
                    goal: goalNode,
                    dangerPins: dangerPins
                ), result.cost < bestCost {
                    bestCost = result.cost
                    bestRoute = [userLocation]
                        + result.nodeIds.compactMap { self.osmNodes[$0] }
                        + [pin.coordinate]
                }
            }

            DispatchQueue.main.async {
                self.routeCoordinates = bestRoute ?? []
                self.isCalculating = false
            }
        }
    }

    func clearRoute() {
        routeCoordinates = []
    }

    // MARK: - A*

    private struct AStarResult {
        let nodeIds: [Int64]
        let cost: Double
    }

    private func astar(
        start: Int64,
        goal: Int64,
        dangerPins: [RoutablePin]
    ) -> AStarResult? {
        guard let goalCoord = osmNodes[goal] else { return nil }

        var openSet = PriorityQueue()
        var cameFrom: [Int64: Int64] = [:]
        var gScore: [Int64: Double] = [start: 0]

        let startH = osmNodes[start].map { Self.haversine($0, goalCoord) } ?? 0
        openSet.insert(node: start, priority: startH)

        while let current = openSet.popMin() {
            if current == goal {
                return AStarResult(
                    nodeIds: reconstructPath(cameFrom: cameFrom, current: current),
                    cost: gScore[current] ?? 0
                )
            }

            guard let edges = graph.adjacency[current] else { continue }

            let currentCoord = osmNodes[current]

            for edge in edges {
                if isEdgeBlocked(
                    from: currentCoord,
                    toNodeId: edge.to,
                    dangerPins: dangerPins
                ) { continue }

                let tentative = (gScore[current] ?? .infinity) + edge.distance

                if tentative < (gScore[edge.to] ?? .infinity) {
                    cameFrom[edge.to] = current
                    gScore[edge.to] = tentative

                    let h = osmNodes[edge.to].map { Self.haversine($0, goalCoord) } ?? 0
                    openSet.insert(node: edge.to, priority: tentative + h)
                }
            }
        }

        return nil
    }

    private func reconstructPath(cameFrom: [Int64: Int64], current: Int64) -> [Int64] {
        var path = [current]
        var node = current
        while let prev = cameFrom[node] {
            path.append(prev)
            node = prev
        }
        return path.reversed()
    }

    /// Returns true if traversing this edge would enter a danger zone.
    /// Checks the destination node AND the midpoint of the segment so roads
    /// that cut through a zone are blocked even when both endpoints are outside.
    private func isEdgeBlocked(
        from fromCoord: CLLocationCoordinate2D?,
        toNodeId: Int64,
        dangerPins: [RoutablePin]
    ) -> Bool {
        guard let toCoord = osmNodes[toNodeId] else { return true }

        for pin in dangerPins {
            if Self.haversine(toCoord, pin.coordinate) < pin.radiusMeters {
                return true
            }

            if let from = fromCoord {
                let midLat = (from.latitude + toCoord.latitude) / 2
                let midLon = (from.longitude + toCoord.longitude) / 2
                let mid = CLLocationCoordinate2D(latitude: midLat, longitude: midLon)
                if Self.haversine(mid, pin.coordinate) < pin.radiusMeters {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Helpers

    /// Finds the graph node inside the zone radius that's closest to the user,
    /// so the route ends as soon as it enters the safe zone.
    private func closestGraphNode(
        insideZoneAt center: CLLocationCoordinate2D,
        radius: Double,
        preferCloseTo origin: CLLocationCoordinate2D
    ) -> Int64 {
        var bestId: Int64 = 0
        var bestDist = Double.infinity

        for id in graph.adjacency.keys {
            guard let nodeCoord = osmNodes[id] else { continue }
            let distToCenter = Self.haversine(nodeCoord, center)
            guard distToCenter <= radius else { continue }

            let distToOrigin = Self.haversine(nodeCoord, origin)
            if distToOrigin < bestDist {
                bestDist = distToOrigin
                bestId = id
            }
        }

        if bestId == 0 {
            return closestNode(to: center)
        }
        return bestId
    }

    private func closestNode(to coord: CLLocationCoordinate2D) -> Int64 {
        var bestId: Int64 = 0
        var bestDist = Double.infinity
        for id in graph.adjacency.keys {
            guard let nodeCoord = osmNodes[id] else { continue }
            let d = Self.haversine(coord, nodeCoord)
            if d < bestDist {
                bestDist = d
                bestId = id
            }
        }
        return bestId
    }

    /// Haversine distance in meters between two coordinates.
    static func haversine(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        let R = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180

        let h = sin(dLat / 2) * sin(dLat / 2)
              + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(h), sqrt(1 - h))
    }
}

// MARK: - Routable Pin (lightweight struct passed into the engine)

struct RoutablePin {
    let coordinate: CLLocationCoordinate2D
    let radiusMeters: Double
}

// MARK: - Route Graph

private struct RouteGraph {
    struct Edge {
        let to: Int64
        let distance: Double
    }

    private(set) var adjacency: [Int64: [Edge]] = [:]

    mutating func addEdge(from a: Int64, to b: Int64, distance: Double) {
        adjacency[a, default: []].append(Edge(to: b, distance: distance))
        adjacency[b, default: []].append(Edge(to: a, distance: distance))
    }
}

// MARK: - Priority Queue (min-heap for A*)

private struct PriorityQueue {
    private var heap: [(node: Int64, priority: Double)] = []

    var isEmpty: Bool { heap.isEmpty }

    mutating func insert(node: Int64, priority: Double) {
        heap.append((node, priority))
        siftUp(heap.count - 1)
    }

    mutating func popMin() -> Int64? {
        guard !heap.isEmpty else { return nil }
        if heap.count == 1 { return heap.removeLast().node }
        let min = heap[0]
        heap[0] = heap.removeLast()
        siftDown(0)
        return min.node
    }

    private mutating func siftUp(_ i: Int) {
        var i = i
        while i > 0 {
            let parent = (i - 1) / 2
            if heap[i].priority < heap[parent].priority {
                heap.swapAt(i, parent)
                i = parent
            } else { break }
        }
    }

    private mutating func siftDown(_ i: Int) {
        var i = i
        let n = heap.count
        while true {
            var smallest = i
            let left = 2 * i + 1
            let right = 2 * i + 2
            if left < n, heap[left].priority < heap[smallest].priority { smallest = left }
            if right < n, heap[right].priority < heap[smallest].priority { smallest = right }
            if smallest == i { break }
            heap.swapAt(i, smallest)
            i = smallest
        }
    }
}

// MARK: - OSM XML Parser

private final class OSMParser: NSObject, XMLParserDelegate {
    /// All parsed nodes: nodeId → coordinate.
    private(set) var nodes: [Int64: CLLocationCoordinate2D] = [:]
    /// All parsed ways that have a highway tag.
    private(set) var ways: [OSMWay] = []

    struct OSMWay {
        let id: Int64
        var nodeRefs: [Int64]
        var highwayType: String
    }

    private var currentWay: OSMWay?
    private var currentWayTags: [String: String] = [:]
    private var currentWayNodeRefs: [Int64] = []

    func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        switch elementName {
        case "node":
            guard let idStr = attributes["id"],
                  let id = Int64(idStr),
                  let latStr = attributes["lat"],
                  let lat = Double(latStr),
                  let lonStr = attributes["lon"],
                  let lon = Double(lonStr) else { return }
            nodes[id] = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        case "way":
            guard let idStr = attributes["id"],
                  let id = Int64(idStr) else { return }
            currentWayNodeRefs = []
            currentWayTags = [:]
            currentWay = OSMWay(id: id, nodeRefs: [], highwayType: "")

        case "nd":
            if currentWay != nil,
               let refStr = attributes["ref"],
               let ref = Int64(refStr) {
                currentWayNodeRefs.append(ref)
            }

        case "tag":
            if currentWay != nil,
               let k = attributes["k"],
               let v = attributes["v"] {
                currentWayTags[k] = v
            }

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if elementName == "way", var way = currentWay {
            if let highwayVal = currentWayTags["highway"] {
                way.nodeRefs = currentWayNodeRefs
                way.highwayType = highwayVal
                ways.append(way)
            }
            currentWay = nil
        }
    }
}

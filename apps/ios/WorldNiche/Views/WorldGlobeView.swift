import SwiftUI
import SceneKit
import UIKit
import simd

/// An offline, tactile world. The texture and hit tests use the same country polygons.
struct WorldGlobeView: UIViewRepresentable {
    let countries: [Country]
    let selectedCountry: Country?
    let spinToken: Int
    var onSelect: (Country) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.autoenablesDefaultLighting = false
        view.accessibilityLabel = "Interactive world globe"
        view.accessibilityHint = "Drag to turn the world. Pinch to zoom. Tap a country to explore it. All destinations are also available in the country list."
        view.accessibilityTraits = [.image]
        context.coordinator.configure(view: view, countries: countries)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.countries = countries
        context.coordinator.onSelect = onSelect
        context.coordinator.updateSelection(selectedCountry, spinToken: spinToken)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        uiView.scene?.rootNode.enumerateChildNodes { node, _ in node.removeAllActions() }
        uiView.scene = nil
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var countries: [Country] = []
        var onSelect: (Country) -> Void
        private weak var view: SCNView?
        private let worldNode = SCNNode()
        private let surfaceNode = SCNNode()
        private let markerNode = SCNNode()
        private let cameraNode = SCNNode()
        private var selectedID: String?
        private var lastSpinToken: Int?
        private var pinchScale: Double = 1.18
        private let atlas = GlobeAtlas.shared

        init(onSelect: @escaping (Country) -> Void) { self.onSelect = onSelect }

        func configure(view: SCNView, countries: [Country]) {
            self.view = view
            self.countries = countries
            let scene = SCNScene()
            scene.background.contents = UIColor.clear
            view.scene = scene

            cameraNode.camera = SCNCamera()
            cameraNode.camera?.usesOrthographicProjection = true
            cameraNode.camera?.orthographicScale = pinchScale
            cameraNode.camera?.zNear = 0.1
            cameraNode.camera?.zFar = 30
            cameraNode.position = SCNVector3(0, 0, 4.5)
            scene.rootNode.addChildNode(cameraNode)
            view.pointOfView = cameraNode

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.color = UIColor(red: 0.94, green: 0.96, blue: 0.90, alpha: 1)
            ambient.light?.intensity = 780
            scene.rootNode.addChildNode(ambient)

            let sunlight = SCNNode()
            sunlight.light = SCNLight()
            sunlight.light?.type = .omni
            sunlight.light?.intensity = 440
            sunlight.light?.color = UIColor(red: 1, green: 0.97, blue: 0.90, alpha: 1)
            sunlight.position = SCNVector3(-3, 4, 6)
            scene.rootNode.addChildNode(sunlight)

            surfaceNode.name = "world-surface"
            surfaceNode.geometry = Self.makeSphere()
            let material = SCNMaterial()
            material.diffuse.contents = atlas.texture
            material.lightingModel = .blinn
            material.specular.contents = UIColor(white: 0.12, alpha: 1)
            material.shininess = 0.2
            material.isDoubleSided = false
            surfaceNode.geometry?.materials = [material]
            worldNode.addChildNode(surfaceNode)
            scene.rootNode.addChildNode(worldNode)
            worldNode.simdOrientation = Self.orientation(latitude: 22, longitude: 18)
            buildMarker()
            worldNode.addChildNode(markerNode)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
            tap.require(toFail: pan)
            view.addGestureRecognizer(tap)
        }

        func updateSelection(_ country: Country?, spinToken: Int) {
            let isFirstUpdate = lastSpinToken == nil
            let shouldSpin = !isFirstUpdate && lastSpinToken != spinToken
            let didChange = selectedID != country?.id
            lastSpinToken = spinToken
            guard didChange || shouldSpin || isFirstUpdate else { return }
            selectedID = country?.id
            guard let country else {
                markerNode.isHidden = true
                return
            }
            let direction = Self.position(latitude: country.latitude, longitude: country.longitude)
            markerNode.simdPosition = direction * 1.014
            markerNode.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction)
            markerNode.isHidden = false
            let destination = Self.orientation(latitude: country.latitude, longitude: country.longitude)
            stopRotation()
            guard !isFirstUpdate && !UIAccessibility.isReduceMotionEnabled else {
                worldNode.simdOrientation = destination
                return
            }
            let start = worldNode.simdOrientation
            let duration: TimeInterval = shouldSpin ? 1.8 : 0.8
            let animation = SCNAction.customAction(duration: duration) { node, time in
                let fraction = min(1, Float(time) / Float(duration))
                let eased = fraction * fraction * (3 - 2 * fraction)
                let base = simd_slerp(start, destination, eased)
                let turn = shouldSpin ? Float.pi * 2 * (1 - eased) : 0
                node.simdOrientation = simd_quatf(angle: turn, axis: SIMD3<Float>(0, 1, 0)) * base
            }
            worldNode.runAction(animation, forKey: "navigation")
        }

        private func buildMarker() {
            let accent = UIColor(red: 0.13, green: 0.31, blue: 0.24, alpha: 1)
            let ring = SCNTorus(ringRadius: 0.038, pipeRadius: 0.0045)
            ring.ringSegmentCount = 48
            ring.pipeSegmentCount = 8
            let ringMaterial = SCNMaterial()
            ringMaterial.diffuse.contents = accent
            ringMaterial.lightingModel = .constant
            ring.materials = [ringMaterial]
            let ringNode = SCNNode(geometry: ring)
            markerNode.addChildNode(ringNode)
            let center = SCNSphere(radius: 0.013)
            center.segmentCount = 20
            center.materials = [ringMaterial]
            let centerNode = SCNNode(geometry: center)
            centerNode.position.y = 0.004
            markerNode.addChildNode(centerNode)
            markerNode.isHidden = true
        }

        private func stopRotation() {
            let visibleOrientation = worldNode.presentation.simdOrientation
            worldNode.removeAllActions()
            worldNode.simdOrientation = visibleOrientation
        }

        @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            if recognizer.state == .began { stopRotation() }
            if recognizer.state == .changed {
                let translation = recognizer.translation(in: view)
                let factor = Float(pinchScale) / max(120, Float(view.bounds.height)) * 1.8
                let horizontal = simd_quatf(angle: Float(translation.x) * factor, axis: SIMD3<Float>(0, 1, 0))
                let vertical = simd_quatf(angle: Float(translation.y) * factor, axis: SIMD3<Float>(1, 0, 0))
                worldNode.simdOrientation = simd_normalize(horizontal * vertical * worldNode.simdOrientation)
                recognizer.setTranslation(.zero, in: view)
            }
            if recognizer.state == .ended && !UIAccessibility.isReduceMotionEnabled {
                let velocity = recognizer.velocity(in: view)
                let axis = SIMD3<Float>(Float(velocity.y), Float(velocity.x), 0)
                let speed = simd_length(axis)
                guard speed > 100 else { return }
                let normalizedAxis = simd_normalize(axis)
                let angle = min(1.4, speed / 2200)
                let initial = worldNode.simdOrientation
                let inertia = SCNAction.customAction(duration: 1.15) { node, elapsed in
                    let t = min(1, Float(elapsed) / 1.15)
                    let deceleration = 1 - pow(1 - t, 3)
                    node.simdOrientation = simd_quatf(angle: angle * deceleration, axis: normalizedAxis) * initial
                }
                worldNode.runAction(inertia, forKey: "inertia")
            }
        }

        @objc private func pinch(_ recognizer: UIPinchGestureRecognizer) {
            if recognizer.state == .began { stopRotation() }
            pinchScale = min(1.65, max(0.76, pinchScale / Double(recognizer.scale)))
            cameraNode.camera?.orthographicScale = pinchScale
            recognizer.scale = 1
        }

        @objc private func tap(_ recognizer: UITapGestureRecognizer) {
            guard let view else { return }
            stopRotation()
            let results = view.hitTest(recognizer.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            guard let hit = results.first(where: { $0.node === surfaceNode }) else { return }
            let point = hit.localCoordinates
            let latitude = asin(Double(point.y) / max(0.0001, Double(sqrt(point.x * point.x + point.y * point.y + point.z * point.z)))) * 180 / .pi
            let longitude = atan2(Double(point.x), Double(point.z)) * 180 / .pi
            let ids = atlas.countryIDs(latitude: latitude, longitude: longitude)
            var country = countries.first { ids.contains($0.id) }
            // Tiny islands and city-states may have no polygon at world scale. Never snap an ocean tap across a continent.
            if country == nil {
                country = countries.map { ($0, Self.angularDistance(latitude, longitude, $0.latitude, $0.longitude)) }
                    .filter { $0.1 < 1.7 }.min { $0.1 < $1.1 }?.0
            }
            guard let country else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            onSelect(country)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
        }

        private static func position(latitude: Double, longitude: Double) -> SIMD3<Float> {
            let lat = Float(latitude * .pi / 180)
            let lon = Float(longitude * .pi / 180)
            return SIMD3<Float>(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
        }

        private static func orientation(latitude: Double, longitude: Double) -> simd_quatf {
            simd_quatf(angle: Float(latitude * .pi / 180), axis: SIMD3<Float>(1, 0, 0)) *
            simd_quatf(angle: Float(-longitude * .pi / 180), axis: SIMD3<Float>(0, 1, 0))
        }

        private static func angularDistance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
            let radians = Double.pi / 180
            let dot = sin(lat1 * radians) * sin(lat2 * radians) + cos(lat1 * radians) * cos(lat2 * radians) * cos((lon1 - lon2) * radians)
            return acos(min(1, max(-1, dot))) / radians
        }

        private static func makeSphere() -> SCNGeometry {
            let columns = 160
            let rows = 80
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var uv: [CGPoint] = []
            var indices: [Int32] = []
            for row in 0...rows {
                let v = Double(row) / Double(rows)
                for column in 0...columns {
                    let u = Double(column) / Double(columns)
                    let p = position(latitude: 90 - v * 180, longitude: u * 360 - 180)
                    let vertex = SCNVector3(p.x, p.y, p.z)
                    vertices.append(vertex)
                    normals.append(vertex)
                    uv.append(CGPoint(x: u, y: v))
                }
            }
            for row in 0..<rows {
                for column in 0..<columns {
                    let a = Int32(row * (columns + 1) + column)
                    let b = a + 1
                    let c = a + Int32(columns + 1)
                    let d = c + 1
                    indices.append(contentsOf: [a, c, b, b, c, d])
                }
            }
            return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uv)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        }
    }
}

@MainActor
private final class GlobeAtlas {
    static let shared = GlobeAtlas()
    private let regions: [Region]
    let texture: UIImage

    private struct Region {
        let iso: String
        let rings: [[[CGPoint]]]
        let bounds: CGRect
    }

    private init() {
        var parsed: [Region] = []
        if let url = Bundle.main.url(forResource: "GlobeCountries", withExtension: "geojson"),
           let data = try? Data(contentsOf: url),
           let collection = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let features = collection["features"] as? [[String: Any]] {
            for feature in features {
                guard let properties = feature["properties"] as? [String: Any],
                      let iso = properties["iso"] as? String,
                      let geometry = feature["geometry"] as? [String: Any],
                      let type = geometry["type"] as? String else { continue }
                let coordinates: [[[[Double]]]]
                if type == "Polygon", let polygon = geometry["coordinates"] as? [[[Double]]] { coordinates = [polygon] }
                else if let polygons = geometry["coordinates"] as? [[[[Double]]]] { coordinates = polygons }
                else { continue }
                let rings = coordinates.map { polygon in polygon.map { ring in ring.compactMap { pair -> CGPoint? in
                    guard pair.count >= 2 else { return nil }
                    return CGPoint(x: pair[0], y: pair[1])
                } } }
                let points = rings.flatMap { $0.flatMap { $0 } }
                guard let first = points.first else { continue }
                var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
                for point in points {
                    minX = min(minX, point.x); maxX = max(maxX, point.x)
                    minY = min(minY, point.y); maxY = max(maxY, point.y)
                }
                parsed.append(Region(iso: iso, rings: rings, bounds: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)))
            }
        }
        regions = parsed
        texture = Self.makeTexture(regions: parsed)
    }

    func countryIDs(latitude: Double, longitude: Double) -> Set<String> {
        let point = CGPoint(x: longitude, y: latitude)
        var ids = Set<String>()
        for region in regions where region.bounds.contains(point) && !region.iso.isEmpty {
            for polygon in region.rings {
                guard let outer = polygon.first, Self.contains(point, ring: outer) else { continue }
                if !polygon.dropFirst().contains(where: { Self.contains(point, ring: $0) }) { ids.insert(region.iso) }
            }
        }
        return ids
    }

    private static func contains(_ point: CGPoint, ring: [CGPoint]) -> Bool {
        guard ring.count > 2 else { return false }
        var inside = false
        var previous = ring[ring.count - 1]
        for current in ring {
            if (current.y > point.y) != (previous.y > point.y),
               point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x {
                inside.toggle()
            }
            previous = current
        }
        return inside
    }

    private static func makeTexture(regions: [Region]) -> UIImage {
        let size = CGSize(width: 4096, height: 2048)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            UIColor(red: 0.69, green: 0.79, blue: 0.73, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.setStrokeColor(UIColor(red: 0.48, green: 0.65, blue: 0.56, alpha: 0.23).cgColor)
            context.setLineWidth(1)
            for longitude in stride(from: -180, through: 180, by: 30) {
                let x = (CGFloat(longitude) + 180) / 360 * size.width
                context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: size.height))
            }
            for latitude in stride(from: -60, through: 60, by: 30) {
                let y = (90 - CGFloat(latitude)) / 180 * size.height
                context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.strokePath()
            for region in regions {
                let shade = CGFloat(region.iso.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 5) * 0.008
                context.setFillColor(UIColor(red: 0.92 - shade, green: 0.935 - shade, blue: 0.87 - shade, alpha: 1).cgColor)
                context.setStrokeColor(UIColor(red: 0.46, green: 0.60, blue: 0.49, alpha: 0.65).cgColor)
                context.setLineWidth(1.9)
                context.setLineJoin(.round)
                for polygon in region.rings {
                    let path = CGMutablePath()
                    for ring in polygon {
                        guard let first = ring.first else { continue }
                        func projected(_ point: CGPoint) -> CGPoint {
                            CGPoint(x: (point.x + 180) / 360 * size.width, y: (90 - point.y) / 180 * size.height)
                        }
                        path.move(to: projected(first))
                        for point in ring.dropFirst() { path.addLine(to: projected(point)) }
                        path.closeSubpath()
                    }
                    context.addPath(path)
                    context.drawPath(using: .eoFillStroke)
                }
            }
        }
    }
}

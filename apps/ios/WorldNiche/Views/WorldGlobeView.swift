import SwiftUI
import SceneKit
import UIKit
import UIKit.UIGestureRecognizerSubclass
import simd

/// An offline, tactile world. The texture and hit tests use the same country polygons.
struct WorldGlobeView: UIViewRepresentable {
    let countries: [Country]
    let selectedCountry: Country?
    let spinToken: Int
    var resetToken = 0
    var allowsCountrySelection = true
    var onSelect: (Country) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> GlobeSceneView {
        let view = GlobeSceneView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isMultipleTouchEnabled = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.autoenablesDefaultLighting = false
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Interactive world globe"
        updateAccessibility(view)
        view.accessibilityTraits = [.image]
        context.coordinator.allowsCountrySelection = allowsCountrySelection
        context.coordinator.configure(view: view, countries: countries)
        return view
    }

    func updateUIView(_ uiView: GlobeSceneView, context: Context) {
        context.coordinator.countries = countries
        context.coordinator.onSelect = onSelect
        context.coordinator.allowsCountrySelection = allowsCountrySelection
        updateAccessibility(uiView)
        context.coordinator.updateSelection(selectedCountry, spinToken: spinToken)
        context.coordinator.resetIfNeeded(token: resetToken, country: selectedCountry)
    }

    private func updateAccessibility(_ view: SCNView) {
        view.accessibilityHint = allowsCountrySelection
            ? "Drag with one finger to turn. Use two fingers to move and pinch to zoom. Tap a country to show its name, then tap the name to explore. All destinations are also available in Atlas."
            : "Drag with one finger to turn. Use two fingers to move and pinch to zoom. This practice globe does not open countries."
    }

    static func dismantleUIView(_ uiView: GlobeSceneView, coordinator: Coordinator) {
        coordinator.stopAnimation()
        uiView.onLayout = nil
        uiView.scene?.rootNode.enumerateChildNodes { node, _ in node.removeAllActions() }
        uiView.scene = nil
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var countries: [Country] = []
        var onSelect: (Country) -> Void
        var allowsCountrySelection = true
        private weak var view: SCNView?
        private let worldNode = SCNNode()
        private let surfaceNode = SCNNode()
        private let markerNode = SCNNode()
        private let cameraNode = SCNNode()
        private var selectedID: String?
        private var lastSpinToken: Int?
        private var lastResetToken: Int?
        private var viewport = GlobeViewport()
        private var orientation = GlobeOrientation(latitude: 22, longitude: 18)
        private var gestureGeneration = -1
        private var gestureViewport = GlobeViewport()
        private var gesturePoint = CGPoint.zero
        private var displayLink: CADisplayLink?
        private var animation: NavigationAnimation?
        private var borderGeometry: SCNGeometry?

        private struct NavigationAnimation {
            let started: TimeInterval
            let duration: TimeInterval
            let start: GlobeOrientation
            let destination: GlobeOrientation
            let viewport: GlobeViewport
            let destinationViewport: GlobeViewport
            let extraTurn: Double
        }
        private let atlas = GlobeAtlas.shared

        init(onSelect: @escaping (Country) -> Void) { self.onSelect = onSelect }

        func configure(view: GlobeSceneView, countries: [Country]) {
            self.view = view
            self.countries = countries
            let scene = SCNScene()
            scene.background.contents = UIColor.clear
            view.scene = scene

            cameraNode.camera = SCNCamera()
            cameraNode.camera?.usesOrthographicProjection = true
            cameraNode.camera?.projectionDirection = .vertical
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
            let borders = atlas.makeBorders()
            borderGeometry = borders
            worldNode.addChildNode(SCNNode(geometry: borders))
            scene.rootNode.addChildNode(worldNode)
            worldNode.simdOrientation = orientation.quaternion
            buildMarker()
            worldNode.addChildNode(markerNode)
            view.onLayout = { [weak self] in self?.updateViewport() }
            updateViewport()

            let navigation = GlobeNavigationGesture(target: self, action: #selector(explore(_:)))
            navigation.delegate = self
            navigation.canBegin = { [weak self, weak view] point in
                guard let self, let view else { return false }
                return self.viewport.surfacePoint(at: point, in: view.bounds.size) != nil
            }
            view.addGestureRecognizer(navigation)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
            tap.require(toFail: navigation)
            tap.delegate = self
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
            // Browsing changes only the marker. Surprise navigation is explicitly requested.
            guard isFirstUpdate || shouldSpin else { return }
            navigate(to: country, spinning: shouldSpin, animated: !isFirstUpdate)
        }

        func resetIfNeeded(token: Int, country: Country?) {
            defer { lastResetToken = token }
            guard let previous = lastResetToken, previous != token else { return }
            navigate(to: country, spinning: false, animated: true)
        }

        private func navigate(to country: Country?, spinning: Bool, animated: Bool) {
            stopAnimation()
            let destination = GlobeOrientation(latitude: country?.latitude ?? 22, longitude: country?.longitude ?? 18)
            guard animated && !UIAccessibility.isReduceMotionEnabled else {
                orientation = destination
                viewport = GlobeViewport()
                worldNode.simdOrientation = orientation.quaternion
                updateViewport()
                return
            }
            animation = NavigationAnimation(started: CACurrentMediaTime(), duration: spinning ? 1.8 : 0.55,
                start: orientation, destination: destination, viewport: viewport,
                destinationViewport: GlobeViewport(), extraTurn: spinning ? 2 * .pi : 0)
            let link = CADisplayLink(target: self, selector: #selector(animate(_:)))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }

        @objc private func animate(_ link: CADisplayLink) {
            guard let animation else { return }
            let t = min(1, max(0, (link.timestamp - animation.started) / animation.duration))
            let eased = t * t * (3 - 2 * t)
            let longitudeChange = (animation.destination.longitude - animation.start.longitude).remainder(dividingBy: 2 * .pi)
            orientation = animation.start.rotated(horizontal: (-longitudeChange + animation.extraTurn) * eased,
                vertical: (animation.destination.latitude - animation.start.latitude) * eased)
            viewport = animation.viewport.interpolated(to: animation.destinationViewport, fraction: eased)
            worldNode.simdOrientation = orientation.quaternion
            updateViewport()
            if t == 1 { stopAnimation() }
        }

        func stopAnimation() {
            displayLink?.invalidate()
            displayLink = nil
            animation = nil
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

        @objc private func explore(_ recognizer: GlobeNavigationGesture) {
            guard let view, recognizer.state == .began || recognizer.state == .changed else { return }
            if gestureGeneration != recognizer.generation {
                stopAnimation()
                gestureGeneration = recognizer.generation
                gestureViewport = viewport
                gesturePoint = recognizer.startCenter
            }
            if recognizer.fingerCount == 2 {
                viewport = gestureViewport
                viewport.transform(from: recognizer.startCenter, to: recognizer.center,
                    magnification: recognizer.span / max(1, recognizer.startSpan), in: view.bounds.size)
            } else if recognizer.fingerCount == 1 {
                orientation = orientation.dragging(from: gesturePoint, to: recognizer.center,
                    in: view.bounds.size, viewport: gestureViewport)
                worldNode.simdOrientation = orientation.quaternion
            }
            gesturePoint = recognizer.center
            updateViewport()
        }

        private func updateViewport() {
            guard let view else { return }
            let diameter = max(1, min(view.bounds.width, view.bounds.height))
            cameraNode.camera?.orthographicScale = viewport.scale * max(1, view.bounds.height) / diameter
            cameraNode.position.x = -Float(viewport.offset.x)
            cameraNode.position.y = -Float(viewport.offset.y)
            borderGeometry?.setValue(Float(viewport.scale * 0.65 / diameter), forKey: "borderWidth")
            // A selection marker must not cover neighboring countries when zoomed in.
            markerNode.simdScale = SIMD3<Float>(repeating: Float(min(1, viewport.scale / GlobeViewport.initialScale)))
            view.accessibilityValue = "\(viewport.zoomPercent)% zoom"
        }

        @objc private func tap(_ recognizer: UITapGestureRecognizer) {
            guard allowsCountrySelection, let view else { return }
            let location = recognizer.location(in: view)
            stopAnimation()
            let results = view.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
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

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view else { return false }
            let point = touch.location(in: view)
            let onSurface = viewport.surfacePoint(at: point, in: view.bounds.size) != nil
            if gestureRecognizer is GlobeNavigationGesture {
                if onSurface { stopAnimation() }
                // A pinch can straddle the silhouette. Decide using its midpoint once both fingers arrive.
                return true
            }
            return point.y > 12 && point.y < view.bounds.height - 12 && onSurface
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        private static func position(latitude: Double, longitude: Double) -> SIMD3<Float> {
            let lat = Float(latitude * .pi / 180)
            let lon = Float(longitude * .pi / 180)
            return SIMD3<Float>(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
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

/// The real sphere silhouette can leave the canvas. Its vertical edges blend into the page.
final class GlobeSceneView: SCNView {
    var onLayout: (() -> Void)?
    private let edgeMask = CAGradientLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeMask.frame = bounds
        let fade = min(0.12, 24 / max(1, bounds.height))
        edgeMask.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        edgeMask.locations = [0, NSNumber(value: fade), NSNumber(value: 1 - fade), 1]
        layer.mask = edgeMask
        CATransaction.commit()
        onLayout?()
    }
}

/// One touch stream owns rotation, scale and movement, so callback order cannot introduce drift.
private final class GlobeNavigationGesture: UIGestureRecognizer {
    var canBegin: ((CGPoint) -> Bool)?
    private var fingers = Set<UITouch>()
    private(set) var generation = 0
    private(set) var startCenter = CGPoint.zero
    private(set) var startSpan: CGFloat = 1
    private(set) var center = CGPoint.zero
    private(set) var span: CGFloat = 1
    var fingerCount: Int { fingers.count }

    private func sample() {
        let points = fingers.map { $0.location(in: view) }
        guard let first = points.first else { return }
        center = points.count == 2 ? CGPoint(x: (first.x + points[1].x) / 2, y: (first.y + points[1].y) / 2) : first
        span = points.count == 2 ? hypot(first.x - points[1].x, first.y - points[1].y) : 1
    }

    private func rebase() {
        sample()
        startCenter = center
        startSpan = span
        generation += 1
        if state == .began || state == .changed { state = .changed }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        fingers.formUnion(touches)
        guard fingers.count <= 2 else { state = state == .possible ? .failed : .cancelled; return }
        rebase()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        sample()
        if state == .possible {
            if hypot(center.x - startCenter.x, center.y - startCenter.y) > 3 || abs(span - startSpan) > 3 {
                let withinEdges = startCenter.y > 12 && startCenter.y < (view?.bounds.height ?? 0) - 12
                state = withinEdges && canBegin?(startCenter) == true ? .began : .failed
            }
        } else { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        fingers.subtract(touches)
        if fingers.isEmpty { state = state == .possible ? .failed : .ended }
        else { rebase() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .cancelled
    }

    override func reset() {
        fingers.removeAll()
        super.reset()
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

    func makeBorders() -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var sides: [SCNVector3] = []
        var indices: [Int32] = []
        func position(_ point: CGPoint) -> SIMD3<Float> {
            let lat = Float(point.y * .pi / 180), lon = Float(point.x * .pi / 180)
            return SIMD3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
        }
        for ring in regions.flatMap({ $0.rings.flatMap { $0 } }) {
            for (first, second) in zip(ring, ring.dropFirst()) {
                let a = position(first), b = position(second)
                let cross = simd_cross(a, b)
                guard simd_length(cross) > 0.000001 else { continue }
                let side = simd_normalize(cross)
                // Subdivision keeps long border segments on the sphere, including at the horizon.
                let steps = max(1, Int(ceil(acos(min(1, max(-1, simd_dot(a, b)))) / 0.005)))
                for step in 0..<steps {
                    let p = simd_normalize(simd_mix(a, b, SIMD3(repeating: Float(step) / Float(steps)))) * 1.001
                    let q = simd_normalize(simd_mix(a, b, SIMD3(repeating: Float(step + 1) / Float(steps)))) * 1.001
                    let base = Int32(vertices.count)
                    for (point, normal) in [(p, side), (p, -side), (q, side), (q, -side)] {
                        vertices.append(SCNVector3(point.x, point.y, point.z))
                        sides.append(SCNVector3(normal.x, normal.y, normal.z))
                    }
                    indices.append(contentsOf: [base, base + 1, base + 2, base + 2, base + 1, base + 3])
                }
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: sides)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.46, green: 0.60, blue: 0.49, alpha: 1)
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        // The normals carry ribbon sides. Width is in scene units and follows the camera scale.
        geometry.shaderModifiers = [.geometry: """
            #pragma arguments
            float borderWidth;
            #pragma body
            _geometry.position.xyz += _geometry.normal * borderWidth;
            """]
        geometry.setValue(Float(0.002), forKey: "borderWidth")
        return geometry
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
                    context.drawPath(using: .eoFill)
                }
            }
        }
    }
}

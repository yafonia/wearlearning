//
//  ARWorldTrackingViewModel.swift
//  WeAReLearning
//
//  Created by Yafonia Hutabarat on 27/06/26.
//

import ARKit
import RealityKit
import simd
import UIKit

struct ARWorldTrackingDisplayState {
    var sessionID: String
    var cameraTransform: String
    var cameraOrientation: String
    var trackingState: String
    var lightEstimate: String
}

// Anchoring target for an AnchorEntity-only (render-only) user anchor. .plane and
// .camera attach to detected surfaces / the camera, so they cannot be backed by a
// plain ARAnchor(transform:).
enum AnchorEntityTarget: Int, CaseIterable {
    case world, plane, camera
}

// How a tap is turned into a world position before an anchor is placed.
enum RaycastMethod: Int, CaseIterable {
    case sessionRaycast, sessionTrackedRaycast, arViewRaycast, sceneRaycast, sceneRaycastLiDAR

    var title: String {
        switch self {
        case .sessionRaycast: "ARSession.raycast"
        case .sessionTrackedRaycast: "ARSession.trackedRaycast"
        case .arViewRaycast: "ARView.raycast"
        case .sceneRaycast: "ARView.scene.raycast (no LiDAR mesh)"
        case .sceneRaycastLiDAR: "ARView.scene.raycast (with LiDAR mesh)"
        }
    }

    // Only these consume an ARRaycastQuery.Target; the scene.raycast methods do not.
    var usesRaycastTarget: Bool {
        switch self {
        case .sessionRaycast, .sessionTrackedRaycast, .arViewRaycast: true
        case .sceneRaycast, .sceneRaycastLiDAR: false
        }
    }
}

// Read-only snapshot of a session anchor (the source of truth).
struct InspectorARAnchor {
    let type: String
    let name: String
    let uuid: UUID
    let transform: simd_float4x4
    let isRendered: Bool
}

// Read-only snapshot of a scene AnchorEntity (the render projection).
struct InspectorSceneAnchor {
    let type: String
    let name: String
    let uuid: UUID?
    let color: UIColor?
    let transform: simd_float4x4
    let isAnchored: Bool
}

@MainActor
final class ARWorldTrackingViewModel: NSObject {
    var isHorizontalPlaneDetectionEnabled = false {
        didSet { applyPlaneDetectionChanges() }
    }

    var isVerticalPlaneDetectionEnabled = false {
        didSet { applyPlaneDetectionChanges() }
    }

    var worldAlignment: ARConfiguration.WorldAlignment = .gravity {
        didSet { applyConfigurationChange() }
    }

    var environmentTexturing: ARWorldTrackingConfiguration.EnvironmentTexturing = .none {
        didSet { applyConfigurationChange() }
    }

    var isLightEstimationEnabled = false {
        didSet { applyConfigurationChange() }
    }

    var sceneReconstruction: ARWorldTrackingConfiguration.SceneReconstruction = [] {
        didSet { applyConfigurationChange() }
    }

    // ARView.Environment.SceneUnderstanding.collision. Enables collision shapes on the
    // reconstructed mesh so it can be raycast against.
    var isCollisionEnabled = false {
        didSet { updateSceneUnderstanding() }
    }

    // ARView debug visualizations. World origin starts on to match prior behavior.
    var showsFeaturePoints = false {
        didSet { updateDebugOptions() }
    }

    var showsWorldOrigin = true {
        didSet { updateDebugOptions() }
    }

    // Applied on the next explicit run() (the Run button), not on config-change reruns.
    var runOptions: ARSession.RunOptions = []

    var onDisplayStateUpdated: ((ARWorldTrackingDisplayState) -> Void)?
    var onAnchorsChanged: (() -> Void)?

    private weak var arView: ARView?
    private var configuration = ARWorldTrackingConfiguration()
    // Render-only projection of the session's anchors, keyed by ARAnchor.identifier.
    // ARAnchor is the source of truth; these AnchorEntity values exist purely to draw.
    private var renderedAnchors: [UUID: AnchorEntity] = [:]
    // ARAnchor identifiers created "with ARAnchor, without AnchorEntity": the delegate
    // skips their render projection so they exist in the session but are not rendered.
    private var unrenderedARAnchorIDs: Set<UUID> = []
    // Add-order of scene entities (newest last); drives newest-first inspector lists.
    // Keyed by entity identity so world (ARAnchor-less) entities are ordered too.
    private var sceneOrder: [ObjectIdentifier] = []
    // Render-only anchors the user created without a backing ARAnchor, for cleanup.
    private var unanchoredEntities: [AnchorEntity] = []
    private var lastLightEstimate = "-"
    // Retained while a tracked raycast is in flight; stopped after its first result.
    private var trackedRaycast: ARTrackedRaycast?
    // Palette cycled so each user-created anchor marker gets a distinct color.
    private static let userAnchorColors: [UIColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemTeal, .systemBlue, .systemIndigo, .systemPurple, .systemPink
    ]
    private var nextUserAnchorColorIndex = 0

    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        updateDebugOptions()
        updateSceneUnderstanding()
        reconfigure()
        notifyAnchorsChanged()
    }

    // The Run button: applies the user-selected run options.
    func run() {
        guard let arView else { return }
        if runOptions.contains(.resetTracking) || runOptions.contains(.removeExistingAnchors) {
            clearRenderedAnchors()
        }
        updateConfiguration()
        arView.session.run(configuration, options: runOptions)
        publishDisplayState(cameraTransform: "-", trackingState: "-")
    }

    func setRunOption(_ option: ARSession.RunOptions, enabled: Bool) {
        if enabled {
            runOptions.insert(option)
        } else {
            runOptions.remove(option)
        }
    }

    // Silent re-apply of the configuration after a settings change. Uses no run
    // options, so tweaking worldAlignment/planeDetection never resets tracking.
    private func reconfigure() {
        guard let arView else { return }
        updateConfiguration()
        arView.session.run(configuration)
        publishDisplayState(cameraTransform: "-", trackingState: "-")
    }

    func pause() {
        arView?.session.pause()
    }

    func reset() {
        guard let arView else { return }
        updateConfiguration()
        arView.session.run(configuration, options: [])
        publishDisplayState(cameraTransform: "-", trackingState: "-")
    }

    func removeAllAnchors() {
        guard let arView else { return }
        // Remove from the session (the source of truth). session.remove(anchor:) fires
        // didRemove, so the delegate tears down each render entity. The reflection probe
        // is a .camera anchor with no ARAnchor, so it is left untouched.
        for anchor in arView.session.currentFrame?.anchors ?? [] {
            arView.session.remove(anchor: anchor)
        }
        // Render-only anchors have no ARAnchor, so tear them down directly.
        for entity in unanchoredEntities {
            removeSceneAnchor(entity)
        }
        unanchoredEntities.removeAll()
        notifyAnchorsChanged()
    }

    func resetTracking() {
        guard let arView else { return }
        clearRenderedAnchors()
        updateConfiguration()
        arView.session.run(
            configuration,
            options: [.resetTracking, .removeExistingAnchors]
        )
        publishDisplayState(cameraTransform: "-", trackingState: "-")
    }

    // Info-only lookup: returns the tapped anchor's info, or nil for empty space.
    // Placement is deferred until after the raycast-method and add-anchor dialogs.
    func anchorInfoAtTap(at point: CGPoint, in arView: ARView) -> AnchorTapInfo? {
        guard let entity = arView.entity(at: point) else { return nil }
        return anchorInfo(for: entity)
    }

    // Runs the chosen raycast for `point`. The result transform is shown in the Add
    // Anchor dialog before placeUserAnchor creates the anchor.
    func raycast(
        method: RaycastMethod,
        target: ARRaycastQuery.Target,
        at point: CGPoint,
        completion: @escaping (simd_float4x4?) -> Void
    ) {
        performRaycast(method: method, target: target, at: point, completion: completion)
    }

    // Creates the anchor at an already-computed transform (from raycast(...)).
    func placeUserAnchor(
        name: String,
        withARAnchor: Bool,
        withAnchorEntity: Bool,
        entityTarget: AnchorEntityTarget,
        transform: simd_float4x4?
    ) {
        // Render-only .plane/.camera anchors ignore the transform, so identity is fine
        // if the raycast found nothing.
        let resolved = transform ?? ((!withARAnchor && entityTarget != .world) ? matrix_identity_float4x4 : nil)
        guard let resolved else { return }
        addUserAnchor(
            name: name,
            transform: resolved,
            withARAnchor: withARAnchor,
            withAnchorEntity: withAnchorEntity,
            target: entityTarget
        )
    }

    private func performRaycast(
        method: RaycastMethod,
        target: ARRaycastQuery.Target,
        at point: CGPoint,
        completion: @escaping (simd_float4x4?) -> Void
    ) {
        guard let arView else { return completion(nil) }
        switch method {
        case .sessionRaycast:
            guard let query = arView.makeRaycastQuery(from: point, allowing: target, alignment: .any) else {
                return completion(nil)
            }
            completion(arView.session.raycast(query).first?.worldTransform)
        case .sessionTrackedRaycast:
            guard let query = arView.makeRaycastQuery(from: point, allowing: target, alignment: .any) else {
                return completion(nil)
            }
            trackedRaycast = arView.session.trackedRaycast(query) { [weak self] results in
                guard let self, let transform = results.first?.worldTransform else { return }
                self.trackedRaycast?.stopTracking()
                self.trackedRaycast = nil
                completion(transform)
            }
        case .arViewRaycast:
            completion(arView.raycast(from: point, allowing: target, alignment: .any).first?.worldTransform)
        case .sceneRaycast, .sceneRaycastLiDAR:
            // Collision raycast against the scene. With LiDAR mesh (enableLiDARMesh) this
            // hits the reconstructed environment; without it, only entities that have
            // collision shapes.
            guard let ray = arView.ray(through: point),
                  let hit = arView.scene.raycast(
                    origin: ray.origin,
                    direction: ray.direction,
                    length: 10,
                    query: .nearest
                  ).first else {
                return completion(nil)
            }
            var transform = matrix_identity_float4x4
            transform.columns.3 = SIMD4<Float>(hit.position, 1)
            completion(transform)
        }
    }

    // Turns on both scene reconstruction and mesh collision, then reruns the session
    // (via sceneReconstruction's didSet) so the LiDAR mesh can be raycast against.
    func enableLiDARMesh() {
        sceneReconstruction = .mesh
        isCollisionEnabled = true
    }

    func addUserAnchor(
        name: String,
        transform: simd_float4x4,
        withARAnchor: Bool = true,
        withAnchorEntity: Bool = true,
        target: AnchorEntityTarget = .world
    ) {
        guard let arView else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if withARAnchor {
            // Add a real, named session anchor. The delegate builds its render entity, so
            // user anchors and ARKit-detected planes flow through the exact same path and
            // the ARAnchor remains the single source of truth. When there is no
            // AnchorEntity, flag the id so the delegate skips its render projection.
            let arAnchor = ARAnchor(name: trimmedName, transform: transform)
            if !withAnchorEntity { unrenderedARAnchorIDs.insert(arAnchor.identifier) }
            arView.session.add(anchor: arAnchor)
        } else {
            // Render-only anchor: an AnchorEntity with no backing ARAnchor. It lives purely
            // in the scene, so we track it for reset/remove-all cleanup. .plane and .camera
            // attach to detected surfaces / the camera and ignore `transform`.
            let entity: AnchorEntity
            switch target {
            case .world:
                entity = AnchorEntity(.world(transform: transform))
            case .plane:
                entity = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: SIMD2<Float>(0.2, 0.2)))
            case .camera:
                entity = AnchorEntity(.camera)
            }
            entity.name = trimmedName
            let marker = makeUserAnchorMarker()
            // A .camera marker at the origin sits on the camera and is not visible, so
            // push it forward into view.
            if case .camera = target { marker.position = [0, 0, -0.5] }
            entity.addChild(marker)
            unanchoredEntities.append(entity)
            addSceneAnchor(entity)
            notifyAnchorsChanged()
        }
    }

    func anchorInfo(for entity: Entity) -> AnchorTapInfo? {
        guard let anchorEntity = anchorEntity(from: entity) else { return nil }

        // ARAnchor-backed anchor (user anchor or detected plane): the ARAnchor is truth.
        if let id = renderedAnchors.first(where: { $0.value === anchorEntity })?.key,
           let anchor = arView?.session.currentFrame?.anchors.first(where: { $0.identifier == id }) {
            return AnchorTapInfo(
                name: displayName(for: anchor),
                uuid: anchor.identifier,
                transform: anchor.transform
            )
        }

        // Render-only anchor (world/plane/camera AnchorEntity with no backing ARAnchor).
        if unanchoredEntities.contains(where: { $0 === anchorEntity }) {
            return AnchorTapInfo(
                name: anchorEntity.name,
                uuid: anchorEntity.anchorIdentifier,
                transform: anchorEntity.transformMatrix(relativeTo: nil)
            )
        }

        return nil
    }

    // Snapshot of the session's anchors (the source of truth) for the inspector,
    // ordered newest-added first.
    func inspectorARAnchors() -> [InspectorARAnchor] {
        let anchors = arView?.session.currentFrame?.anchors ?? []
        return anchors
            .sorted { sceneOrderIndex(renderedAnchors[$0.identifier]) > sceneOrderIndex(renderedAnchors[$1.identifier]) }
            .map {
                InspectorARAnchor(
                    type: String(describing: type(of: $0)),
                    name: displayName(for: $0),
                    uuid: $0.identifier,
                    transform: $0.transform,
                    isRendered: renderedAnchors[$0.identifier] != nil
                )
            }
    }

    // Snapshot of the RealityKit scene's anchors (the render projection) for the
    // inspector, ordered newest-added first. Includes the reflection probe, which
    // has no backing ARAnchor and therefore sorts last.
    func inspectorSceneAnchors() -> [InspectorSceneAnchor] {
        guard let anchors = arView?.scene.anchors else { return [] }
        let sessionIDs = Set((arView?.session.currentFrame?.anchors ?? []).map { $0.identifier })
        return anchors
            .sorted { sceneOrderIndex($0) > sceneOrderIndex($1) }
            .map { entity in
                let backingID = (entity as? AnchorEntity)?.anchorIdentifier
                return InspectorSceneAnchor(
                    type: sceneAnchorTypeName(entity),
                    name: entity.name,
                    uuid: backingID,
                    color: sceneAnchorColor(entity),
                    transform: entity.transformMatrix(relativeTo: nil),
                    isAnchored: backingID.map { sessionIDs.contains($0) } ?? false
                )
            }
    }

    // Single funnel for scene mutations so add-order stays in sync with the scene.
    private func addSceneAnchor(_ entity: AnchorEntity) {
        arView?.scene.addAnchor(entity)
        sceneOrder.append(ObjectIdentifier(entity))
    }

    private func removeSceneAnchor(_ entity: AnchorEntity) {
        arView?.scene.removeAnchor(entity)
        sceneOrder.removeAll { $0 == ObjectIdentifier(entity) }
    }

    // Position of a scene entity in add-order; untracked entities (e.g. the
    // reflection probe) return -1 so they sort to the bottom of the newest-first
    // lists.
    private func sceneOrderIndex(_ entity: Entity?) -> Int {
        guard let entity, let index = sceneOrder.firstIndex(of: ObjectIdentifier(entity)) else { return -1 }
        return index
    }

    // The "type" of an AnchorEntity is its anchoring target kind.
    private func sceneAnchorTypeName(_ entity: HasAnchoring) -> String {
        switch entity.anchoring.target {
        case .camera: return "camera"
        case .world: return "world"
        case .anchor: return "anchor"
        case .plane: return "plane"
        case .image: return "image"
        case .face: return "face"
        case .body: return "body"
        case .object: return "object"
        @unknown default: return "other"
        }
    }

    private func sceneAnchorColor(_ entity: Entity) -> UIColor? {
        for child in entity.children {
            if let model = child as? ModelEntity,
               let material = model.model?.materials.first as? SimpleMaterial {
                return material.color.tint
            }
        }
        return nil
    }

    private func applyPlaneDetectionChanges() {
        guard arView != nil else { return }
        updatePlaneVisibility()
        reconfigure()
    }

    private func applyConfigurationChange() {
        guard arView != nil else { return }
        reconfigure()
    }

    private func updateDebugOptions() {
        guard let arView else { return }
        if showsFeaturePoints { arView.debugOptions.insert(.showFeaturePoints) }
        else { arView.debugOptions.remove(.showFeaturePoints) }
        if showsWorldOrigin { arView.debugOptions.insert(.showWorldOrigin) }
        else { arView.debugOptions.remove(.showWorldOrigin) }
    }

    private func updateSceneUnderstanding() {
        guard let arView else { return }
        if isCollisionEnabled { arView.environment.sceneUnderstanding.options.insert(.collision) }
        else { arView.environment.sceneUnderstanding.options.remove(.collision) }
    }

    private func updateConfiguration() {
        configuration.worldAlignment = worldAlignment

        var planeDetection: ARWorldTrackingConfiguration.PlaneDetection = []
        if isHorizontalPlaneDetectionEnabled {
            planeDetection.insert(.horizontal)
        }
        if isVerticalPlaneDetectionEnabled {
            planeDetection.insert(.vertical)
        }
        configuration.planeDetection = planeDetection

        configuration.sceneReconstruction =
            ARWorldTrackingConfiguration.supportsSceneReconstruction(sceneReconstruction) ? sceneReconstruction : []
    }

    private func isDetectionEnabled(for alignment: ARPlaneAnchor.Alignment) -> Bool {
        switch alignment {
        case .horizontal:
            isHorizontalPlaneDetectionEnabled
        case .vertical:
            isVerticalPlaneDetectionEnabled
        @unknown default:
            false
        }
    }

    private func updatePlaneVisibility() {
        for case let plane as ARPlaneAnchor in arView?.session.currentFrame?.anchors ?? [] {
            renderedAnchors[plane.identifier]?.isEnabled = isDetectionEnabled(for: plane.alignment)
        }
    }

    // Builds the render projection for an anchor: a plane gets its mesh, everything
    // else gets a marker. The entity is anchored to the ARAnchor by identifier.
    private func renderEntity(for anchor: ARAnchor) -> AnchorEntity {
        let entity = AnchorEntity(anchor: anchor)
        entity.name = displayName(for: anchor)
        if let planeAnchor = anchor as? ARPlaneAnchor {
            entity.addChild(makePlaneModelEntity(for: planeAnchor))
            entity.isEnabled = isDetectionEnabled(for: planeAnchor.alignment)
        } else {
            entity.addChild(makeUserAnchorMarker())
        }
        return entity
    }

    private func refreshPlaneMesh(_ planeAnchor: ARPlaneAnchor) {
        guard let entity = renderedAnchors[planeAnchor.identifier],
              let modelEntity = entity.children.first as? ModelEntity else {
            return
        }

        modelEntity.model = ModelComponent(
            mesh: makePlaneMesh(for: planeAnchor),
            materials: [makePlaneMaterial(for: planeAnchor.alignment)]
        )
        modelEntity.position = planeModelPosition(for: planeAnchor)
        entity.isEnabled = isDetectionEnabled(for: planeAnchor.alignment)
    }

    // Render-only teardown for reset paths (run(options:) does not fire didRemove).
    private func clearRenderedAnchors() {
        for (_, entity) in renderedAnchors {
            removeSceneAnchor(entity)
        }
        renderedAnchors.removeAll()
        for entity in unanchoredEntities {
            removeSceneAnchor(entity)
        }
        unanchoredEntities.removeAll()
        notifyAnchorsChanged()
    }

    private func notifyAnchorsChanged() {
        onAnchorsChanged?()
    }

    private func displayName(for anchor: ARAnchor) -> String {
        if let plane = anchor as? ARPlaneAnchor {
            return (plane.alignment == .horizontal ? "horizontal" : "vertical") + " plane"
        }
        if let name = anchor.name, !name.isEmpty { return name }
        return "anchor"
    }

    private func makeUserAnchorMarker() -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.02)
        let color = Self.userAnchorColors[nextUserAnchorColorIndex % Self.userAnchorColors.count]
        nextUserAnchorColorIndex += 1
        let material = SimpleMaterial(color: color.withAlphaComponent(0.9), isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private func anchorEntity(from entity: Entity) -> AnchorEntity? {
        var current: Entity? = entity
        while let node = current {
            if let anchorEntity = node as? AnchorEntity {
                return anchorEntity
            }
            current = node.parent
        }
        return nil
    }

    private func makePlaneModelEntity(for planeAnchor: ARPlaneAnchor) -> ModelEntity {
        let modelEntity = ModelEntity(
            mesh: makePlaneMesh(for: planeAnchor),
            materials: [makePlaneMaterial(for: planeAnchor.alignment)]
        )
        modelEntity.position = planeModelPosition(for: planeAnchor)
        return modelEntity
    }

    private func planeModelPosition(for planeAnchor: ARPlaneAnchor) -> SIMD3<Float> {
        let center = planeAnchor.center
        return SIMD3(center.x, 0, center.z)
    }

    private func makePlaneMesh(for planeAnchor: ARPlaneAnchor) -> MeshResource {
        let extent = planeAnchor.planeExtent
        return MeshResource.generatePlane(
            width: extent.width,
            depth: extent.height
        )
    }

    private func makePlaneMaterial(for alignment: ARPlaneAnchor.Alignment) -> SimpleMaterial {
        let color: UIColor = alignment == .horizontal
            ? UIColor.systemBlue.withAlphaComponent(0.3)
            : UIColor.systemGreen.withAlphaComponent(0.3)
        return SimpleMaterial(color: color, isMetallic: false)
    }

    private func publishDisplayState(
        cameraTransform: String,
        trackingState: String,
        cameraOrientation: String = "-",
        lightEstimate: String = "-"
    ) {
        let state = ARWorldTrackingDisplayState(
            sessionID: arView?.session.identifier.uuidString ?? "-",
            cameraTransform: cameraTransform,
            cameraOrientation: cameraOrientation,
            trackingState: trackingState,
            lightEstimate: lightEstimate
        )
        onDisplayStateUpdated?(state)
    }

    private func publishFrameState(from frame: ARFrame) {
        let lightEstimate = formatLightEstimate(frame)
        lastLightEstimate = lightEstimate
        publishDisplayState(
            cameraTransform: formatTransform(frame.camera.transform),
            trackingState: formatTrackingState(frame.camera.trackingState),
            cameraOrientation: formatOrientation(frame.camera),
            lightEstimate: lightEstimate
        )
    }

    private func publishCameraState(from camera: ARCamera) {
        publishDisplayState(
            cameraTransform: formatTransform(camera.transform),
            trackingState: formatTrackingState(camera.trackingState),
            cameraOrientation: formatOrientation(camera),
            lightEstimate: lastLightEstimate
        )
    }

    private func formatTransform(_ transform: simd_float4x4) -> String {
        let position = transform.columns.3
        return String(
            format: "x: %.3f, y: %.3f, z: %.3f",
            position.x,
            position.y,
            position.z
        )
    }

    // The euler angles are expressed in the world frame, so the same physical pose
    // reads differently depending on worldAlignment (gravity / heading / camera).
    private func formatOrientation(_ camera: ARCamera) -> String {
        let radiansToDegrees: Float = 180 / .pi
        let degrees = camera.eulerAngles * radiansToDegrees
        return String(
            format: "pitch: %.0f°, yaw: %.0f°, roll: %.0f°",
            degrees.x,
            degrees.y,
            degrees.z
        )
    }

    // ARKit only vends a light estimate when isLightEstimationEnabled is on, so a nil
    // estimate is what tells us the option is currently disabled.
    private func formatLightEstimate(_ frame: ARFrame) -> String {
        guard let estimate = frame.lightEstimate else { return "Off" }
        return String(
            format: "%.0f lm, %.0f K",
            estimate.ambientIntensity,
            estimate.ambientColorTemperature
        )
    }

    private func formatTrackingState(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .notAvailable:
            return "Not Available"
        case .limited(let reason):
            switch reason {
            case .initializing:
                return "Limited: Initializing"
            case .excessiveMotion:
                return "Limited: Excessive Motion"
            case .insufficientFeatures:
                return "Limited: Insufficient Features"
            case .relocalizing:
                return "Limited: Relocalizing"
            @unknown default:
                return "Limited"
            }
        case .normal:
            return "Normal"
        }
    }
}

extension ARWorldTrackingViewModel: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            publishFrameState(from: frame)
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        Task { @MainActor in
            publishCameraState(from: camera)
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                session.currentFrame?.anchors
                // Environment probe anchors are non-visual data anchors (they carry the
                // environment cube-map for reflections), so no render projection.
                if anchor is AREnvironmentProbeAnchor { continue }
                // ARAnchor-only anchors (created without an AnchorEntity) are not rendered.
                if unrenderedARAnchorIDs.remove(anchor.identifier) != nil { continue }
                let entity = renderEntity(for: anchor)
                renderedAnchors[anchor.identifier] = entity
                addSceneAnchor(entity)
            }
            notifyAnchorsChanged()
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            for case let planeAnchor as ARPlaneAnchor in anchors {
                refreshPlaneMesh(planeAnchor)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let entity = renderedAnchors.removeValue(forKey: anchor.identifier) {
                    removeSceneAnchor(entity)
                }
            }
            notifyAnchorsChanged()
        }
    }
}

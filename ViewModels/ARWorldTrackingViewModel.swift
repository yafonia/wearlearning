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

    var isLightEstimationEnabled = true {
        didSet { applyConfigurationChange() }
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
    // Add-order of scene entities (newest last); drives newest-first inspector lists.
    // Keyed by entity identity so world (ARAnchor-less) entities are ordered too.
    private var sceneOrder: [ObjectIdentifier] = []
    // Render-only anchors the user created without a backing ARAnchor, for cleanup.
    private var unanchoredEntities: [AnchorEntity] = []
    private var reflectionProbe: AnchorEntity?
    private var lastLightEstimate = "-"

    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        updateDebugOptions()
        reconfigure()
        updateReflectionProbe()
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
        updateReflectionProbe()
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
        updateReflectionProbe()
        publishDisplayState(cameraTransform: "-", trackingState: "-")
    }

    func handleTap(at point: CGPoint, in arView: ARView) -> TapHandleResult {
        if let entity = arView.entity(at: point),
           let info = anchorInfo(for: entity) {
            return .existingAnchor(info)
        }

        if let transform = RaycastPlaceholder.performRaycast(at: point, in: arView) {
            return .raycastHit(transform)
        }

        return .noHit
    }

    func addUserAnchor(name: String, transform: simd_float4x4, useARAnchor: Bool = true) {
        guard let arView else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if useARAnchor {
            // Add a real, named session anchor. The delegate builds its render entity, so
            // user anchors and ARKit-detected planes flow through the exact same path and
            // the ARAnchor remains the single source of truth.
            let arAnchor = ARAnchor(name: trimmedName, transform: transform)
            arView.session.add(anchor: arAnchor)
        } else {
            // Render-only anchor: a world-anchored AnchorEntity with no backing ARAnchor.
            // It lives purely in the scene, so we track it for reset/remove-all cleanup.
            let entity = AnchorEntity(.world(transform: transform))
            entity.name = trimmedName
            entity.addChild(makeUserAnchorMarker())
            unanchoredEntities.append(entity)
            addSceneAnchor(entity)
            notifyAnchorsChanged()
        }
    }

    func anchorInfo(for entity: Entity) -> AnchorTapInfo? {
        guard let anchorEntity = anchorEntity(from: entity),
              let id = renderedAnchors.first(where: { $0.value === anchorEntity })?.key,
              let anchor = arView?.session.currentFrame?.anchors.first(where: { $0.identifier == id })
        else { return nil }

        return AnchorTapInfo(
            name: displayName(for: anchor),
            uuid: anchor.identifier,
            transform: anchor.transform
        )
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
        updateReflectionProbe()
        reconfigure()
    }

    private func updateDebugOptions() {
        guard let arView else { return }
        if showsFeaturePoints { arView.debugOptions.insert(.showFeaturePoints) }
        else { arView.debugOptions.remove(.showFeaturePoints) }
        if showsWorldOrigin { arView.debugOptions.insert(.showWorldOrigin) }
        else { arView.debugOptions.remove(.showWorldOrigin) }
    }

    private func updateConfiguration() {
        configuration.worldAlignment = worldAlignment
        configuration.environmentTexturing = environmentTexturing
        configuration.isLightEstimationEnabled = isLightEstimationEnabled

        var planeDetection: ARWorldTrackingConfiguration.PlaneDetection = []
        if isHorizontalPlaneDetectionEnabled {
            planeDetection.insert(.horizontal)
        }
        if isVerticalPlaneDetectionEnabled {
            planeDetection.insert(.vertical)
        }
        configuration.planeDetection = planeDetection
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
        let material = SimpleMaterial(color: UIColor.systemOrange.withAlphaComponent(0.9), isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    // Shows the reflection probe only while environment texturing is active. Under
    // .none it has nothing to reflect (it renders as a black sphere in the middle),
    // so we keep it out of the scene. Guarding on `scene` keeps this idempotent, so
    // it also re-adds the probe if a scene wipe / tracking reset detached it.
    private func updateReflectionProbe() {
        guard let arView else { return }

        guard environmentTexturing != .none else {
            if let probe = reflectionProbe {
                removeSceneAnchor(probe)
                reflectionProbe = nil
            }
            return
        }

        if reflectionProbe?.scene == nil {
            let probe = makeReflectionProbe()
            reflectionProbe = probe
            addSceneAnchor(probe)
        }
    }

    // A mirror-like sphere kept in front of the camera. environmentTexturing feeds the
    // reflections it shows: flat under .none, mirroring the room under .automatic.
    private func makeReflectionProbe() -> AnchorEntity {
        let anchor = AnchorEntity(.camera)
        anchor.name = "reflection-probe"
        let material = SimpleMaterial(color: .white, roughness: 0.05, isMetallic: true)
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [material])
        sphere.position = [0, 0, -0.5]
        anchor.addChild(sphere)
        return anchor
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
                // Environment probe anchors are non-visual data anchors (they carry the
                // environment cube-map for reflections), so no render projection.
                if anchor is AREnvironmentProbeAnchor { continue }
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

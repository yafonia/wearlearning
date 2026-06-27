////  BaseSimulationViewModel.swift//  ARLearning////  Created by Yafonia Hutabarat on 27/06/26.//

import ARKit
import RealityKit
import simd
import UIKit

struct BaseSimulationDisplayState {
    var sessionID: String
    var cameraTransform: String
    var trackingState: String
}

@MainActor final class BaseSimulationViewModel: NSObject {
    var isHorizontalPlaneDetectionEnabled = false {
        didSet { applyPlaneDetectionChanges() }
    }

    var isVerticalPlaneDetectionEnabled = false {
        didSet { applyPlaneDetectionChanges() }
    }

    var onDisplayStateUpdated: ((BaseSimulationDisplayState) -> Void)?
    var onAnchorsListUpdated: ((String) -> Void)?

    private weak var arView: ARView?
    private var configuration = ARWorldTrackingConfiguration()
    private var planeEntities: [UUID: PlaneVisualization] = [:]
    private var horizontalPlaneCount = 0
    private var verticalPlaneCount = 0

    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        updateConfiguration()
        run()
        publishAnchorsList()
    }

    func run() {
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
        clearPlaneEntities()
        arView?.scene.anchors.removeAll()
    }

    func resetTracking() {
        guard let arView else { return }
        clearPlaneEntities()
        updateConfiguration()
        arView.session.run(
            configuration,
            options: [.resetTracking, .removeExistingAnchors]
        )
        publishDisplayState(cameraTransform: "-", trackingState: "-")
    }

    private func applyPlaneDetectionChanges() {
        guard arView != nil else { return }
        updatePlaneVisibility()
        run()
    }

    private func updateConfiguration() {
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
        for (_, visualization) in planeEntities {
            visualization.entity.isEnabled = isDetectionEnabled(for: visualization.alignment)
        }
    }

    private func addPlaneEntity(for planeAnchor: ARPlaneAnchor) {
        guard let arView else { return }

        let name = makePlaneName(for: planeAnchor.alignment)
        let anchorEntity = AnchorEntity(anchor: planeAnchor)
        let modelEntity = makePlaneModelEntity(for: planeAnchor)
        anchorEntity.addChild(modelEntity)
        anchorEntity.isEnabled = isDetectionEnabled(for: planeAnchor.alignment)
        anchorEntity.name = name

        arView.scene.addAnchor(anchorEntity)
        planeEntities[planeAnchor.identifier] = PlaneVisualization(
            entity: anchorEntity,
            alignment: planeAnchor.alignment,
            name: name,
            transform: planeAnchor.transform
        )
        publishAnchorsList()
    }

    private func updatePlaneEntity(for planeAnchor: ARPlaneAnchor) {
        guard var visualization = planeEntities[planeAnchor.identifier] else {
            addPlaneEntity(for: planeAnchor)
            return
        }

        guard let modelEntity = visualization.entity.children.first as? ModelEntity else {
            return
        }

        modelEntity.model = ModelComponent(
            mesh: makePlaneMesh(for: planeAnchor),
            materials: [makePlaneMaterial(for: planeAnchor.alignment)]
        )
        modelEntity.position = planeModelPosition(for: planeAnchor)
        visualization.entity.isEnabled = isDetectionEnabled(for: planeAnchor.alignment)
        visualization.transform = planeAnchor.transform
        planeEntities[planeAnchor.identifier] = visualization
        publishAnchorsList()
    }

    private func removePlaneEntity(for anchor: ARAnchor) {
        guard let visualization = planeEntities.removeValue(forKey: anchor.identifier) else { return }
        arView?.scene.removeAnchor(visualization.entity)
        publishAnchorsList()
    }

    private func clearPlaneEntities() {
        for (_, visualization) in planeEntities {
            arView?.scene.removeAnchor(visualization.entity)
        }
        planeEntities.removeAll()
        horizontalPlaneCount = 0
        verticalPlaneCount = 0
        publishAnchorsList()
    }

    private func makePlaneName(for alignment: ARPlaneAnchor.Alignment) -> String {
        switch alignment {
        case .horizontal:
            horizontalPlaneCount += 1
            return "horizontal-plane-\(horizontalPlaneCount)"
        case .vertical:
            verticalPlaneCount += 1
            return "vertical-plane-\(verticalPlaneCount)"
        @unknown default:
            return "plane-\(UUID().uuidString.prefix(8))"
        }
    }

    private func publishAnchorsList() {
        guard !planeEntities.isEmpty else {
            onAnchorsListUpdated?("Anchors: (none)")
            return
        }

        let lines = planeEntities.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { visualization in
                "- \(visualization.name): \(formatTransform(visualization.transform))"
            }

        onAnchorsListUpdated?("Anchors:\n" + lines.joined(separator: "\n"))
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

    private func publishDisplayState(cameraTransform: String, trackingState: String) {
        let state = BaseSimulationDisplayState(
            sessionID: arView?.session.identifier.uuidString ?? "-",
            cameraTransform: cameraTransform,
            trackingState: trackingState
        )
        onDisplayStateUpdated?(state)
    }

    private func publishFrameState(from frame: ARFrame) {
        publishDisplayState(
            cameraTransform: formatTransform(frame.camera.transform),
            trackingState: formatTrackingState(frame.camera.trackingState)
        )
    }

    private func publishCameraState(from camera: ARCamera) {
        publishDisplayState(
            cameraTransform: formatTransform(camera.transform),
            trackingState: formatTrackingState(camera.trackingState)
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

    private struct PlaneVisualization {
        let entity: AnchorEntity
        let alignment: ARPlaneAnchor.Alignment
        let name: String
        var transform: simd_float4x4
    }

    extension BaseSimulationViewModel: ARSessionDelegate {
        nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
            Task {
                @MainActor in publishFrameState(from: frame)
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
                guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }
                addPlaneEntity(for: planeAnchor)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }
                updatePlaneEntity(for: planeAnchor)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                removePlaneEntity(for: anchor)
            }
        }
    }

}

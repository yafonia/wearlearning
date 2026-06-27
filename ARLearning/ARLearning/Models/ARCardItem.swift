//
//  ARCardItem.swift
//  ARLearning
//
//  Created by Yafonia Hutabarat on 27/06/26.
//

import Foundation

enum ARCardItem: String, CaseIterable, Sendable {
    case baseSimulation
    case arWorldMap
    case arReferenceImage
    case arFaceTrackingConfiguration

    nonisolated var title: String {
        switch self {
        case .baseSimulation:
            "Base Simulation"
        case .arWorldMap:
            "ARWorldMap"
        case .arReferenceImage:
            "ARReferenceImage"
        case .arFaceTrackingConfiguration:
            "ARFaceTrackingConfiguration"
        }
    }

    nonisolated var systemImageName: String {
        switch self {
        case .baseSimulation:
            "cube.transparent"
        case .arWorldMap:
            "map"
        case .arReferenceImage:
            "photo"
        case .arFaceTrackingConfiguration:
            "face.smiling"
        }
    }
}

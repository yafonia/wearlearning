//
//  ARCardItem.swift
//  WeAReLearning
//
//  Created by Yafonia Hutabarat on 27/06/26.
//

import Foundation

enum ARCardItem: String, CaseIterable, Sendable {
    case arWorldTracking

    nonisolated var title: String {
        switch self {
        case .arWorldTracking:
            "ARWorldTracking"
        }
    }

    nonisolated var systemImageName: String {
        switch self {
        case .arWorldTracking:
            "cube.transparent"
        }
    }
}

//
//  AnchorTapInfo.swift
//  WeAReLearning
//
//  Created by Yafonia Hutabarat on 27/06/26.
//

import Foundation
import simd

struct AnchorTapInfo {
    let name: String
    let uuid: UUID
    let transform: simd_float4x4

    var transformDescription: String {
        let position = transform.columns.3
        return String(
            format: "x: %.3f, y: %.3f, z: %.3f",
            position.x,
            position.y,
            position.z
        )
    }
}

enum TapHandleResult {
    case existingAnchor(AnchorTapInfo)
    case raycastHit(simd_float4x4)
    case noHit
}

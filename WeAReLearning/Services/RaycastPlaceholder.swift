//
//  RaycastPlaceholder.swift
//  WeAReLearning
//
//  Created by Yafonia Hutabarat on 27/06/26.
//

import ARKit
import RealityKit
import simd

enum RaycastPlaceholder {
    static func performRaycast(at screenPoint: CGPoint, in arView: ARView) -> simd_float4x4? {
        let raycastResult = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
        let resultTransform = raycastResult.first?.worldTransform
        return resultTransform
    }
}

//
//  PixlyzerBlockState.swift
//  DeltaClient
//
//  Created by Rohan van Klinken on 3/7/21.
//

import Foundation
import DeltaCore

/// Block state data from pixlyzer.
public struct PixlyzerBlockState: Codable {
  public var luminance: Int?
  public var isRandomlyTicking: Bool?
  public var hasSidedTransparency: Bool?
  public var soundVolume: Double
  public var soundPitch: Double
  public var breakSound: Int
  public var stepSound: Int
  public var placeSound: Int
  public var hitSound: Int
  public var fallSound: Int
  public var requiresTool: Bool
  public var hardness: Double
  public var isOpaque: Bool?
  public var material: Identifier
  public var tintColor: Int?
  public var renderDescriptor: PixlyzerBlockRenderDescriptor
  public var collisionShape: Int
  public var outlineShape: Int
  public var solidRender: Bool?
  public var translucent: Bool?
  public var lightBlock: Int?
  public var largeCollisionShape: Bool?
  public var isCollisionShapeFullBlock: Bool?
  public var occlusionShape: Int?
  public var occlusionShapes: [Int]?
  public var isSturdy: Bool?
  
  enum CodingKeys: String, CodingKey {
    case luminance
    case isRandomlyTicking = "is_randomly_ticking"
    case hasSidedTransparency = "has_side_transparency"
    case soundVolume = "sound_type_volume"
    case soundPitch = "sound_type_pitch"
    case breakSound = "break_sound_type"
    case stepSound = "step_sound_type"
    case placeSound = "place_sound_type"
    case hitSound = "hit_sound_type"
    case fallSound = "fall_sound_type"
    case requiresTool = "requires_tool"
    case hardness
    case isOpaque = "is_opaque"
    case material
    case tintColor = "tint_color"
    case renderDescriptor = "render"
    case collisionShape = "collision_shape"
    case outlineShape = "outline_shape"
    case solidRender = "solid_render"
    case translucent
    case lightBlock = "light_block"
    case largeCollisionShape = "large_collision_shape"
    case isCollisionShapeFullBlock = "is_collision_shape_full_block"
    case occlusionShape = "occlusion_shapes" // There is a mistake in pixlyzer, the plural and the singular are swapped
    case occlusionShapes = "occlusion_shape"
    case isSturdy = "is_sturdy"
  }
}

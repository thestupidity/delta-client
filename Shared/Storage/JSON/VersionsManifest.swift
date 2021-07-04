//
//  VersionsManifest.swift
//  DeltaClient
//
//  Created by Rohan van Klinken on 3/7/21.
//

import Foundation

/// The structure of Mojang's version manifest. I call it the versions manifest because it contains info on all versions not just one.
struct VersionsManifest: Codable {
  var latest: LatestVersions
  var versions: [Version]
  
  struct LatestVersions: Codable {
    var release: String
    var snapshot: String
  }
  
  struct Version: Codable {
    var id: String
    var type: VersionType
    var url: URL
    var time: Date
    var releaseTime: Date
  }
  
  enum VersionType: String, Codable {
    case release
    case snapshot
  }
}

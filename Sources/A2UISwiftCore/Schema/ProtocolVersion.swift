// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

/// The A2UI wire-protocol version used in the `version` field of every envelope.
///
/// Incoming messages are accepted in any supported version. Outgoing messages
/// (renderer-to-agent) use `.v1_0` unless the encoder's `userInfo` carries
/// `A2UIProtocolVersion.userInfoKey` with another value.
public enum A2UIProtocolVersion: String, Sendable, Equatable {
    case v0_9 = "v0.9"
    case v1_0 = "1.0"

    /// `userInfo` key to select the version written by encoders.
    public static let userInfoKey = CodingUserInfoKey(rawValue: "a2ui.protocolVersion")!

    /// Parses a wire `version` string. v0.9.1 is a refinement of v0.9; `v1.0` is accepted
    /// as an alias of `1.0` because some documentation mirrors spell it that way.
    public init?(wire: String) {
        switch wire {
        case "v0.9", "v0.9.1": self = .v0_9
        case "1.0", "v1.0": self = .v1_0
        default: return nil
        }
    }

    /// The version an encoder should write.
    static func current(in encoder: Encoder) -> A2UIProtocolVersion {
        (encoder.userInfo[userInfoKey] as? A2UIProtocolVersion) ?? .v1_0
    }
}

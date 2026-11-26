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

// Mirrors WebCore schema/client-to-server.ts

// MARK: - A2uiClientAction

/// Reports a user-initiated action from a component.
/// Matches 'action' in specification/v0_9/json/client_to_server.json.
/// Mirrors WebCore `A2uiClientAction`.
public struct A2uiClientAction: Codable, Equatable {
    /// The name of the action, taken from the component's action.event.name property.
    public let name: String
    /// The id of the surface where the event originated.
    public let surfaceId: String
    /// The id of the component that triggered the event.
    public let sourceComponentId: String
    /// An ISO 8601 timestamp of when the event occurred.
    public let timestamp: String
    /// Key-value pairs from the component's action.event.context, after resolving all data bindings.
    public let context: [String: AnyCodable]
    /// A2UI 1.0: optional human-readable description of the action (`action.event.userMessage`,
    /// resolved by the renderer), for the agent to show or log.
    public let userMessage: String?
    /// A2UI 1.0: optional metadata (`{"extensions": ...}`).
    public let metadata: AnyCodable?

    public init(
        name: String,
        surfaceId: String,
        sourceComponentId: String,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        context: [String: AnyCodable] = [:],
        userMessage: String? = nil,
        metadata: AnyCodable? = nil
    ) {
        self.name = name
        self.surfaceId = surfaceId
        self.sourceComponentId = sourceComponentId
        self.timestamp = timestamp
        self.context = context
        self.userMessage = userMessage
        self.metadata = metadata
    }
}

// MARK: - A2uiClientError

/// Reports a client-side error.
/// Matches 'error' in specification/v0_9/json/client_to_server.json.
/// Mirrors WebCore `A2uiClientError`.
public struct A2uiClientError: Codable, Equatable {
    /// Error code. "VALIDATION_FAILED" for validation errors; other strings for generic errors.
    public let code: String
    /// The id of the surface where the error occurred.
    public let surfaceId: String
    /// A short description of why the error occurred.
    public let message: String
    /// For VALIDATION_FAILED: JSON pointer to the field that failed (e.g. '/components/0/text').
    public let path: String?
    /// Optional additional details about the error.
    public let details: [String: AnyCodable]?
    /// A2UI 1.0: id of the failed function call (agent-initiated `callRendererFunction`).
    /// The spec makes this mutually exclusive with `surfaceId`; here `surfaceId` stays required,
    /// so pass an empty string and the encoder omits it when `functionCallId` is set.
    public let functionCallId: String?

    public init(
        code: String,
        surfaceId: String,
        message: String,
        path: String? = nil,
        details: [String: AnyCodable]? = nil,
        functionCallId: String? = nil
    ) {
        self.code = code
        self.surfaceId = surfaceId
        self.message = message
        self.path = path
        self.details = details
        self.functionCallId = functionCallId
    }

    private enum CodingKeys: String, CodingKey {
        case code, surfaceId, message, path, details, functionCallId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        functionCallId = try container.decodeIfPresent(String.self, forKey: .functionCallId)
        surfaceId = try container.decodeIfPresent(String.self, forKey: .surfaceId) ?? ""
        message = try container.decode(String.self, forKey: .message)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        details = try container.decodeIfPresent([String: AnyCodable].self, forKey: .details)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        if let functionCallId {
            try container.encode(functionCallId, forKey: .functionCallId)
        } else {
            try container.encode(surfaceId, forKey: .surfaceId)
        }
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encodeIfPresent(details, forKey: .details)
    }
}

// MARK: - A2uiClientMessage

/// A message sent from the A2UI client to the server.
/// Matches specification/v0_9/json/client_to_server.json.
/// Mirrors WebCore `A2uiClientMessage`.
///
/// A2UI 1.0 (`renderer_to_agent.json`) adds `rendererFunctionResponse`. The 1.0 `callAgentFunction`
/// message is not modelled yet. The encoded `version` is `"1.0"` unless the encoder's `userInfo`
/// sets `A2UIProtocolVersion.userInfoKey`.
public enum A2uiClientMessage: Codable {
    case action(A2uiClientAction)
    case error(A2uiClientError)
    case rendererFunctionResponse(A2uiRendererFunctionResponse)

    private enum CodingKeys: String, CodingKey {
        case version, action, error, rendererFunctionResponse
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let action = try container.decodeIfPresent(A2uiClientAction.self, forKey: .action) {
            self = .action(action)
        } else if let error = try container.decodeIfPresent(A2uiClientError.self, forKey: .error) {
            self = .error(error)
        } else if let response = try container.decodeIfPresent(
            A2uiRendererFunctionResponse.self, forKey: .rendererFunctionResponse
        ) {
            self = .rendererFunctionResponse(response)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "A2uiClientMessage must contain 'action', 'error' or 'rendererFunctionResponse'."
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(A2UIProtocolVersion.current(in: encoder).rawValue, forKey: .version)
        switch self {
        case .action(let a): try container.encode(a, forKey: .action)
        case .error(let e): try container.encode(e, forKey: .error)
        case .rendererFunctionResponse(let r): try container.encode(r, forKey: .rendererFunctionResponse)
        }
    }
}

// MARK: - A2uiRendererFunctionResponse

/// A2UI 1.0 `rendererFunctionResponse`: result of an agent-initiated `callRendererFunction`.
public struct A2uiRendererFunctionResponse: Codable, Equatable {
    public struct FunctionError: Codable, Equatable {
        public let code: String
        public let message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    /// Copied verbatim from the request.
    public let functionCallId: String
    public let value: AnyCodable?
    public let error: FunctionError?

    public init(functionCallId: String, value: AnyCodable? = nil, error: FunctionError? = nil) {
        self.functionCallId = functionCallId
        self.value = value
        self.error = error
    }
}

// MARK: - A2uiClientDataModel

/// Schema for the client data model synchronization.
/// Matches specification/v0_9/json/client_data_model.json.
/// Mirrors WebCore `A2uiClientDataModel`.
public struct A2uiClientDataModel: Codable, Equatable {
    public let version: String
    /// A map of surface IDs to their current data models.
    public let surfaces: [String: AnyCodable]

    public init(version: String = A2UIProtocolVersion.v1_0.rawValue, surfaces: [String: AnyCodable]) {
        self.version = version
        self.surfaces = surfaces
    }
}

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

// MARK: - A2uiMessage

/// A discriminated-union message from the A2UI agent to the renderer (A2UI 1.0:
/// `agent_to_renderer.json`; A2UI 0.9: `server_to_client.json`).
/// Mirrors WebCore `A2uiMessage`.
///
/// Each case maps to one top-level JSON key. Decoding accepts the versions listed in
/// ``A2UIProtocolVersion``; encoding writes `"1.0"` unless the encoder's `userInfo`
/// selects another version (`A2UIProtocolVersion.userInfoKey`).
public enum A2uiMessage: Codable, Sendable {
    case createSurface(CreateSurfacePayload)
    case updateComponents(UpdateComponentsPayload)
    case updateDataModel(UpdateDataModelPayload)
    case deleteSurface(DeleteSurfacePayload)
    /// A2UI 1.0: the agent asks the renderer to run a function (was `callFunction` in drafts).
    case callRendererFunction(CallRendererFunctionPayload)
    /// A2UI 1.0: the agent answers a renderer-initiated `callAgentFunction`.
    case agentFunctionResponse(AgentFunctionResponsePayload)

    private enum CodingKeys: String, CodingKey {
        case version
        case createSurface
        case updateComponents
        case updateDataModel
        case deleteSurface
        case callRendererFunction
        case agentFunctionResponse

        var stringValue: String { rawValue }
    }

    /// The version found on the wire when this message was decoded is not stored;
    /// use ``A2UIProtocolVersion/init(wire:)`` on the raw string if you need it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let version = try container.decode(String.self, forKey: .version)
        guard A2UIProtocolVersion(wire: version) != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: #"A2UI message version must be "1.0", "v0.9" or "v0.9.1"."#
            )
        }

        // Validate: only one update-type key is allowed per message.
        let updateTypeKeys: [CodingKeys] = [
            .createSurface, .updateComponents, .updateDataModel, .deleteSurface,
            .callRendererFunction, .agentFunctionResponse,
        ]
        let presentKeys = updateTypeKeys.filter { container.contains($0) }
        if presentKeys.count > 1 {
            let names = presentKeys.map(\.stringValue).joined(separator: ", ")
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Message contains multiple update types: \(names)."
            ))
        }

        if let payload = try container.decodeIfPresent(CreateSurfacePayload.self, forKey: .createSurface) {
            self = .createSurface(payload)
        } else if let payload = try container.decodeIfPresent(UpdateComponentsPayload.self, forKey: .updateComponents) {
            self = .updateComponents(payload)
        } else if let payload = try container.decodeIfPresent(UpdateDataModelPayload.self, forKey: .updateDataModel) {
            self = .updateDataModel(payload)
        } else if let payload = try container.decodeIfPresent(DeleteSurfacePayload.self, forKey: .deleteSurface) {
            self = .deleteSurface(payload)
        } else if let payload = try container.decodeIfPresent(CallRendererFunctionPayload.self, forKey: .callRendererFunction) {
            self = .callRendererFunction(payload)
        } else if let payload = try container.decodeIfPresent(AgentFunctionResponsePayload.self, forKey: .agentFunctionResponse) {
            self = .agentFunctionResponse(payload)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Message must contain one of: createSurface, updateComponents, updateDataModel, deleteSurface, callRendererFunction, agentFunctionResponse."
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(A2UIProtocolVersion.current(in: encoder).rawValue, forKey: .version)
        switch self {
        case .createSurface(let payload):   try container.encode(payload, forKey: .createSurface)
        case .updateComponents(let payload): try container.encode(payload, forKey: .updateComponents)
        case .updateDataModel(let payload): try container.encode(payload, forKey: .updateDataModel)
        case .deleteSurface(let payload):   try container.encode(payload, forKey: .deleteSurface)
        case .callRendererFunction(let payload): try container.encode(payload, forKey: .callRendererFunction)
        case .agentFunctionResponse(let payload): try container.encode(payload, forKey: .agentFunctionResponse)
        }
    }
}

// MARK: - Payloads

/// `createSurface`.
///
/// A2UI 1.0: `catalogId` is optional (default catalog of the surface), initial `components`
/// and `dataModel` may be sent inline (the data model is applied first), `metadata` is new,
/// and `theme` is gone. A 0.9 `theme` is still read (and ignored by the processor) for
/// backward compatibility.
public struct CreateSurfacePayload: Codable, Sendable {
    public var surfaceId: String
    public var catalogId: String?
    public var theme: AnyCodable?
    public var sendDataModel: Bool
    /// A2UI 1.0: initial data model, applied before `components`.
    public var dataModel: AnyCodable?
    /// A2UI 1.0: initial components, same shape as `updateComponents.components`.
    public var components: [RawComponent]?
    /// A2UI 1.0: opaque metadata (`{"extensions": ...}`).
    public var metadata: AnyCodable?

    public init(
        surfaceId: String,
        catalogId: String? = nil,
        theme: AnyCodable? = nil,
        sendDataModel: Bool = false,
        dataModel: AnyCodable? = nil,
        components: [RawComponent]? = nil,
        metadata: AnyCodable? = nil
    ) {
        self.surfaceId = surfaceId
        self.catalogId = catalogId
        self.theme = theme
        self.sendDataModel = sendDataModel
        self.dataModel = dataModel
        self.components = components
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case surfaceId, catalogId, theme, sendDataModel, dataModel, components, metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        surfaceId = try container.decode(String.self, forKey: .surfaceId)
        catalogId = try container.decodeIfPresent(String.self, forKey: .catalogId)
        theme = try container.decodeIfPresent(AnyCodable.self, forKey: .theme)
        sendDataModel = try container.decodeIfPresent(Bool.self, forKey: .sendDataModel) ?? false
        dataModel = try container.decodeIfPresent(AnyCodable.self, forKey: .dataModel)
        components = try container.decodeIfPresent([RawComponent].self, forKey: .components)
        metadata = try container.decodeIfPresent(AnyCodable.self, forKey: .metadata)
    }
}

public struct UpdateComponentsPayload: Codable, Sendable {
    public var surfaceId: String
    public var components: [RawComponent]

    public init(surfaceId: String, components: [RawComponent]) {
        self.surfaceId = surfaceId
        self.components = components
    }
}

/// `updateDataModel`.
///
/// A2UI 1.0 makes `value` required and defines `null` as "delete the key at `path`".
/// Here a JSON `null` and an omitted `value` both decode to `value == nil` (delete), which
/// keeps 0.9 messages working. Encoding always writes `value` (as `null` for a delete).
public struct UpdateDataModelPayload: Codable, Sendable {
    public var surfaceId: String
    public var path: String?
    public var value: AnyCodable?

    public init(surfaceId: String, path: String? = nil, value: AnyCodable? = nil) {
        self.surfaceId = surfaceId
        self.path = path
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case surfaceId, path, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        surfaceId = try container.decode(String.self, forKey: .surfaceId)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        if let decoded = try container.decodeIfPresent(AnyCodable.self, forKey: .value), decoded != .null {
            value = decoded
        } else {
            value = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surfaceId, forKey: .surfaceId)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encode(value ?? .null, forKey: .value)
    }
}

public struct DeleteSurfacePayload: Codable, Sendable {
    public var surfaceId: String

    public init(surfaceId: String) {
        self.surfaceId = surfaceId
    }
}

/// A2UI 1.0 `callRendererFunction`: the agent asks the renderer to run a catalog function.
public struct CallRendererFunctionPayload: Codable, Sendable {
    public var functionCallId: String
    /// Omitted means an empty root data context.
    public var surfaceId: String?
    /// The call (`@call`, `catalogId`, `args`).
    public var callFunction: FunctionCall

    public init(functionCallId: String, surfaceId: String? = nil, callFunction: FunctionCall) {
        self.functionCallId = functionCallId
        self.surfaceId = surfaceId
        self.callFunction = callFunction
    }

    private enum CodingKeys: String, CodingKey {
        case functionCallId, surfaceId, callFunction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        functionCallId = try container.decode(String.self, forKey: .functionCallId)
        surfaceId = try container.decodeIfPresent(String.self, forKey: .surfaceId)
        let raw = try container.decode(AnyCodable.self, forKey: .callFunction)
        guard case .dictionary(let dict) = raw,
              case .functionCall(let call)? = DynamicDictResolver.resolve(dict) else {
            throw DecodingError.dataCorruptedError(
                forKey: .callFunction,
                in: container,
                debugDescription: "callFunction must be an object with '@call'."
            )
        }
        callFunction = call
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(functionCallId, forKey: .functionCallId)
        try container.encodeIfPresent(surfaceId, forKey: .surfaceId)
        var dict: [String: AnyCodable] = [
            "@call": .string(callFunction.call),
            "args": .dictionary(callFunction.args),
        ]
        if let catalogId = callFunction.catalogId { dict["catalogId"] = .string(catalogId) }
        if let returnType = callFunction.returnType { dict["returnType"] = .string(returnType.rawValue) }
        try container.encode(AnyCodable.dictionary(dict), forKey: .callFunction)
    }
}

/// A2UI 1.0 `agentFunctionResponse`: the result (or error) of a renderer-initiated agent call.
public struct AgentFunctionResponsePayload: Codable, Sendable {
    public struct FunctionError: Codable, Sendable, Equatable {
        public var code: String
        public var message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public var functionCallId: String
    public var value: AnyCodable?
    public var error: FunctionError?

    public init(functionCallId: String, value: AnyCodable? = nil, error: FunctionError? = nil) {
        self.functionCallId = functionCallId
        self.value = value
        self.error = error
    }
}

// MARK: - RawComponent

/// A raw component received in an `updateComponents` message.
/// The fixed fields `id`, `component`, `weight`, and `accessibility` are extracted;
/// all remaining keys become `properties`.
///
/// A2UI 1.0 prefixes the envelope keys with `@`: `@accessibility`, `@checks`, `@catalogId`,
/// `@metadata`. Both spellings are read. `@checks` is normalised into `properties["checks"]`
/// so component property decoding is unchanged.
/// Mirrors WebCore `AnyComponentSchema`.
public struct RawComponent: Sendable, Equatable {
    public var id: String
    public var component: String
    public var weight: Double?
    public var accessibility: A2UIAccessibility?
    public var properties: [String: AnyCodable]
    /// A2UI 1.0 `@catalogId`: catalog that defines this component (overrides the surface default).
    public var catalogId: String?
    /// A2UI 1.0 `@metadata`.
    public var metadata: AnyCodable?

    public init(
        id: String,
        component: String,
        weight: Double? = nil,
        accessibility: A2UIAccessibility? = nil,
        properties: [String: AnyCodable] = [:],
        catalogId: String? = nil,
        metadata: AnyCodable? = nil
    ) {
        self.id = id
        self.component = component
        self.weight = weight
        self.accessibility = accessibility
        self.properties = properties
        self.catalogId = catalogId
        self.metadata = metadata
    }
}

extension RawComponent: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try AnyCodable(from: decoder)
        guard case .dictionary(var dict) = raw else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "RawComponent must be a JSON object."
            ))
        }
        // `id` is required at the Codable level; missing-type is validated in MessageProcessor.
        guard let id = dict.removeValue(forKey: "id")?.stringValue else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "RawComponent missing 'id'."
            ))
        }
        self.id = id
        // `component` is optional at decode time; MessageProcessor validates its presence for new components.
        self.component = dict.removeValue(forKey: "component")?.stringValue ?? ""
        self.weight = dict.removeValue(forKey: "weight")?.numberValue
        let accRaw = dict.removeValue(forKey: "@accessibility") ?? dict.removeValue(forKey: "accessibility")
        if case .dictionary(let accDict)? = accRaw {
            self.accessibility = A2UIAccessibility.decode(from: accDict)
        } else {
            self.accessibility = nil
        }
        self.catalogId = dict.removeValue(forKey: "@catalogId")?.stringValue
        self.metadata = dict.removeValue(forKey: "@metadata")
        if let checks = dict.removeValue(forKey: "@checks") {
            dict["checks"] = checks
        }
        self.properties = dict
    }

    public func encode(to encoder: Encoder) throws {
        var dict = properties
        dict["id"] = .string(id)
        dict["component"] = .string(component)
        if let w = weight { dict["weight"] = .number(w) }
        if let accDict = accessibility?.toDict() {
            dict["accessibility"] = .dictionary(accDict)
        }
        if let catalogId { dict["@catalogId"] = .string(catalogId) }
        if let metadata { dict["@metadata"] = metadata }
        var container = encoder.singleValueContainer()
        try container.encode(dict)
    }
}

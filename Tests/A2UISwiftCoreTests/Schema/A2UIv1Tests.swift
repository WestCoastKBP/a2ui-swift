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

@testable import A2UISwiftCore
import Testing
import Foundation

/// A2UI 1.0 message parsing and processing.
/// Spec: https://a2ui.org/specification/v1.0-a2ui/ and
/// https://a2ui.org/specification/v1.0-evolution-guide/
@Suite("A2UI 1.0")
struct A2UIv1Tests {

    private static let catalogId = "https://kbp-ai.com/a2ui/catalogs/kbp-owner/v1/catalog.json"

    /// The live-call card stream (createSurface with inline components and data model,
    /// then two updateDataModel messages).
    private static let liveCallLines: [String] = [
        #"{"version":"1.0","createSurface":{"surfaceId":"call-live","catalogId":"https://kbp-ai.com/a2ui/catalogs/kbp-owner/v1/catalog.json","dataModel":{"call":{"status":"Идёт разговор","who":"+1 650 350-0970","line":"Личная линия","seconds":"0:12"}},"components":[{"id":"root","component":"Card","@accessibility":{"label":"Звонок сейчас","live":"polite"},"status":{"@path":"/call/status"},"title":{"@path":"/call/who"},"facts":[{"@path":"/call/line"},{"@path":"/call/seconds"}],"actions":[{"label":"Взять трубку","icon":"phone","style":"primary","action":{"event":{"name":"call.take_over","context":{"who":{"@path":"/call/who"}}}}}]}]}}"#,
        #"{"version":"1.0","updateDataModel":{"surfaceId":"call-live","path":"/call/seconds","value":"0:48"}}"#,
        #"{"version":"1.0","updateDataModel":{"surfaceId":"call-live","path":"/call/status","value":"Разговор окончен, 1 мин 6 с"}}"#,
    ]

    private func decode(_ json: String) throws -> A2uiMessage {
        try JSONDecoder().decode(A2uiMessage.self, from: Data(json.utf8))
    }

    private func makeProcessor() -> MessageProcessor {
        MessageProcessor(catalogs: [Catalog(id: Self.catalogId)])
    }

    // MARK: - Parsing

    @Test("parses createSurface with inline dataModel and components")
    func parsesCreateSurface() throws {
        let message = try decode(Self.liveCallLines[0])
        guard case .createSurface(let payload) = message else {
            Issue.record("expected createSurface")
            return
        }
        #expect(payload.surfaceId == "call-live")
        #expect(payload.catalogId == Self.catalogId)
        #expect(payload.theme == nil)
        #expect(payload.dataModel?.dictionaryValue?["call"] != nil)
        #expect(payload.components?.count == 1)
        #expect(payload.components?.first?.component == "Card")
    }

    @Test("createSurface without catalogId decodes")
    func createSurfaceWithoutCatalogId() throws {
        let message = try decode(#"{"version":"1.0","createSurface":{"surfaceId":"s"}}"#)
        guard case .createSurface(let payload) = message else {
            Issue.record("expected createSurface")
            return
        }
        #expect(payload.catalogId == nil)
        #expect(payload.sendDataModel == false)
    }

    @Test("parses updateDataModel with a value")
    func parsesUpdateDataModel() throws {
        let message = try decode(Self.liveCallLines[1])
        guard case .updateDataModel(let payload) = message else {
            Issue.record("expected updateDataModel")
            return
        }
        #expect(payload.surfaceId == "call-live")
        #expect(payload.path == "/call/seconds")
        #expect(payload.value == .string("0:48"))
    }

    @Test("accepts the 1.0 and v1.0 version strings, still accepts v0.9")
    func acceptsVersions() throws {
        for version in ["1.0", "v1.0", "v0.9", "v0.9.1"] {
            let json = #"{"version":"\#(version)","deleteSurface":{"surfaceId":"s1"}}"#
            let message = try decode(json)
            guard case .deleteSurface(let payload) = message else {
                Issue.record("expected deleteSurface for \(version)")
                continue
            }
            #expect(payload.surfaceId == "s1")
        }
    }

    @Test("rejects an unknown version")
    func rejectsUnknownVersion() {
        #expect(throws: Error.self) {
            _ = try decode(#"{"version":"2.0","deleteSurface":{"surfaceId":"s1"}}"#)
        }
    }

    @Test("parses callRendererFunction and agentFunctionResponse")
    func parsesFunctionMessages() throws {
        let call = try decode(
            #"{"version":"1.0","callRendererFunction":{"functionCallId":"f1","surfaceId":"s1","callFunction":{"@call":"openUrl","catalogId":"basic","args":{"url":"https://example.com"}}}}"#
        )
        guard case .callRendererFunction(let payload) = call else {
            Issue.record("expected callRendererFunction")
            return
        }
        #expect(payload.functionCallId == "f1")
        #expect(payload.surfaceId == "s1")
        #expect(payload.callFunction.call == "openUrl")
        #expect(payload.callFunction.catalogId == "basic")
        #expect(payload.callFunction.args["url"] == .string("https://example.com"))

        let response = try decode(
            #"{"version":"1.0","agentFunctionResponse":{"functionCallId":"f2","error":{"code":"X","message":"boom"}}}"#
        )
        guard case .agentFunctionResponse(let answer) = response else {
            Issue.record("expected agentFunctionResponse")
            return
        }
        #expect(answer.functionCallId == "f2")
        #expect(answer.error == AgentFunctionResponsePayload.FunctionError(code: "X", message: "boom"))
        #expect(answer.value == nil)
    }

    // MARK: - Bindings and component envelope

    @Test("@path and @call resolve like path and call")
    func dynamicDirectives() throws {
        let binding = try JSONDecoder().decode(
            DynamicString.self, from: Data(#"{"@path":"/call/status"}"#.utf8)
        )
        guard case .dataBinding(let path) = binding else {
            Issue.record("expected data binding")
            return
        }
        #expect(path == "/call/status")

        let function = try JSONDecoder().decode(
            DynamicString.self,
            from: Data(#"{"@call":"formatString","args":{"value":"## ${/title}"}}"#.utf8)
        )
        guard case .functionCall(let call) = function else {
            Issue.record("expected function call")
            return
        }
        #expect(call.call == "formatString")
        #expect(call.args["value"] == .string("## ${/title}"))
    }

    @Test("0.9 path and call objects still resolve (backward compatibility)")
    func legacyDirectives() throws {
        let binding = try JSONDecoder().decode(
            DynamicString.self, from: Data(#"{"path":"/name"}"#.utf8)
        )
        guard case .dataBinding(let path) = binding else {
            Issue.record("expected data binding")
            return
        }
        #expect(path == "/name")
    }

    @Test("component @-keys: @accessibility, @checks, @catalogId, @metadata")
    func componentEnvelopeKeys() throws {
        let json = #"""
        {"id":"email","component":"TextField","label":"Email","value":{"@path":"/form/email"},
         "@catalogId":"basic","@metadata":{"note":"x"},
         "@accessibility":{"label":"Email","live":"assertive","hidden":false},
         "@checks":[{"condition":{"@call":"required","args":{"value":{"@path":"/form/email"}}},"message":"Required"},
                    {"condition":true}]}
        """#
        let raw = try JSONDecoder().decode(RawComponent.self, from: Data(json.utf8))
        #expect(raw.catalogId == "basic")
        #expect(raw.metadata?.dictionaryValue?["note"] == .string("x"))
        #expect(raw.accessibility?.live == "assertive")
        #expect(raw.accessibility?.hidden == DynamicBoolean.literal(false))
        #expect(raw.properties["checks"]?.arrayValue?.count == 2)
        #expect(raw.properties["@checks"] == nil)

        let checks = try raw.typedProperties(TypedChecks.self).checks
        #expect(checks?.count == 2)
        #expect(checks?.first?.message == "Required")
        #expect(checks?.last?.message == "")
    }

    private struct TypedChecks: Decodable {
        var checks: [CheckRule]?
    }

    @Test("0.9 'accessibility' key still read")
    func legacyAccessibilityKey() throws {
        let json = #"{"id":"a","component":"Text","text":"x","accessibility":{"label":"Hi"}}"#
        let raw = try JSONDecoder().decode(RawComponent.self, from: Data(json.utf8))
        #expect(raw.accessibility?.label == DynamicString.literal("Hi"))
    }

    // MARK: - Processing the live-call stream

    @Test("processes the live-call stream end to end")
    func processesLiveCallStream() throws {
        let processor = makeProcessor()
        let messages = try Self.liveCallLines.map(decode)
        let errors = processor.processMessages(messages)
        #expect(errors.isEmpty)

        let surface = try #require(processor.model.getSurface("call-live"))
        #expect(surface.dataModel.get("/call/who") == .string("+1 650 350-0970"))
        // Later updateDataModel messages replaced the initial values.
        #expect(surface.dataModel.get("/call/seconds") == .string("0:48"))
        #expect(surface.dataModel.get("/call/status") == .string("Разговор окончен, 1 мин 6 с"))

        let root = try #require(surface.componentsModel.get("root"))
        #expect(root.type == "Card")
    }

    @Test("updateDataModel with null deletes the key")
    func nullDeletesKey() throws {
        let processor = makeProcessor()
        let create = try decode(
            #"{"version":"1.0","createSurface":{"surfaceId":"s","catalogId":"\#(Self.catalogId)","dataModel":{"a":1,"b":2}}}"#
        )
        let delete = try decode(#"{"version":"1.0","updateDataModel":{"surfaceId":"s","path":"/a","value":null}}"#)
        #expect(processor.processMessages([create, delete]).isEmpty)
        let surface = try #require(processor.model.getSurface("s"))
        #expect(surface.dataModel.get("/a") == nil)
        #expect(surface.dataModel.get("/b") == .number(2))
    }

    @Test("createSurface without catalogId uses the only loaded catalog")
    func singleCatalogFallback() throws {
        let processor = makeProcessor()
        let create = try decode(#"{"version":"1.0","createSurface":{"surfaceId":"s"}}"#)
        #expect(processor.processMessages([create]).isEmpty)
        #expect(processor.model.getSurface("s")?.catalogId == Self.catalogId)
    }

    @Test("createSurface without catalogId is an error when catalogs are ambiguous")
    func ambiguousCatalog() throws {
        let processor = MessageProcessor(catalogs: [Catalog(id: "a"), Catalog(id: "b")])
        let create = try decode(#"{"version":"1.0","createSurface":{"surfaceId":"s"}}"#)
        #expect(processor.processMessages([create]).count == 1)
    }

    @Test("callRendererFunction reaches the handler")
    func rendererFunctionHandler() throws {
        let processor = makeProcessor()
        var received: [String] = []
        processor.rendererFunctionHandler = { received.append($0.functionCallId) }
        let message = try decode(
            #"{"version":"1.0","callRendererFunction":{"functionCallId":"f1","callFunction":{"@call":"now","catalogId":"basic"}}}"#
        )
        #expect(processor.processMessages([message]).isEmpty)
        #expect(received == ["f1"])
    }

    // MARK: - Outgoing messages

    @Test("action message encodes version 1.0 with userMessage and metadata")
    func encodesActionV1() throws {
        let action = A2uiClientAction(
            name: "call.take_over",
            surfaceId: "call-live",
            sourceComponentId: "root",
            timestamp: "2026-11-25T00:00:00Z",
            context: ["who": .string("+1 650 350-0970")],
            userMessage: "Взять трубку"
        )
        let data = try JSONEncoder().encode(A2uiClientMessage.action(action))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? String == "1.0")
        let encoded = try #require(object["action"] as? [String: Any])
        #expect(encoded["name"] as? String == "call.take_over")
        #expect(encoded["userMessage"] as? String == "Взять трубку")
        #expect(encoded["metadata"] == nil)
    }

    @Test("userInfo selects the 0.9 wire version")
    func encodesLegacyVersion() throws {
        let encoder = JSONEncoder()
        encoder.userInfo[A2UIProtocolVersion.userInfoKey] = A2UIProtocolVersion.v0_9
        let message = A2uiMessage.deleteSurface(DeleteSurfacePayload(surfaceId: "s"))
        let data = try encoder.encode(message)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains(#""version":"v0.9""#))
    }

    @Test("updateDataModel always encodes value, null for a delete")
    func encodesNullValue() throws {
        let message = A2uiMessage.updateDataModel(UpdateDataModelPayload(surfaceId: "s", path: "/a"))
        let data = try JSONEncoder().encode(message)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try #require(object["updateDataModel"] as? [String: Any])
        #expect(payload["value"] is NSNull)
    }

    @Test("rendererFunctionResponse round-trips")
    func rendererFunctionResponseRoundTrip() throws {
        let response = A2uiRendererFunctionResponse(functionCallId: "f1", value: .string("ok"))
        let data = try JSONEncoder().encode(A2uiClientMessage.rendererFunctionResponse(response))
        let decoded = try JSONDecoder().decode(A2uiClientMessage.self, from: data)
        guard case .rendererFunctionResponse(let back) = decoded else {
            Issue.record("expected rendererFunctionResponse")
            return
        }
        #expect(back == response)
    }

    @Test("error with functionCallId omits surfaceId")
    func errorWithFunctionCallId() throws {
        let error = A2uiClientError(
            code: "INVALID_FUNCTION_CALL", surfaceId: "", message: "nope", functionCallId: "f1"
        )
        let data = try JSONEncoder().encode(A2uiClientMessage.error(error))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encoded = try #require(object["error"] as? [String: Any])
        #expect(encoded["functionCallId"] as? String == "f1")
        #expect(encoded["surfaceId"] == nil)
    }

    @Test("capabilities are keyed by 1.0 by default and by v0.9 on request")
    func capabilitiesKeys() throws {
        let processor = makeProcessor()
        let v1 = try JSONEncoder().encode(processor.clientCapabilities)
        let v1Object = try #require(JSONSerialization.jsonObject(with: v1) as? [String: Any])
        #expect(v1Object["1.0"] != nil)

        let legacy = A2uiClientCapabilities.make(from: [Catalog(id: "c")], protocolVersion: .v0_9)
        let legacyData = try JSONEncoder().encode(legacy)
        let legacyObject = try #require(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
        #expect(legacyObject["v0.9"] != nil)

        let decoded = try JSONDecoder().decode(A2uiClientCapabilities.self, from: legacyData)
        #expect(decoded.protocolVersion == .v0_9)
        #expect(decoded.v09.supportedCatalogIds == ["c"])
    }

    // MARK: - Review fixes

    @Test("capabilities keyed by neither 1.0 nor v0.9 give a descriptive error")
    func capabilitiesUnknownKey() throws {
        do {
            _ = try JSONDecoder().decode(A2uiClientCapabilities.self, from: Data(#"{"unsupported":{}}"#.utf8))
            Issue.record("expected a decoding error")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription.contains("1.0"))
        }
    }

    @Test("callRendererFunction keeps returnType when re-encoded")
    func callRendererFunctionReturnTypeRoundTrip() throws {
        let message = try decode(
            #"{"version":"1.0","callRendererFunction":{"functionCallId":"f2","callFunction":{"@call":"now","returnType":"string"}}}"#
        )
        let data = try JSONEncoder().encode(message)
        guard case .callRendererFunction(let payload) = try JSONDecoder().decode(A2uiMessage.self, from: data) else {
            Issue.record("expected callRendererFunction")
            return
        }
        #expect(payload.callFunction.returnType == .string)
        #expect(payload.callFunction.call == "now")
    }
}

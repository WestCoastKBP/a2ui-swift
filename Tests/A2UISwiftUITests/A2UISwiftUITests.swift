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

import Testing
import SwiftUI
import A2UISwiftCore
import A2UISwiftUI

// TODO: Add SwiftUI layer tests here
// e.g. SurfaceViewModel, A2UIComponentView, CatalogItem overrides

@Suite("SurfaceViewModel client data model")
@MainActor
struct SurfaceViewModelClientDataModelTests {

    @Test("getClientDataModel writes 1.0 by default and v0.9 when asked")
    func clientDataModelVersion() {
        let surface = SurfaceModel(id: "s", catalog: Catalog(id: "c"), sendDataModel: true)
        let model = SurfaceViewModel(surface: surface)
        #expect(model.getClientDataModel()?.version == "1.0")
        model.protocolVersion = .v0_9
        #expect(model.getClientDataModel()?.version == "v0.9")
    }
}

//
//  LandMarksApp.swift
//  LandMarks
//
//  Created by ybw on 2026/4/22.
//

import SwiftUI

@main
struct LandMarksApp: App {
    @State var modelData = ModelData()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(modelData)
        }
    }
}

//
//  ContentView.swift
//  LandMarks
//
//  Created by ybw on 2026/4/22.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        
        LandMarkList()
       
    }
}

#Preview {
    ContentView().environment(ModelData())
}

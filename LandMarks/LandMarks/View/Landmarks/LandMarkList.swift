//
//  LandMarkList.swift
//  LandMarks
//
//  Created by ybw on 2026/4/24.
//

import SwiftUI

struct LandMarkList: View {
    @Environment(ModelData.self) var modelData
    
    @State private var showFavoritesOnly = false
    
    var filteredLandmarks: [Landmark] {
        modelData.landmarks.filter { landmark in
            (!showFavoritesOnly || landmark.isFavorite)
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List (){
                Toggle(isOn: $showFavoritesOnly) {
                    Text("Favorites only")
                }
                
                ForEach(filteredLandmarks) { l in
                    NavigationLink {
                        LandMarkDetail(landmark: l)
                   } label: {
                       LandMarkRow(landmark: l)
                   }
                }
            }
            .animation(.default, value: filteredLandmarks)
            .navigationTitle("Landmarks")
        } detail: {
            Text("Select a Landmark")
        }
       
    }
}

#Preview {
    LandMarkList().environment(ModelData())
}

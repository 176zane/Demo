//
//  LandMarkList.swift
//  LandMarks
//
//  Created by ybw on 2026/4/24.
//

import SwiftUI

struct LandMarkList: View {
    
    var body: some View {
        NavigationSplitView {
            List (landmarks){ l in
//                LandMarkRow(landmark: l)
                
                NavigationLink {
                    LandMarkDetail(landmark: l)
               } label: {
                   LandMarkRow(landmark: l)
               }
            }
            .navigationTitle("Landmarks")
        } detail: {
            Text("22")
        }
       
    }
}

#Preview {
    LandMarkList()
}

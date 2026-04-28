//
//  LandMarkRow.swift
//  LandMarks
//
//  Created by ybw on 2026/4/24.
//

import SwiftUI

struct LandMarkRow: View {
    
    var landmark: Landmark
    
    var body: some View {
        HStack {
            landmark.image
                .resizable()
                .frame(width: 50,height: 50)
                .background(.gray)
                    
            Text(landmark.name)
            Spacer()
            if landmark.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}

#Preview("rock") {
    let landmarks = ModelData().landmarks
    Group {
        LandMarkRow(landmark: landmarks[0])
        LandMarkRow(landmark: landmarks[1])
    }
}


//
//  CircleImage.swift
//  LandMarks
//
//  Created by ybw on 2026/4/23.
//

import SwiftUI

struct CircleImage: View {
    var image: Image
    var body: some View {
        
        image
            .clipShape(.circle)
            .overlay{
                Circle().stroke(.white,lineWidth: 5)
            }
            .shadow(radius: 5)
    }
}

#Preview {
    CircleImage(image: Image("turtlerock"))
}

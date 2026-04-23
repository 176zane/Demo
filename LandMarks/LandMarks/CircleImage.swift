//
//  CircleImage.swift
//  LandMarks
//
//  Created by ybw on 2026/4/23.
//

import SwiftUI

struct CircleImage: View {
    var body: some View {
        Image("turtlerock")
            .clipShape(.circle)
            .overlay{
                Circle().stroke(.white,lineWidth: 5)
            }
            .shadow(radius: 5)
    }
}

#Preview {
    CircleImage()
}

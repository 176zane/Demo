//
//  LandMarkDetail.swift
//  LandMarks
//
//  Created by ybw on 2026/4/24.
//

import SwiftUI

struct LandMarkDetail: View {
    var landmark: Landmark
    
    var body: some View {
        ScrollView {
            MapView(coordinate: landmark.locationCoordinate)
                           .frame(height: 300)

            CircleImage(image: landmark.image)
                .offset(y:-130)
                .padding(.bottom,-130)
                //.background(.gray)
            VStack (alignment: .leading){
                Text(landmark.name)
                    .font(.title)
                    .foregroundStyle(.red)
                    .background(.green)
                HStack {
                    Text(landmark.park)
                    Spacer()
                    Text(landmark.state)
                        
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Divider()


                Text("About \(landmark.name)")
                   .font(.title2)
                Text(landmark.description)
            }.padding()
      
        }
        
    }
}

#Preview {
    LandMarkDetail(landmark: landmarks[2])

}

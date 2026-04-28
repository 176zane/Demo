//
//  LandMarkDetail.swift
//  LandMarks
//
//  Created by ybw on 2026/4/24.
//

import SwiftUI

struct LandMarkDetail: View {
    @Environment(ModelData.self) var modelData
    
    var landmark: Landmark
    var landmarkIndex: Int {
         modelData.landmarks.firstIndex(where: { $0.id == landmark.id })!
     }
    
    var body: some View {
        @Bindable var modelData = modelData
        
        ScrollView {
            MapView(coordinate: landmark.locationCoordinate)
                           .frame(height: 300)

            CircleImage(image: landmark.image)
                .offset(y:-130)
                .padding(.bottom,-130)
                //.background(.gray)
            VStack (alignment: .leading){
                HStack {
                    Text(landmark.name)
                        .font(.title)
                        .foregroundStyle(.red)
                        .background(.green)
                    FavoriteButton(isSet: $modelData.landmarks[landmarkIndex].isFavorite)
                }
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
    let modelData = ModelData()

    let landmarks = modelData.landmarks
    LandMarkDetail(landmark: landmarks[2]).environment(modelData)

}

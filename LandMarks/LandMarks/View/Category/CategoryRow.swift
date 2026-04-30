//
//  CategoryRow.swift
//  LandMarks
//
//  Created by ybw on 2026/4/30.
//

import SwiftUI

struct CategoryItem: View {
    var landmark: Landmark


    var body: some View {
        VStack(alignment: .leading) {
            landmark.image
                .renderingMode(.original)
                .resizable()
                .frame(width: 155, height: 155)
                .cornerRadius(5)
            Text(landmark.name)
                .foregroundStyle(.primary)
                .font(.caption)
        }
        .padding(.leading, 15)
    }
}

struct CategoryRow: View {
    var categoryName: String
        var items: [Landmark]


    var body: some View {
        VStack(alignment: .leading) {
            Text(categoryName)
                .font(.headline)
                .padding(.leading, 15)
                .padding(.top, 5)


            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(items) { landmark in
                        //CategoryItem(landmark: landmark)
                        NavigationLink {
                           LandMarkDetail(landmark: landmark)
                       } label: {
                           CategoryItem(landmark: landmark)
                       }
                    }
                }
            }
            .frame(height: 185)
        }
    }
}

#Preview {

    let landmarks = ModelData().landmarks
    
    Group {
        CategoryRow(
            categoryName: landmarks[0].category.rawValue,
            items: Array(landmarks.prefix(4))
        )
        CategoryItem(landmark: ModelData().landmarks[0])
    }
    
}

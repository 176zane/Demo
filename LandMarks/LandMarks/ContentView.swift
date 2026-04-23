//
//  ContentView.swift
//  LandMarks
//
//  Created by ybw on 2026/4/22.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
       
        VStack {
            MapView()
                .frame(height: 300)
            CircleImage()
                .offset(y:-130)
                .padding(.bottom,-130)
                //.background(.gray)
            VStack (alignment: .leading){
                Text("Turtle Rock")
                    .font(.title)
                    .foregroundStyle(.red)
                    .background(.green)
                HStack {
                    Text("Joshua Tree National Park")
                    Spacer()
                    Text("California")
                        
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Divider()


               Text("About Turtle Rock")
                   .font(.title2)
               Text("Descriptive text goes here.")
            }.padding()
            Spacer()
        }
        
       
    }
}

#Preview {
    ContentView()
}

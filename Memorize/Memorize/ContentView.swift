//
//  ContentView.swift
//  Memorize
//
//  Created by ybw on 2026/1/8.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        HStack{
            CardView(isFaceUp: true)
            CardView()
            CardView()
            CardView()
        }
        .foregroundColor(.orange)
        .padding()
    }
}

struct CardView: View {
    var isFaceUp = false
    var body: some View {
        ZStack {
            if isFaceUp {

                
                RoundedRectangle(cornerRadius: 12).stroke(lineWidth: 2).foregroundColor(.black)
                Text("👻").font(.largeTitle)
                
                
            }else {
                RoundedRectangle(cornerRadius: 12)
            }
        }
    }
}
#Preview {
    ContentView()
}

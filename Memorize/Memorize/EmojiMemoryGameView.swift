//
//  ContentView.swift
//  Memorize
//
//  Created by ybw on 2026/1/8.
//

import SwiftUI

struct EmojiMemoryGameView: View {
    @ObservedObject var viewModel : EmojiMemoryGame
    
    
    var body: some View {
        VStack {
            ScrollView{
               cards
            }
            .foregroundColor(.orange)
            Button("Shuffle") {
                viewModel.shuffle()
            }
        }
        

        .padding()
    }
    var cards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 95),spacing: 0)],spacing: 0, content: {
            ForEach(viewModel.cards.indices,id: \.self) { index in
                CardView(card: viewModel.cards[index])
                    .aspectRatio(2/3, contentMode: .fit).padding(4)
            }
        })
    }
}


struct CardView: View {
    let card: MemoryGamge<String>.Card
    
    var body: some View {
        ZStack(alignment: .center) {
            let base = RoundedRectangle(cornerRadius: 12)
            
            Group {
                base.fill(.white)
                base.strokeBorder(lineWidth: 2)
                Text(card.content).font(.system(size: 200)).minimumScaleFactor(0.01).aspectRatio(contentMode: .fit)
            }.opacity(card.isFaceUp ? 1 : 0)
            
            base.fill().opacity(card.isFaceUp ? 0 : 1)
            
        }.onTapGesture {
            
        }
    }
}
#Preview {
    EmojiMemoryGameView(viewModel: EmojiMemoryGame())
}

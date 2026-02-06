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
//            ScrollView{
//               cards
//                    .animation(.default, value: viewModel.cards)
//                    .background(.green)
//            }
//            .background(.red)
            
            cards
                .animation(.default, value: viewModel.cards)
                .background(.green)
            
            .foregroundColor(.orange)
//            Text("hello").background(Rectangle().foregroundColor(.red))
//            Circle().overlay(Text("hellow").foregroundColor(.red),alignment: .center)
            Button("Shuffle") {
                viewModel.shuffle()
            }
        }
        .padding()
    }
    
    
    
    @ViewBuilder
    var cards: some View {
//        LazyHGrid(rows: [GridItem(.adaptive(minimum: 95),spacing: 0)], content: {
//            ForEach(viewModel.cards) { c in
//                CardView(card: c)
//                    .aspectRatio(2/3, contentMode: .fit)
//                    .padding(4)
//                    .onTapGesture {
//                        viewModel.choose(c)
//                    }
//                    
//            }
//        })
        let aspect:CGFloat = 2/3
        AspectVGrid(items: viewModel.cards, aspecRatio: aspect){ c in
            VStack {
                CardView(card: c)
                    .aspectRatio(aspect, contentMode: .fit)
                    .padding(4)
                    .onTapGesture {
                        viewModel.choose(c)
                    }
                Text(c.id)
            }
            
                
        }
        .foregroundColor(.orange)
        }
        
}



#Preview {
    EmojiMemoryGameView(viewModel: EmojiMemoryGame())
}

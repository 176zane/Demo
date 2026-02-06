//
//  CardView.swift
//  Memorize
//
//  Created by ybw on 2026/2/5.
//

import SwiftUI



struct CardView: View {
    typealias Card = MemoryGamge<String>.Card
    
    let card: Card
    
    var body: some View {
        ZStack {
            let base = RoundedRectangle(cornerRadius: Constants.cornerRadius)
            Group {
                base.fill(.white)
                base.strokeBorder(lineWidth: Constants.lineWidth)
                Text(card.content)
                    .font(.system(size: Constants.FontSize.largest))
                    .minimumScaleFactor(Constants.FontSize.scaleFactor)

                    .multilineTextAlignment(.center)
                    .padding(Constants.inset)
                    
            }
            .opacity(card.isFaceUp ? 1 : 0)
            base.fill().opacity(card.isFaceUp ? 0 : 1)
        }
        .opacity(card.isFaceUp || !card.isMatched ? 1 : 0)
    }
    
    private struct Constants {
        static let cornerRadius: CGFloat = 12
        static let lineWidth: CGFloat = 2
        static let inset: CGFloat = 5
        struct FontSize{
            static let largest: CGFloat = 200
            static let smallest: CGFloat = 10
            static let scaleFactor = smallest / largest
        }
    }
}

#Preview {
    VStack {
        HStack {
            CardView(card: MemoryGamge<String>.Card(id: "test1",isFaceUp: true, content: "test"))
                .aspectRatio(4/3, contentMode: .fit)
            CardView(card: MemoryGamge<String>.Card(id: "test2", content: "test"))
        }
        HStack {
            CardView(card: MemoryGamge<String>.Card(id: "test1", isFaceUp: true, content: "this is a very long  string"))
            CardView(card: MemoryGamge<String>.Card(id: "test2", content: "test"))
        }
    }
    
    
        .padding()
        .foregroundColor(.blue)
    
    
}

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
        Pie(endAngle: .degrees(240))
            .opacity(0.5)
            .overlay (
                Text(card.content)
                    .font(.system(size: Constants.FontSize.largest))
                    .minimumScaleFactor(Constants.FontSize.scaleFactor)
                    .multilineTextAlignment(.center)
                    .aspectRatio(contentMode: .fit)
                    .padding(Constants.inset)
        )   
        .cardify(isFaceUp: card.isFaceUp)
        .padding(Constants.inset)
        .opacity(card.isFaceUp || !card.isMatched ? 1 : 0)
    }
    
    private struct Constants {
        static let cornerRadius: CGFloat = 12
        static let lineWidth: CGFloat = 4
        static let inset: CGFloat = 8
        struct FontSize{
            static let largest: CGFloat = 200
            static let smallest: CGFloat = 10
            static let scaleFactor = smallest / largest
        }
    }
}

//#Preview {
//    VStack {
//        HStack {
//            CardView(card: MemoryGamge<String>.Card(id: "test1",isFaceUp: true, content: "test"))
//                .aspectRatio(4/3, contentMode: .fit)
//            CardView(card: MemoryGamge<String>.Card(id: "test2", content: "test"))
//        }
//        HStack {
//            CardView(card: MemoryGamge<String>.Card(id: "test1", isFaceUp: true, content: "this is a very long  string"))
//            CardView(card: MemoryGamge<String>.Card(id: "test2", content: "test"))
//        }
//    }
//    
//    
//        .padding()
//        .foregroundColor(.blue)
//    
//    
//}

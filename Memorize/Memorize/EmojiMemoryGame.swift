//
//  EmojiMemoryGame.swift
//  Memorize
//
//  Created by ybw on 2026/1/19.
//

import Foundation
internal import Combine

class EmojiMemoryGame: ObservableObject {

    private static let emojis = ["❤️","😭","🙈","👅","🤖",]
    private static func createMemoryGame() -> MemoryGamge<String> {
        return MemoryGamge(numberOfPairsOfCards: 4) { pairIndex in
            if emojis.indices.contains(pairIndex) {
                return emojis[pairIndex]
            }else {
                return "?"
            }
        }
    }
    
   @Published private var model = createMemoryGame()
    
    var cards: Array<MemoryGamge<String>.Card>{
        return model.cards
    }
    func shuffle(){
        model.shuffle()
    }
    func choose(_ card: MemoryGamge<String>.Card) {
        model.choose(card: card)
    }
}

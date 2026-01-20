//
//  MemorizeGame.swift
//  Memorize
//
//  Created by ybw on 2026/1/19.
//

import Foundation
struct MemoryGamge<CardContent>{
    struct Card {
        var isFaceUp: Bool = true
        var isMatched: Bool = false
        var content: CardContent
    }
    private(set) var cards: Array<Card>
    
    init(numberOfPairsOfCards:Int, cardContentFactoty:(Int)->CardContent) {
        cards = []
        for i in 0..<numberOfPairsOfCards {
            let content = cardContentFactoty(i)
            cards.append(Card(content: content))
            cards.append(Card(content: content))
        }
    }
    
    func choose(card:Card) {
        
    }
    mutating func shuffle(){
        cards.shuffle()
    }
    
}

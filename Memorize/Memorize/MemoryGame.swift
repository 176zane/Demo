//
//  MemorizeGame.swift
//  Memorize
//
//  Created by ybw on 2026/1/19.
//

import Foundation
struct MemoryGamge<CardContent> where CardContent:Equatable{
    struct Card :Equatable,Identifiable{
        var id: String
        
        var isFaceUp: Bool = true
        var isMatched: Bool = false
        var content: CardContent
    }
    private(set) var cards: Array<Card>
    
    init(numberOfPairsOfCards:Int, cardContentFactoty:(Int)->CardContent) {
        cards = []
        for i in 0..<numberOfPairsOfCards {
            let content = cardContentFactoty(i)
            cards.append(Card(id: "\(i)a", content: content))
            cards.append(Card(id: "\(i)b", content: content))
        }
    }
    var theOneAndOnlyFaceUpCardIndex: Int? {
        get {
            cards.indices.filter{cards[$0].isFaceUp}.only
        }
        set {
            cards.indices.forEach { i in
                cards[i].isFaceUp = i == newValue
            }
        }
    }
    mutating func choose(card:Card) {
        if let i = cards.firstIndex(where: {$0 == card}) {
           
            if !cards[i].isFaceUp && !cards[i].isMatched {
                if let oneIndex = theOneAndOnlyFaceUpCardIndex {
                    if cards[i].content == cards[oneIndex].content {
                        cards[i].isMatched = true
                        cards[oneIndex].isMatched = true
                    }
                }else {
                    theOneAndOnlyFaceUpCardIndex = i
                }
                cards[i].isFaceUp = true
            }
        }

//        //错误用法，cards.first返回的是第一个满足条件的元素的副本，并不是元素本身，此处值类型修改属性对数组里面的元素本身无效
//        if var c = cards.first(where: {$0 == card}) {
//            c.isFaceUp.toggle()
//        }
       
    }
    mutating func shuffle(){
        cards.shuffle()
    }
}

extension Array{
    var only: Element? {
        count == 1 ? first : nil
    }
}

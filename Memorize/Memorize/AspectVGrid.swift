//
//  AspectVGrid.swift
//  Memorize
//
//  Created by ybw on 2026/2/4.
//

import SwiftUI

struct AspectVGrid<Item:Identifiable,ItemView:View>: View {
    var items: [Item]
    var aspecRatio:CGFloat = 1
    var content:(Item) -> ItemView

    
    var body: some View {
        GeometryReader {geometry in
            let gridItemWidth = gridItemWidthThatFits(count:items.count, size: geometry.size, aspectRatio: aspecRatio)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: gridItemWidth),spacing: 0)],spacing: 0, content: {
                ForEach(items) {i in
                    content(i).aspectRatio(aspecRatio, contentMode: .fit)
                    
                }
            })
        }
    }
    func gridItemWidthThatFits(count:Int,size:CGSize,aspectRatio:CGFloat) ->CGFloat {
        let count = CGFloat(count)
        var columnCount = 1.0
        repeat {
            let width = size.width / columnCount
            let height = width / aspectRatio
            
            let rowCount = (count / columnCount).rounded(.up)
            if rowCount * height < size.height {
                return (size.width / columnCount).rounded(.down)
            }
            columnCount += 1
        } while columnCount < count
        
        return min(size.width / count, size.height*aspectRatio).rounded(.down)
    }
}



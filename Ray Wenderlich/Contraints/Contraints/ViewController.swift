//
//  ViewController.swift
//  Contraints
//
//  Created by Deep Thought on 2017/5/15.
//  Copyright © 2017年 Zane. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func buttonTapped(_ sender: UIButton) {
        if sender.title(for: .normal) == "X" {
            sender.setTitle("A very long title for this button", for: .normal)
        } else {
            sender.setTitle("X", for: .normal)
        }
    }


    
    
}


//
//  ViewController.swift
//  Translate
//
//  Created by 李阳 on 2022/1/24.
//

import Cocoa


class ViewController: NSViewController {
    @IBOutlet weak var segmentControl: NSSegmentedControl!
    @IBOutlet weak var copyToPboardButton: NSButton!
    
    @IBOutlet weak var tag1: NSTextField!
    @IBOutlet var textView1: NSTextView!
    
    @IBOutlet weak var tag2: NSTextField!
    @IBOutlet var textView2: NSTextView!
    
    @IBOutlet weak var column3Container: NSView!
    @IBOutlet weak var tag3: NSTextField!
    @IBOutlet var textView3: NSTextView!
    
    private var lastSelectedIndex = 0
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        setupBody()
    }

    @IBAction func pasteboardButtonDidClick(_ sender: NSButton) {
        let pboard = NSPasteboard.general
        print(pboard.string(forType: .string) ?? "empty")
        guard let string = pboard.string(forType: .string)?.trim(),
              !string.isEmpty else { return }
        perform(string, setter: true)
    }
    @IBAction func runButtonDidClick(_ sender: NSButton) {
        let index = segmentControl.selectedSegment
        if index == 0 {
            perform(textView2.string.trim())
        } else {
            perform(textView1.string.trim())
        }
    }
    @IBAction func segmentControlDidClick(_ sender: NSSegmentedControl) {
        let index = segmentControl.selectedSegment
        guard lastSelectedIndex != index else { return }
        lastSelectedIndex = index
        resetUI()
    }
}

private extension ViewController {
    func perform(_ string: String, setter: Bool = false) {
        let index = segmentControl.selectedSegment
        if index == 0 {
            let sample = textView1.string.trim()
            if setter { textView2.string = string }
            let res = Translate.strings(from: string, refer: sample)
            textView3.string = res
            
            guard copyToPboardButton.state == .on,
                  !res.isEmpty else { return }
            copyToPasterboard(res)
        } else if index == 1 {
            if setter { textView1.string = string }
            let res = Translate.excel(from: string)
            textView2.string = res.key
            textView3.string = res.value
            
            guard copyToPboardButton.state == .on else { return }
            copyToPasterboard(res.value)
            copyToPasterboard(res.key)
        } else {
            if setter { textView1.string = string }
            let res = Translate.validFormat(string) ?? "Paussed"
            textView2.string = res
        }
    }
    
    func copyToPasterboard(_ strings: String...) {
        guard !strings.isEmpty else { return }
        let pboard = NSPasteboard.general
        pboard.declareTypes([.string], owner: nil)
        for string in strings {
            pboard.setString(string, forType: .string)
        }
    }
}

private extension ViewController {
    func setupBody() {
        segmentControl.selectedSegment = lastSelectedIndex
        [tag1, tag2, tag3].forEach {
            $0?.isEditable = false
        }
        
        textView1.becomeFirstResponder()
        tag1.stringValue = "请输入翻译样本"
        
        resetUI()
    }
    func resetUI() {
        let index = segmentControl.selectedSegment
        
        if index == 2 {
            column3Container.isHidden = true
        } else {
            column3Container.isHidden = false
        }
        textView2.string = ""
        textView3.string = ""
        if index == 0 {
            tag2.stringValue = "请输入Excel中的翻译"
            tag3.stringValue = "结果"
        } else if index == 1 {
            tag2.stringValue = "Keys"
            tag3.stringValue = "Values"
        } else {
            tag2.stringValue = "结果"
        }
    }
}

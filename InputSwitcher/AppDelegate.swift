import Cocoa               // macOSアプリ（NSApp/NSMenu/NSStatusItemなど）の基本
import Carbon              // 入力ソース（日本語/英数）の情報取得など、古いけど今も使うAPIがある
import ServiceManagement   // ログイン時自動起動（macOS 13+ の SMAppService）

/// メニューバー常駐アプリの本体（アプリ起動〜メニュー作成〜キー監視を全部まとめている）
class AppDelegate: NSObject, NSApplicationDelegate {

    // =========================
    // メニューバーUI関連
    // =========================

    /// メニューバーに出るアイコン（ステータスアイテム）
    var statusItem: NSStatusItem?

    // =========================
    // キー監視（Event Tap）関連
    // =========================

    /// macOSのキーイベントを監視するための EventTap（これがないとCmd押下を拾えない）
    var eventTap: CFMachPort?

    /// EventTapをRunLoopにぶら下げるためのソース
    /// ※保持しておくと安定しやすい（参照が切れて不安定になるのを防ぐ）
    var eventTapSource: CFRunLoopSource?

    /// 「今押されているCmdキー」が左(54)か右(55)かを覚える
    var pressedCmdKeyCode: CGKeyCode? = nil

    /// Cmdを押している間に別キーが押されたかどうか（Cmd+Sなどのショートカット判定に使う）
    var otherKeyPressed = false


    // =========================
    // ユーザー設定（UserDefaults）関連
    // =========================
    // ※UserDefaultsは「アプリ設定を保存する箱」
    // 例：左右のCmd割り当て、Dock表示など

    /// trueなら「左Cmd=日本語、右Cmd=英数」
    /// falseなら「左Cmd=英数、右Cmd=日本語」
    var leftCmdIsJapanese: Bool {
        get { UserDefaults.standard.bool(forKey: "leftCmdIsJapanese") }
        set { UserDefaults.standard.set(newValue, forKey: "leftCmdIsJapanese") }
    }

    /// Dockに表示するかどうか（メニューバー常駐アプリは通常Dockに出さないことが多い）
    var showInDock: Bool {
        get { UserDefaults.standard.bool(forKey: "showInDock") }
        set {
            UserDefaults.standard.set(newValue, forKey: "showInDock")
            updateDockVisibility() // 設定が変わったら即反映
        }
    }


    // =========================
    // アプリ起動時に呼ばれる（最重要）
    // =========================
    func applicationDidFinishLaunching(_ notification: Notification) {

        // 初回起動の場合、設定が未登録なのでデフォルト値を入れる
        if UserDefaults.standard.object(forKey: "leftCmdIsJapanese") == nil {
            UserDefaults.standard.set(true, forKey: "leftCmdIsJapanese")
        }
        if UserDefaults.standard.object(forKey: "showInDock") == nil {
            UserDefaults.standard.set(false, forKey: "showInDock")
        }

        // Dock表示の反映
        updateDockVisibility()

        // メニューバーのアイコン＆メニューを作成
        setupMenuBar()

        // キー監視開始（Cmd押下を拾うため）
        startEventTap()
    }


    // =========================
    // Dock表示の切り替え
    // =========================
    /// Dockに表示するかどうかをOSに伝える
    func updateDockVisibility() {
        if showInDock {
            // 普通のアプリ扱い（Dockに表示される）
            NSApp.setActivationPolicy(.regular)
        } else {
            // メニューバー常駐アプリ扱い（Dockに出ない）
            NSApp.setActivationPolicy(.accessory)
        }
    }


    // =========================
    // メニューバーの作成
    // =========================
    /// メニューバーにアイコンを作り、メニューを割り当てる
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuIcon") // AssetsにMenuIconを追加しておく
            button.image?.isTemplate = true           // ダーク/ライトで自動反転してくれて見やすい
            button.title = ""
        }

        updateMenu()
    }

    /// メニューを作り直す（設定を変えたら表示も更新したいので、毎回生成する方式）
    func updateMenu() {
        let menu = NSMenu()

        // 表示用のラベルを作る（左Cmdが日本語なら、右Cmdは英語）
        let leftLabel  = leftCmdIsJapanese ? "日本語" : "英語"
        let rightLabel = leftCmdIsJapanese ? "英語"   : "日本語"

        // 現在の割り当てを表示（クリックはできない情報表示）
        let i1 = NSMenuItem(title: "左 ⌘  →  \(leftLabel)", action: nil, keyEquivalent: "")
        i1.isEnabled = false
        menu.addItem(i1)

        let i2 = NSMenuItem(title: "右 ⌘  →  \(rightLabel)", action: nil, keyEquivalent: "")
        i2.isEnabled = false
        menu.addItem(i2)

        menu.addItem(.separator())

        // 左右割り当てを入れ替えるボタン
        let assignItem = NSMenuItem(title: "左右の割り当てを入れ替え",
                                    action: #selector(toggleAssignment),
                                    keyEquivalent: "")
        assignItem.target = self
        menu.addItem(assignItem)

        // Dock表示を切り替えるボタン
        let dockItem = NSMenuItem(
            title: showInDock ? "✓ Dockに表示中（クリックで非表示）" : "　 Dockに表示する",
            action: #selector(toggleDock),
            keyEquivalent: ""
        )
        dockItem.target = self
        menu.addItem(dockItem)

        menu.addItem(.separator())

        // A: ログイン時に起動（OSログインしたら自動でアプリを起動）
        let launchItem = NSMenuItem(title: "ログイン時に起動",
                                    action: #selector(toggleLaunchAtLogin),
                                    keyEquivalent: "")
        launchItem.target = self
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)

        // B: 診断（動かない時に状態を見れる）
        let diagItem = NSMenuItem(title: "診断：状態を見る",
                                  action: #selector(showDiagnostics),
                                  keyEquivalent: "")
        diagItem.target = self
        menu.addItem(diagItem)

        menu.addItem(.separator())

        // 終了（Cmd+Q相当）
        menu.addItem(NSMenuItem(title: "終了", action: #selector(quitApp), keyEquivalent: "q"))

        // 作ったmenuをステータスアイテムにセット
        statusItem?.menu = menu
    }


    // =========================
    // キー監視（Event Tap）開始
    // =========================
    func startEventTap() {
        // 監視したいイベント（キー押下/キー離し/修飾キー状態変化）
        let eventMask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue) |
        (1 << CGEventType.keyUp.rawValue)   |
        (1 << CGEventType.flagsChanged.rawValue)

        // Cの関数（callback）から self（AppDelegate）を参照するためのポインタ
        // passUnretained：retain（保持）しない。AppDelegateはアプリが生きてる間ほぼ死なないのでこれでOK。
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // Event Tap作成（ここが失敗すると、権限がない可能性が高い）
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,           // セッション全体のイベントを拾う
            place: .headInsertEventTap,        // イベント処理の先頭に割り込む
            options: .defaultTap,              // 普通のTap
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                // refconから self を取り出す
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                return me.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            // 失敗した場合：アクセシビリティ権限がない可能性が高い
            // 権限が付いたら再試行する（1秒ごとにチェック）
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.startEventTap()
                }
            }
            // 権限付与のプロンプトを出す（システム設定へ誘導）
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
            return
        }

        // 作れたTapを保持してRunLoopへ追加
        self.eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.eventTapSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)

        // Tapを有効化
        CGEvent.tapEnable(tap: tap, enable: true)
    }


    // =========================
    // イベントが来た時の処理（Cmd単押し判定）
    // =========================
    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {

        // macOSがTapを勝手に止めることがあるので、無効化されたら復帰
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // 押されたキーのコード（USキーボードの左Cmd=54、右Cmd=55）
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {

        case .flagsChanged:
            // 修飾キー（Cmd/Shift/Optionなど）の状態変化が来る

            let isCmd = event.flags.contains(.maskCommand)
            let isCmdKey = (keyCode == 54 || keyCode == 55)

            if isCmdKey && isCmd {
                // Cmdが押された瞬間
                if pressedCmdKeyCode == nil {
                    pressedCmdKeyCode = keyCode      // 左か右か覚える
                    otherKeyPressed = false          // まだ他のキーは押されてない
                }

            } else if isCmdKey && !isCmd {
                // Cmdが離された瞬間
                // その間に他キーが押されてないなら「Cmd単押し」と判定して切替する
                if let pressed = pressedCmdKeyCode, pressed == keyCode, !otherKeyPressed {
                    return sendInputSwitchKey(isLeftCmd: keyCode == 54)
                }
                // 状態リセット
                pressedCmdKeyCode = nil
                otherKeyPressed = false
            }

        case .keyDown:
            // 通常キーが押された
            // Cmdが押されてる状態で他キーが押されたら「ショートカット」と判定
            if event.flags.contains(.maskCommand) {
                otherKeyPressed = true
            }

        default:
            break
        }

        // イベントはそのままOSへ流す（通常の動作も維持）
        return Unmanaged.passUnretained(event)
    }


    // =========================
    // 入力切替（かな/英数）を送信
    // =========================
    func sendInputSwitchKey(isLeftCmd: Bool) -> Unmanaged<CGEvent>? {

        // 左Cmdが日本語に割り当てられている場合：
        //  左Cmd単押し → 日本語、右Cmd単押し → 英数
        // 逆の場合は反転
        let useJapanese: Bool
        if leftCmdIsJapanese {
            useJapanese = isLeftCmd
        } else {
            useJapanese = !isLeftCmd
        }

        // 日本語（かな）= 104 / 英数 = 102（環境によって差が出ることがある）
        let targetKeyCode: CGKeyCode = useJapanese ? 104 : 102

        // HIDレベルでキー入力イベントを作って投稿する
        let src = CGEventSource(stateID: .hidSystemState)

        if let down = CGEvent(keyboardEventSource: src, virtualKey: targetKeyCode, keyDown: true) {
            down.flags = [] // 修飾キーなしとして送る
            down.post(tap: .cgSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: targetKeyCode, keyDown: false) {
            up.flags = []
            up.post(tap: .cgSessionEventTap)
        }

        // 状態リセット
        pressedCmdKeyCode = nil
        otherKeyPressed = false

        // ここでイベントを返さない（＝Cmdの単押し自体はOSには流さない挙動になる）
        return nil
    }


    // =========================
    // メニューアクション群
    // =========================
    @objc func toggleAssignment() {
        leftCmdIsJapanese = !leftCmdIsJapanese
        updateMenu()
    }

    @objc func toggleDock() {
        showInDock = !showInDock
        updateMenu()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }


    // =========================
    // A: ログイン時に起動（macOS 13+）
    // =========================
    func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    sender.state = .off
                } else {
                    try SMAppService.mainApp.register()
                    sender.state = .on
                }
            } catch {
                showAlert(title: "設定に失敗", message: error.localizedDescription)
                sender.state = isLaunchAtLoginEnabled() ? .on : .off
            }
        } else {
            showAlert(title: "未対応", message: "ログイン時起動は macOS 13 以上で利用できます。")
            sender.state = .off
        }
    }


    // =========================
    // B: 診断（動かない時の切り分け用）
    // =========================
    @objc func showDiagnostics() {
        let a11y = AXIsProcessTrusted()
        let tapStatus = (eventTap != nil) ? "OK" : "未設定"
        let msg = """
        Accessibility権限: \(a11y ? "OK" : "未許可")
        EventTap: \(tapStatus)
        Dock表示: \(showInDock ? "ON" : "OFF")
        ログイン時起動: \(isLaunchAtLoginEnabled() ? "ON" : "OFF")
        """
        showAlert(title: "診断", message: msg)
    }

    /// ちょっとした通知・エラー表示用（簡易アラート）
    func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

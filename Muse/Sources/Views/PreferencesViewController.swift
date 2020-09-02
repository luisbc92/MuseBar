//
//  PreferencesViewController.swift
//  Muse Bar
//
//  Created by Matan Mashraki on 02/09/2020.
//  Copyright © 2020 Matan Mashraki. All rights reserved.
//

import AppKit
import Sparkle
import LoginServiceKit

class PreferencesViewController: NSViewController {
    
    @IBOutlet weak var versionLabel: NSButton!
    @IBOutlet weak var launchAtLogin: NSButton!
    @IBOutlet weak var autoUpdates: NSButton!
    
    override func viewDidLoad() {
        launchAtLogin.setState(state: LoginServiceKit.isExistLoginItems())
        autoUpdates.setState(state: SUUpdater.shared()?.automaticallyChecksForUpdates ?? false)
        versionLabel.title = versionString
    }
    
    @IBAction func launchAtLoginCheck(_ sender: Any) {
        if LoginServiceKit.isExistLoginItems() {
            LoginServiceKit.removeLoginItems()
        } else {
            LoginServiceKit.addLoginItems()
        }
        launchAtLogin.setState(state: LoginServiceKit.isExistLoginItems())
    }
    
    @IBAction func autoUpdatesCheck(_ sender: Any) {
        guard let updater = SUUpdater.shared() else { return }
        let newValue = !updater.automaticallyChecksForUpdates
        updater.automaticallyChecksForUpdates = newValue
        autoUpdates.setState(state: newValue)
    }
    
    @IBAction func openGitHubClicked(_ sender: Any) {
        let url = URL(string: "https://github.com/planecore/MuseBar")!
        NSWorkspace.shared.open(url)
    }
    
    var versionString: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return "Muse Bar"
        }
        return "Version \(version) (\(build))"
    }
    
}

extension NSButton {
    func setState(state: Bool) {
        if state {
            self.state = .on
        } else {
            self.state = .off
        }
    }
    
    func state() -> Bool {
        return self.state == .on
    }
}

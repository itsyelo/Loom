//
//  AppDelegate.swift
//  LoomExample
//
//  Created by Bill on 2026/3/28.
//

import UIKit
import Loom

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Configure Loom on the main thread at launch. The first calculate()
        // in this app happens on a background thread (the feed pipeline), so
        // don't rely on the off-main fallbacks for screen scale.
        Loom.configure(screenScale: UIScreen.main.scale)

        // Measure with UILabel's own layout engine — any attributed string
        // agrees natively. No locked-line-height discipline anywhere in
        // this app: the residual collapse/expand toggle jitter at 13–14pt
        // (~1–2pt) was judged acceptable — see MultilineUILabelTips.
        Loom.defaultTextMeasurer = TextKitMeasurer.shared

        // Debug overlays are toggled at runtime from the "Custom View" tab.
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}


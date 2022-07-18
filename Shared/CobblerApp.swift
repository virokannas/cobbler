//
//  CobblerApp.swift
//  Shared
//
//  Created by Simo Virokannas on 7/16/22.
//

import SwiftUI

@main
struct CobblerApp: App {
    var body: some Scene {
        WindowGroup {
            MainView().frame(minWidth: 300, maxWidth: 400, minHeight: 100, maxHeight: 200)
        }
    }
}

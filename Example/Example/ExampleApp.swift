//
//  ExampleApp.swift
//  Example
//
//  Created by Takuto Nakamura on 2026/06/25.
//

import SwiftUI
import MinTermKit

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}

struct ContentView: View {
    @State private var session = TerminalSession(cols: 80, rows: 24)

    var body: some View {
        TerminalView(session: session, padding: 8)
            .navigationTitle(session.title.isEmpty ? "MinTermKit" : session.title)
            .onAppear {
                session.startLocalProcess(executable: "/bin/zsh")
            }
    }
}

//
//  ContentView.swift
//  TeamStats
//
//  Created by Narayan Lekhi on 10/8/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ContentUnavailableView {
                    Label("No games yet", systemImage: "basketball")
                } description: {
                    Text("No games have been added. Game entry is not available yet.")
                }
                .navigationTitle("Games")
            }
            .tabItem {
                Label("Games", systemImage: "basketball")
            }

            NavigationStack {
                ContentUnavailableView {
                    Label("No players yet", systemImage: "person.3")
                } description: {
                    Text("TODO_TEAM_ROSTER: The team roster has not been provided. Player entry is not available yet.")
                }
                .navigationTitle("Players")
            }
            .tabItem {
                Label("Players", systemImage: "person.3")
            }
        }
    }
}

#Preview {
    ContentView()
}

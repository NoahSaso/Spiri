//
//  SpiriApp.swift
//  Spiri
//
//  Created by Noah Saso on 11/21/21.
//

import SwiftUI
import SpiriKit
import Intents

@main
struct SpiriApp: App {
    let spotify = SpiriKitSpotify()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(spotify)
                .onOpenURL(perform: { url in spotify.requestTokens(url: url) })
                .onAppear(perform: {
                    let intent = AddSongToPlaylistIntent()
                    intent.playlist = Playlist(identifier: nil, display: "Example Playlist")
                    intent.suggestedInvocationPhrase = "Add Current Song To Playlist"
                    let interaction = INInteraction(intent: intent, response: nil)
                    interaction.donate { err in print(err) }
                })
        }
    }
}

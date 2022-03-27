//
//  SpiriApp.swift
//  Spiri
//
//  Created by Noah Saso on 11/21/21.
//

import Intents
import SpiriKit
import SwiftUI

@main
struct SpiriApp: App {
    let spotify = SpiriKitSpotify()

    var body: some Scene {
        WindowGroup {
            // Load initial client ID value from the keychain.
            ContentView(
                clientId: self.spotify.loadClientId() ?? "",
                aliases: self.spotify.loadAliases()
            )
            .environmentObject(spotify)
            .onOpenURL(perform: { url in spotify.requestTokens(url: url) })
            .onAppear(perform: {
                let intent = AddSongToPlaylistIntent()
                intent.playlist = Playlist(identifier: nil, display: "Example Playlist")
                intent.suggestedInvocationPhrase = "Add Current Song To Playlist"
                let interaction = INInteraction(intent: intent, response: nil)
                interaction.donate { err in print(err == nil ? "donated" : err?.localizedDescription ?? "donation error") }
                    
                INPreferences.requestSiriAuthorization { status in
                    print("siri auth:", status.rawValue)
                }
            })
        }
    }
}

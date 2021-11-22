//
//  ContentView.swift
//  Spiri
//
//  Created by Noah Saso on 11/21/21.
//

import SwiftUI
import SpiriKit

struct ContentView: View {
    @EnvironmentObject var spotify: SpiriKitSpotify

    var body: some View {
        if spotify.isAuthorized {
            Button("Deauthorize Spotify", action: spotify.deauthorize)
        } else {
            Button("Authorize Spotify", action: spotify.authorize)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

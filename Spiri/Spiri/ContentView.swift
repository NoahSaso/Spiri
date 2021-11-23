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

    @State var clientId: String = ""
    @State private var clientIdInvalidShowing = false
    
    func authorize() {
        if self.clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clientIdInvalidShowing = true
            return
        }

        spotify.authorize()
    }

    var body: some View {
        TextField("Spotify App Client ID", text: $clientId)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .padding(24)
            .submitLabel(.go)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(lineWidth: 1.0)
                    .padding(EdgeInsets(top: 16, leading: 12, bottom: 16, trailing: 12))
            )
            .disabled(spotify.isAuthorized)
            .opacity(spotify.isAuthorized ? 0.4 : 1.0)
            .onChange(of: clientId) { spotify.saveClientId($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .onSubmit(authorize)
            .alert(isPresented: $clientIdInvalidShowing) {
                Alert(
                    title: Text("Invalid"),
                    message: Text("Client ID cannot be empty.")
                )
            }

        if spotify.isAuthorized {
            Button("Deauthorize Spotify", action: spotify.deauthorize)
        } else {
            Button("Authorize Spotify", action: authorize)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(clientId: "abc123")
            .environmentObject(SpiriKitSpotify_Previews())
    }
}

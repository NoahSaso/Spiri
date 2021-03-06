//
//  ContentView.swift
//  Spiri
//
//  Created by Noah Saso on 11/21/21.
//

import SpiriKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var spotify: SpiriKitSpotify

    @State var clientId = ""
    @State var aliases: [String: String]

    @State private var clientIdInvalidShowing = false
    @State private var newAliasesShowing = false

    @State private var editingAlias = ""
    @State private var newAlias = ""
    
    func authorize() {
        if self.clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.clientIdInvalidShowing = true
            return
        }

        self.spotify.authorize()
    }
    
    /**
     Save alias to the keychain.
     */
    func setAlias(alias: String, playlistId: String) {
        self.aliases[alias] = playlistId
        _ = self.spotify.saveAliases(self.aliases)
    }
    
    /**
     Delete alias from the keychain.
     */
    func deleteAliases(_ aliasesToDelete: [String]) {
        aliasesToDelete.forEach { self.aliases.removeValue(forKey: $0) }
        _ = self.spotify.saveAliases(self.aliases)
    }
    
    /**
     Update alias on the keychain.
     */
    func updateAlias(alias: String, newAlias: String, newPlaylistId: String) {
        self.aliases.removeValue(forKey: alias)
        self.aliases[newAlias] = newPlaylistId
        _ = self.spotify.saveAliases(self.aliases)
    }

    var body: some View {
        VStack {
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
                    .foregroundColor(.red)
            } else {
                Button("Authorize Spotify", action: authorize)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0))
        
        VStack {
            Toggle("Add duplicates", isOn: $spotify.addDuplicates)
            Text("Add songs to playlists even if they already exist in that playlist.")
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
        }
        
        Button(
            self.newAliasesShowing ? "Hide playlists" : "Create new alias",
            action: { self.newAliasesShowing = !self.newAliasesShowing }
        ).padding(EdgeInsets(top: 24, leading: 0, bottom: 0, trailing: 0))
        
        if self.newAliasesShowing {
            List {
                ForEach(spotify.playlists, id: \.id) { newAliasPlaylist in
                    Button(
                        newAliasPlaylist.name,
                        action: { setAlias(alias: newAliasPlaylist.name, playlistId: newAliasPlaylist.id) }
                    )
                }
            }
        }
        
        let sortedAliases = self.aliases.sorted(by: >)
        
        List {
            ForEach(sortedAliases, id: \.key) { alias, playlistId in
                HStack(alignment: .center, spacing: 10) {
                    TextField(
                        "Alias",
                        text: Binding<String>(
                            get: { self.editingAlias == alias ? newAlias : alias },
                            set: { self.newAlias = $0 }
                        ),
                        onEditingChanged: { editing in
                            if editing {
                                self.editingAlias = alias
                                self.newAlias = alias
                            } else {
                                updateAlias(alias: alias, newAlias: self.newAlias, newPlaylistId: playlistId)
                                self.editingAlias = ""
                                self.newAlias = ""
                            }
                        }
                    )
                    .submitLabel(.done)
                    
                    if spotify.playlists.isEmpty {
                        Text("Loading...").foregroundColor(.gray)
                    } else if let playlist = spotify.playlists.first { $0.id == playlistId } {
                        Text(playlist.name)
                    } else {
                        Text("Unknown").foregroundColor(.red)
                    }
                }
            }
            .onDelete { deleteAliases($0.map { sortedAliases[$0].key }) }
        }
        .navigationBarTitle("Aliases")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(clientId: "abc123", aliases: [String: String]())
            .environmentObject(SpiriKitSpotify_Previews())
    }
}

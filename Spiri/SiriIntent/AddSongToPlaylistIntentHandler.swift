//
//  AddSongToPlaylistIntentHandler.swift
//  SiriIntent
//
//  Created by Noah Saso on 11/21/21.
//

import Foundation
import Intents
import SpiriKit
import Combine
import Fuse
import SpotifyWebAPI

class AddSongToPlaylistIntentHandler: NSObject, AddSongToPlaylistIntentHandling {
    private var cancellables: Set<AnyCancellable> = []

    private let spotify = SpiriKitSpotify()
    private let fuse = Fuse(threshold: 0.4)
    
    /**
     Try to find a Playlist from the API matching the given name in the list of playlists from the API and the alias dictionary and create a parameter value for the Playlist.
     */
    func getPlaylistForName(_ name: String, playlists: [SpotifyWebAPI.Playlist<PlaylistItemsReference>], aliases: [String:String]) -> Playlist? {
        var p = playlists.first { $0.name == name }
        if p == nil {
            let id = aliases.first { $0.key == name }?.value
            if id != nil {
                p = playlists.first { $0.id == id }
            }
        }

        if p == nil {
            return nil
        }

        let playlist = Playlist(identifier: p!.id, display: p!.name)
        playlist.uri = p!.uri

        return playlist
    }

    func handle(intent: AddSongToPlaylistIntent, completion: @escaping (AddSongToPlaylistIntentResponse) -> Void) {
        print("handle time")

        guard
            spotify.isAuthorized,
            let api = spotify.api,
            let playlist = intent.playlist,
            playlist.identifier != nil,
            let playlistUri = playlist.uri
        else {
            print("unauthorized or playlist fields empty")
            return completion(AddSongToPlaylistIntentResponse(code: .failureAuth, userActivity: nil))
        }
        
        api.currentPlayback()
            .sink(receiveCompletion: { value in
                switch value {
                case .finished: print("current playback completed")
                case .failure(let error):
                    print("current playback failure: \(error)")
                    completion(AddSongToPlaylistIntentResponse.failure(failureMessage: error.localizedDescription))
                }
            }, receiveValue: { context in
                print("got playback")

                guard
                    let item = context?.item,
                    let itemId = item.id,
                    let itemUri = item.uri
                else {
                    return completion(AddSongToPlaylistIntentResponse(code: .failureSong, userActivity: nil))
                }
                
                func add() {
                    print("adding song")
                    self.spotify
                        .addToPlaylist(
                            itemUri: itemUri,
                            playlistUri: playlistUri,
                            success: { completion(AddSongToPlaylistIntentResponse.success(song: item.name, playlist: playlist.displayString)) },
                            failure: { completion(AddSongToPlaylistIntentResponse.failure(failureMessage: $0.localizedDescription)) }
                        )
                }
                
                // check if duplicate exists
                if !self.spotify.addDuplicates {
                    let playlistUriContainer = SpiriKitURIContainer(uri: playlistUri)
                    
                    api
                        .playlistItems(playlistUriContainer)
                        .extendPagesConcurrently(api)
                        .collectAndSortByOffset()
                        .sink(receiveCompletion: { value in
                            switch value {
                            case .finished: print("playlist items completed")
                            case .failure(let error):
                                print("playlist items failure: \(error)")
                                completion(AddSongToPlaylistIntentResponse.failure(failureMessage: error.localizedDescription))
                            }
                        }, receiveValue: { result in
                            // if any item in playlist matches the ID we're trying to add, give duplicate error
                            if result.contains(where: { $0.item?.id == itemId }) {
                                return completion(AddSongToPlaylistIntentResponse.duplicate(song: item.name, playlist: playlist.displayString))
                            }

                            add()
                        })
                        .store(in: &self.cancellables)
                } else {
                    add()
                }
            })
            .store(in: &cancellables)
    }
    
    func resolvePlaylist(for intent: AddSongToPlaylistIntent, with completion: @escaping (PlaylistResolutionResult) -> Void) {
        print("resolving playlist")

        if !spotify.isAuthorized {
            print("spotify unauthorized")
            return completion(PlaylistResolutionResult.success(with: Playlist(identifier: nil, display: "Unauthorized")))
        }
        
        guard let playlistSearch = intent.playlist else {
            return completion(PlaylistResolutionResult.needsValue())
        }
        
        spotify.fetchPlaylists(
            success: { playlists in
                let aliases = self.spotify.loadAliases()

                // include aliases in matchable items
                let allNames = playlists.map { $0.name } + aliases.map { $0.key }

                let searchResults = self.fuse.search(playlistSearch.spokenPhrase, in: allNames)

                if searchResults.isEmpty {
                    return completion(PlaylistResolutionResult.needsValue())
                }

                // if found great result, use it
                if let winner = searchResults.first(where: { $0.score < 0.1 }) {
                    let name = allNames[winner.index]
                    let p = self.getPlaylistForName(name, playlists: playlists, aliases: aliases)

                    guard let playlist = p else {
                        return completion(PlaylistResolutionResult.needsValue())
                    }

                    return completion(PlaylistResolutionResult.success(with: playlist))
                }
                
                let playlistResults = searchResults
                    .map { self.getPlaylistForName(allNames[$0.index], playlists: playlists, aliases: aliases) }
                    .filter { $0 != nil }.map { $0! }
                completion(PlaylistResolutionResult.disambiguation(with: playlistResults))
            },
            failure: { error in
                print("current playlists failure: \(error)")
                completion(PlaylistResolutionResult.needsValue())
            }
        )
    }

    func providePlaylistOptionsCollection(for intent: AddSongToPlaylistIntent, searchTerm: String?, with completion: @escaping (INObjectCollection<Playlist>?, Error?) -> Void) {
        print("providing playlist options")
        
        if !spotify.isAuthorized {
            print("spotify unauthorized")
            return completion(nil, nil)
        }
        
        spotify.fetchPlaylists(
            success: { playlists in
                let aliases = self.spotify.loadAliases()

                var playlistResults: [Playlist] = []
                if let playlistSearch = searchTerm {
                    // include aliases in matchable items
                    let allNames = playlists.map { $0.name } + aliases.map { $0.key }

                    let searchResults = self.fuse.search(playlistSearch, in: allNames)
                    if !searchResults.isEmpty {
                        playlistResults = searchResults
                            .map { self.getPlaylistForName(allNames[$0.index], playlists: playlists, aliases: aliases) }
                            .filter { $0 != nil }.map { $0! }
                    }
                } else {
                    playlistResults =
                        playlists.map {
                            let p = Playlist(identifier: $0.id, display: $0.name)
                            p.uri = $0.uri
                            return p
                        } +
                        // add aliases to items
                        aliases.map { alias -> Playlist? in
                            guard let playlist = playlists.first(where: { p in p.id == alias.value }) else {
                                return nil
                            }
                            let p = Playlist(identifier: alias.value, display: alias.key)
                            p.uri = playlist.uri
                            return p
                        }.filter { $0 != nil }.map { $0! }
                }
                
                completion(INObjectCollection(items: playlistResults.sorted { $0.displayString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() < $1.displayString.trimmingCharacters(in: .whitespacesAndNewlines)      .lowercased() }), nil)
            }, failure: { error in
                print("provide current playlists failure: \(error)")
                completion(nil, error)
            })
    }
}

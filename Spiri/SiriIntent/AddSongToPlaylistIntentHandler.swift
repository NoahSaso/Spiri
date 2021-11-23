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

class URIContainer: SpotifyURIConvertible {
    let uri: String
    init(uri: String) {
        self.uri = uri
    }
}

class AddSongToPlaylistIntentHandler: NSObject, AddSongToPlaylistIntentHandling {
    private var cancellables: Set<AnyCancellable> = []

    private let spotify = SpiriKitSpotify()
    private let fuse = Fuse(threshold: 0.4)

    func handle(intent: AddSongToPlaylistIntent, completion: @escaping (AddSongToPlaylistIntentResponse) -> Void) {
        print("handle time")

        if !spotify.isAuthorized || intent.playlist?.identifier == nil || intent.playlist?.uri == nil {
            print("unauthorized or playlist fields empty")
            return completion(AddSongToPlaylistIntentResponse(code: .failureAuth, userActivity: nil))
        }
        
        spotify.api
            .currentPlayback()
            .sink(receiveCompletion: { value in
                switch value {
                case .finished: print("current playback completed")
                case .failure(let error):
                    print("current playback failure: \(error)")
                    completion(AddSongToPlaylistIntentResponse.failure(failureMessage: error.localizedDescription))
                }
            }, receiveValue: { context in
                print("got playback")

                guard let item = context?.item else {
                    return completion(AddSongToPlaylistIntentResponse(code: .failureSong, userActivity: nil))
                }
                
                print("adding song")

                // add song to playlist
                self.spotify.api
                    .addToPlaylist(URIContainer(uri: intent.playlist!.uri!), uris: [URIContainer(uri: item.uri!)])
                    .sink(receiveCompletion: { value in
                        switch value {
                        case .finished: print("add to playlist completed")
                        case .failure(let error):
                            print("add to playlist failure: \(error)")
                            completion(AddSongToPlaylistIntentResponse.failure(failureMessage: error.localizedDescription))
                        }
                    }, receiveValue: { snapshotId in
                        print("added! playlist: \(intent.playlist!.identifier!), snapshot id: \(snapshotId)")
                        completion(AddSongToPlaylistIntentResponse.success(song: item.name, playlist: intent.playlist!.displayString))
                    })
                    .store(in: &self.cancellables)
            })
            .store(in: &cancellables)
    }
    
    func resolvePlaylist(for intent: AddSongToPlaylistIntent, with completion: @escaping (PlaylistResolutionResult) -> Void) {
        print("resolving playlist")

        if !spotify.isAuthorized {
            return completion(PlaylistResolutionResult.success(with: Playlist(identifier: nil, display: "Unauthorized")))
        }

        if let playlistSearch = intent.playlist {
            spotify.api
                .currentUserPlaylists(limit: 50)
                .extendPagesConcurrently(spotify.api)
                .collectAndSortByOffset()
                .sink(receiveCompletion: { value in
                    switch value {
                    case .finished: print("current playlists completed")
                    case .failure(let error):
                        print("current playlists failure: \(error)")
                        completion(PlaylistResolutionResult.needsValue())
                    }
                }, receiveValue: { playlists in
                    print("received \(playlists.count) playlists")

                    let searchResults = self.fuse.search(playlistSearch.spokenPhrase, in: playlists.map { $0.name })
                    
                    if searchResults.isEmpty {
                        return completion(PlaylistResolutionResult.needsValue())
                    }

                    // if found great result, confirm and then use it
                    if let winner = searchResults.first(where: { $0.score < 0.1 }) {
                        let p = playlists[winner.index]
                        let playlist = Playlist(identifier: p.id, display: p.name)
                        playlist.uri = p.uri
                        return completion(PlaylistResolutionResult.success(with: playlist))
                    }
                    
                    let playlistResults = searchResults.map { playlists[$0.index] }.map { playlist -> Playlist in
                        let p = Playlist(identifier: playlist.id, display: playlist.name)
                        p.uri = playlist.uri
                        return p
                    }
                    return completion(PlaylistResolutionResult.disambiguation(with: playlistResults))
                })
                .store(in: &cancellables)
        } else {
            completion(PlaylistResolutionResult.needsValue())
        }
    }

    func providePlaylistOptionsCollection(for intent: AddSongToPlaylistIntent, searchTerm: String?, with completion: @escaping (INObjectCollection<Playlist>?, Error?) -> Void) {
        print("providing playlist options")

        if !spotify.isAuthorized {
            print("spotify unauthorized")
            return completion(nil, nil)
        }

        spotify.api
            .currentUserPlaylists(limit: 50)
            .extendPagesConcurrently(spotify.api)
            .collectAndSortByOffset()
            .sink(receiveCompletion: { value in
                switch value {
                case .finished: print("provide current playlists completed")
                case .failure(let error):
                    print("provide current playlists failure: \(error)")
                    completion(nil, error)
                }
            }, receiveValue: { playlists in
                print("received \(playlists.count) playlists")

                var playlistResults: [Playlist] = []
                if let playlistSearch = searchTerm {
                    let searchResults = self.fuse.search(playlistSearch, in: playlists.map { $0.name })
                    if !searchResults.isEmpty {
                        playlistResults.append(contentsOf: searchResults.map { playlists[$0.index] }.map {
                            let p = Playlist(identifier: $0.id, display: $0.name)
                            p.uri = $0.uri
                            return p
                        })
                    }
                } else {
                    playlistResults = playlists.map {
                        let p = Playlist(identifier: $0.id, display: $0.name)
                        p.uri = $0.uri
                        return p
                    }
                }
                
                completion(INObjectCollection(items: playlistResults.sorted { $0.displayString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() < $1.displayString.trimmingCharacters(in: .whitespacesAndNewlines)      .lowercased() }), nil)
            })
            .store(in: &cancellables)
    }
}

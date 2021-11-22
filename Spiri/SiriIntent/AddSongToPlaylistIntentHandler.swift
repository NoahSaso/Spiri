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

    func handle(intent: AddSongToPlaylistIntent, completion: @escaping (AddSongToPlaylistIntentResponse) -> Void) {
        if !spotify.isAuthorized || intent.playlist?.identifier == nil {
            return completion(AddSongToPlaylistIntentResponse(code: .failureAuth, userActivity: nil))
        }
        
        spotify.api
            .currentPlayback()
            .sink(receiveCompletion: { _ in }, receiveValue: { context in
                guard let item = context?.item else {
                    return completion(AddSongToPlaylistIntentResponse.failure(song: "nothing", playlist: intent.playlist!.displayString))
                }

                // add song to playlist
                self.spotify.api
                    .addToPlaylist(intent.playlist as! SpotifyURIConvertible, uris: [item as! SpotifyURIConvertible])
                    .sink(receiveCompletion: { _ in }, receiveValue: { snapshotId in
                        print("added! playlist: \(intent.playlist!.identifier!), snapshot id: \(snapshotId)")
                        completion(AddSongToPlaylistIntentResponse.success(song: item.name, playlist: intent.playlist!.displayString))
                    })
                    .store(in: &self.cancellables)
            })
            .store(in: &cancellables)
    }
    
    func resolvePlaylist(for intent: AddSongToPlaylistIntent, with completion: @escaping (PlaylistResolutionResult) -> Void) {
        if !spotify.isAuthorized {
            return completion(PlaylistResolutionResult.success(with: Playlist(identifier: nil, display: "Unauthorized")))
        }

        if let playlistSearch = intent.playlist {
            spotify.api
                .currentUserPlaylists(limit: 50)
                .extendPagesConcurrently(spotify.api)
                .collectAndSortByOffset()
                .sink(receiveCompletion: { _ in }, receiveValue: { playlists in
                    print("received \(playlists.count) playlists")

                    let searchResults = self.fuse.search(playlistSearch.spokenPhrase, in: playlists.map { $0.name })
                    
                    if searchResults.isEmpty {
                        return completion(PlaylistResolutionResult.needsValue())
                    }

                    // if found great result, confirm and then use it
                    if let winner = searchResults.first(where: { $0.score < 0.1 }) {
                        let p = playlists[winner.index]
                        return completion(PlaylistResolutionResult.success(with: Playlist(identifier: p.id, display: p.name)))
                    }
                    
                    let playlistResults = searchResults.map { playlists[$0.index] }.map { Playlist(identifier: $0.id, display: $0.name) }
                    return completion(PlaylistResolutionResult.disambiguation(with: playlistResults))
                })
                .store(in: &cancellables)
        } else {
            completion(PlaylistResolutionResult.needsValue())
        }
    }
}

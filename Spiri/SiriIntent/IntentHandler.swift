//
//  IntentHandler.swift
//  SiriIntent
//
//  Created by Noah Saso on 11/21/21.
//

import Intents

class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any {
        print("handling")
        guard intent is AddSongToPlaylistIntent else {
            fatalError("Unhandled intent type: \(intent)")
        }

        return AddSongToPlaylistIntentHandler()
    }
}

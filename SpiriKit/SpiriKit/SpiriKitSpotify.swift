//
//  SpiriKitSpotify.swift
//  SpiriKitSpotify
//
//  Created by Noah Saso on 11/21/21.
//

import Foundation
import Combine
import UIKit
import KeychainAccess
import SpotifyWebAPI

// https://github.com/Peter-Schorn/SpotifyAPI/wiki/Saving-authorization-information-to-persistent-storage.
/**
 A helper class that wraps around an instance of `SpotifyAPI` and provides
 convenience methods for authorizing your application.
 
 Its most important role is to handle changes to the authorization information
 and save them to persistent storage in the keychain.
 */
public class SpiriKitSpotify: ObservableObject {
    private static let clientId = "4c29315b680c4ac381b72ffeb169e87f"
    
    /// The key in the keychain that is used to store the authorization
    /// information: "authorizationManager".
    static let authorizationManagerKey = "authorizationManager"
    
    /// The URL that Spotify will redirect to after the user either authorizes
    /// or denies authorization for your application.
    static let loginCallbackURL = URL(
        string: "spiri://authorized"
    )!
    
    /// The scopes that this API client needs access to.
    static let scopes: Set<Scope> = [
        .playlistReadPrivate,
        .playlistModifyPublic,
        .playlistModifyPrivate,
        .playlistReadCollaborative,
        .userReadPlaybackState,
        .userReadCurrentlyPlaying,
    ]
    
    /// A cryptographically-secure random string used to ensure than an incoming
    /// redirect from Spotify was the result of a request made by this app, and
    /// not an attacker. **This value should be regenerated after each**
    /// **authorization process completes.**
    private let authorizationState = String.randomURLSafe(length: 128)
    
    private let codeVerifier = String.randomURLSafe(length: 128)
    private let codeChallenge: String
    
    /**
     Whether or not the application has been authorized. If `true`, then you can
     begin making requests to the Spotify web API using the `api` property of
     this class, which contains an instance of `SpotifyAPI`.
     
     This property provides a convenient way for the user interface to be
     updated based on whether the user has logged in with their Spotify account
     yet. For example, you could use this property disable UI elements that
     require the user to be logged in.
     
     This property is updated by `authorizationManagerDidChange()`, which is
     called every time the authorization information changes, and
     `authorizationManagerDidDeauthorize()`, which is called every time
     `SpotifyAPI.authorizationManager.deauthorize()` is called.
     */
    @Published public private(set) var isAuthorized = false
    
    /// The keychain to store the authorization information in.
    private let keychain = Keychain(service: "com.noahsaso.spiri")
    
    /// An instance of `SpotifyAPI` that you use to make requests to the Spotify
    /// web API.
    public let api: SpotifyAPI<AuthorizationCodeFlowPKCEManager>
    
    private var cancellables: [AnyCancellable] = []
    
    public init() {
        self.codeChallenge = String.makeCodeChallenge(codeVerifier: self.codeVerifier)
        self.api = SpotifyAPI(
            authorizationManager: AuthorizationCodeFlowPKCEManager(
                clientId: Self.clientId
            )
        )

        // MARK: Important: Subscribe to `authorizationManagerDidChange` BEFORE
        // MARK: retrieving `authorizationManager` from persistent storage
        self.api.authorizationManagerDidChange
        // We must receive on the main thread because we are updating the
        // @Published `isAuthorized` property.
            .receive(on: RunLoop.main)
            .sink(receiveValue: authorizationManagerDidChange)
            .store(in: &cancellables)
        
        self.api.authorizationManagerDidDeauthorize
            .receive(on: RunLoop.main)
            .sink(receiveValue: authorizationManagerDidDeauthorize)
            .store(in: &cancellables)
        
        // Check to see if the authorization information is saved in the
        // keychain.
        if let authManagerData = keychain[data: Self.authorizationManagerKey] {
            do {
                // Try to decode the data.
                let authorizationManager = try JSONDecoder().decode(
                    AuthorizationCodeFlowPKCEManager.self,
                    from: authManagerData
                )
                
                /*
                 This assignment causes `authorizationManagerDidChange` to emit
                 a signal, meaning that `authorizationManagerDidChange()` will
                 be called.
                 
                 Note that if you had subscribed to
                 `authorizationManagerDidChange` after this line, then
                 `authorizationManagerDidChange()` would not have been called
                 and the @Published `isAuthorized` property would not have been
                 properly updated.
                 
                 We do not need to update `self.isAuthorized` here because that
                 is already handled in `authorizationManagerDidChange()`.
                 */
                self.api.authorizationManager = authorizationManager
                
                // update anyways so it is set immediately
                self.isAuthorized = self.api.authorizationManager.isAuthorized(for: Self.scopes)
                
                print("found authorization manager in keychain")
            } catch {
                print("could not decode authorizationManager from data:\n\(error)")
            }
        }
        else {
            print("did not find authorization manager in keychain")
        }
    }
    
    /**
     A convenience method that creates the authorization URL and opens it in the
     browser.
     
     You could also configure it to accept parameters for the authorization
     scopes
     */
    public func authorize() {
        let authorizationURL = api.authorizationManager.makeAuthorizationURL(
            redirectURI: Self.loginCallbackURL,
            codeChallenge: self.codeChallenge,
            // This same value **MUST** be provided for the state parameter of
            // `authorizationManager.requestAccessAndRefreshTokens(redirectURIWithQuery:state:)`.
            // Otherwise, an error will be thrown.
            state: self.authorizationState,
            scopes: Self.scopes
        )!
        
        // You can open the URL however you like. For example, you could open it
        // in a web view instead of the browser.
        // See https://developer.apple.com/documentation/webkit/wkwebview
        UIApplication.shared.open(authorizationURL)
    }
    
    public func deauthorize() {
        self.api.authorizationManager.deauthorize()
        print("deauthorized")
    }
    
    public func requestTokens(url: URL) {
        self.api.authorizationManager.requestAccessAndRefreshTokens(
            redirectURIWithQuery: url,
            // Must match the code verifier that was used to generate the
            // code challenge when creating the authorization URL.
            codeVerifier: self.codeVerifier,
            // Must match the value used when creating the authorization URL.
            state: self.authorizationState
        )
        .sink(receiveCompletion: { completion in
            switch completion {
                case .finished:
                    print("successfully authorized")
                case .failure(let error):
                    if let authError = error as? SpotifyAuthorizationError, authError.accessWasDenied {
                        print("The user denied the authorization request")
                    }
                    else {
                        print("couldn't authorize application: \(error)")
                    }
            }
        })
        .store(in: &cancellables)
    }
    
    /**
     Saves changes to `api.authorizationManager` to the keychain.
     
     This method is called every time the authorization information changes. For
     example, when the access token gets automatically refreshed, (it expires
     after an hour) this method will be called.
     
     It will also be called after the access and refresh tokens are retrieved
     using `requestAccessAndRefreshTokens(redirectURIWithQuery:state:)`.
     */
    private func authorizationManagerDidChange() {
        // Update the @Published `isAuthorized` property.
        self.isAuthorized = self.api.authorizationManager.isAuthorized(for: Self.scopes)
        
        do {
            // Encode the authorization information to data.
            let authManagerData = try JSONEncoder().encode(self.api.authorizationManager)
            
            // Save the data to the keychain.
            self.keychain[data: Self.authorizationManagerKey] = authManagerData

            print("saved authorization manager to keychain. is authorized:", self.isAuthorized)
        } catch {
            print(
                "couldn't encode authorizationManager for storage in the " +
                "keychain:\n\(error)"
            )
        }
    }
    
    /**
     Removes `api.authorizationManager` from the keychain.
     
     This method is called every time `api.authorizationManager.deauthorize` is
     called.
     */
    private func authorizationManagerDidDeauthorize() {
        self.isAuthorized = false
        
        do {
            /*
             Remove the authorization information from the keychain.
             
             If you don't do this, then the authorization information that you
             just removed from memory by calling `deauthorize()` will be
             retrieved again from persistent storage after this app is quit and
             relaunched.
             */
            try self.keychain.remove(Self.authorizationManagerKey)

            print("removed authorization manager from keychain")
        } catch {
            print(
                "couldn't remove authorization manager from keychain: \(error)"
            )
        }
    }
    
}


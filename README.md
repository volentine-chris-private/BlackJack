# BlackJack  (MVVM · SwiftUI · SwiftData)
An iOS local blackjack app with up to four additional players, configurable house rules, a true-count calculator, and a user profile that tracks balance history as well as a 30-day chart giving a visual representation of total gains/losses.

## Requirements
- Xcode 26.0 or newer
- iOS 26.6+, iPhone deployment target

## Project Highlights
The project implements the `Model-View-ViewModel` architecture, along with Network and Service layers. Some of the services include:
- A `BlackJack Game Engine` that owns the logic throughout each step of a BlackJack round's lifecycle
- A `Ledger` service, responsible for data persistence related to user funds gained/lost, hands won/lost, etc.
- A `True Count Calculator` that can be utilized in-app for betting assistance
- An `NPC Brain` with different betting strategies utilized by NPCs
- `DeckOfCardsService` retrieves new shuffled decks via the [Deck of Cards](https://deckofcardsapi.com/) API, along with a fallback on-device shuffle if there are any network failures
- `NameGenerationService` that uses [this API](https://randomuser.me/documentation) to retrieve random names for NPCs (and similarly has a local fallback)

## Ideas for future work on this project:
- Implementation of a secure user login system
- Building out Unit and UI Test cases
- Reworking some aspects of the game logic
  - E.g., if early surrender is enabled, the user should be given that option for any hand (as opposed to how it currently works - the option is only presented if the dealer has to check their hole card for a BlackJack)
- Integrate player images for User and NPCs
- Add more comments throughout the codebase as deemed necessary
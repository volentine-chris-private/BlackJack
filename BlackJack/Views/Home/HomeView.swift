//
//  HomeView.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI

@MainActor
struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    let services: AppServices

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: geo.size.height * 0.16)

                    header

                    VStack(spacing: 14) {
                        Button {
                            viewModel.playTapped()
                        } label: {
                            Label("Play", systemImage: "suit.spade.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("homePlayButton")

                        Button {
                            viewModel.isShowingSettings = true
                        } label: {
                            Label("Settings", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("homeSettingsButton")
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 44)

                    Spacer()

                    suitsFooter
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.isShowingProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.peach)
                    }
                    .accessibilityLabel("Profile")
                    .accessibilityHint("View your funds and 30-day history")
                    .accessibilityIdentifier("homeProfileButton")
                    .disabled(viewModel.profile == nil)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $viewModel.isShowingSettings) {
                SettingsView(services: services)
            }
        }
        .fullScreenCover(isPresented: $viewModel.isShowingBuyIn, onDismiss: { viewModel.buyInSheetDismissed() }) {
            BuyInSheet(
                title: "Take a Seat",
                subtitle: "How much of your funds do you want to bring to the table?",
                confirmTitle: "Sit Down",
                availableFunds: viewModel.availableFunds,
                services: services
            ) { amount in
                viewModel.confirmBuyIn(amount)
            }
        }
        .sheet(isPresented: $viewModel.isShowingProfile, onDismiss: { viewModel.profileSheetDismissed() }) {
            if let profile = viewModel.profile {
                ProfileView(services: services, profile: profile) {
                    viewModel.requestDataReset()
                }
            }
        }
        .fullScreenCover(item: $viewModel.activeSession, onDismiss: { viewModel.reload() }) { session in
            BlackjackTableView(services: services, config: session) {
                viewModel.sessionEnded()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(viewModel.welcomeText)
                .accessibilityIdentifier("homeWelcomeText")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.beige)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 24)

            if viewModel.profile != nil {
                HStack(spacing: 6) {
                    Image(systemName: "banknote.fill")
                    Text(viewModel.fundsText)
                }
                .font(.headline)
                .foregroundStyle(AppTheme.peach)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(AppTheme.teal.opacity(0.35)))
            }
        }
    }

    private var suitsFooter: some View {
        HStack(spacing: 18) {
            ForEach(Suit.allCases, id: \.self) { suit in
                Text(suit.symbol)
                    .font(.title2)
                    .foregroundStyle(suit.isRed ? AppTheme.copper.opacity(0.5) : AppTheme.beige.opacity(0.25))
            }
        }
        .accessibilityHidden(true)
    }
}

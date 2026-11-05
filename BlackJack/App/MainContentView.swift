//
//  MainContentView.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI
import SwiftData

@MainActor
struct MainContentView: View {
    let services: AppServices
    @State private var homeViewModel: HomeViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(services: AppServices) {
        self.services = services
        _homeViewModel = State(initialValue: HomeViewModel(services: services))
    }

    var body: some View {
        HomeView(viewModel: homeViewModel, services: services)
            .sheet(isPresented: onboardingBinding) {
                OnboardingView(services: services) {
                    homeViewModel.reload()
                }
                .interactiveDismissDisabled()
            }
            .errorPresentation(services.errorCenter)
            .task {
                homeViewModel.performLaunchChecks()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    services.persistAll(reason: "scene phase changed")
                }
            }
    }

    /// Onboarding stays up until a profile exists; it can't be swiped away.
    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { homeViewModel.needsOnboarding },
            set: { _ in }
        )
    }
}

import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            TodayRootView()
                .tabItem {
                    Label("Сегодня", systemImage: "calendar")
                }

            PrescriptionsRootView()
                .tabItem {
                    Label("Назначения", systemImage: "doc.text")
                }

                /*
                 NavigationStack {
                MedicationsListView()
            }
            .tabItem {
                Label("Лекарства", systemImage: "pills")
            }
                 */

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gear")
                }
        }
        .preferredColorScheme({
            switch appState.colorScheme {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }())
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}

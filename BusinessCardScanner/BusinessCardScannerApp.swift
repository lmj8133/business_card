import SwiftUI
import SwiftData

@main
struct BusinessCardScannerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([BusinessCard.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

struct ContentView: View {
    @StateObject private var parser = BusinessCardParser()

    var body: some View {
        TabView {
            CardListView()
                .tabItem {
                    Label("Cards", systemImage: "rectangle.stack")
                }

            ScanView()
                .tabItem {
                    Label("Scan", systemImage: "camera")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .environmentObject(parser)
    }
}

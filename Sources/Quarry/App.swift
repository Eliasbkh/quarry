import SwiftUI

/// Grasgrün aus dem App-Icon, dunkel genug für weiße Schrift auf Knöpfen (Kontrast > 5:1).
let brand = Color(red: 0.21, green: 0.48, blue: 0.32)

@main struct QuarryApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup("Quarry") {
            ContentView()
                .environment(store)
                .frame(minWidth: 980, minHeight: 640)
                .tint(brand)
                .task { await store.checkForUpdates(manual: false) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    store.refreshSystemState()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") { Task { await store.checkForUpdates(manual: true) } }
            }
        }
    }
}

enum Route: Hashable { case home, discover(Kind), instance(String) }

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var route: Route? = .home
    @State private var showNew = false

    var body: some View {
        NavigationSplitView {
            List(selection: $route) {
                Label("Übersicht", systemImage: "house").tag(Route.home)
                Section("Entdecken") {
                    ForEach(Kind.allCases) { Label($0.title, systemImage: $0.symbol).tag(Route.discover($0)) }
                }
                Section("Meine Instanzen") {
                    ForEach(store.instances) { i in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(i.name).lineLimit(1)
                                Text("Minecraft \(i.gameVersion) · \(i.mods.count) Mods").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "cube.fill") }
                        .tag(Route.instance(i.id))
                    }
                    Button { showNew = true } label: { Label("Neue Instanz …", systemImage: "plus") }
                        .buttonStyle(.borderless)
                        .disabled(store.status != nil)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            switch route {
            case .home, nil: HomeView(showNew: $showNew, route: $route)
            case .discover(let kind): DiscoverView(kind: kind).id(kind)
            case .instance(let id):
                if let i = store.instances.first(where: { $0.id == id }) {
                    InstanceView(instance: i, route: $route).id(id)
                } else {
                    ContentUnavailableView("Instanz nicht gefunden", systemImage: "questionmark.folder")
                }
            }
        }
        .sheet(isPresented: $showNew) { NewInstanceSheet { route = .instance($0) } }
        .overlay(alignment: .bottom) {
            if let s = store.status {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(s).monospacedDigit() }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: .capsule)
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: store.status == nil)
        .alert(item: Binding(get: { store.update }, set: { store.update = $0 })) { r in
            Alert(
                title: Text("Quarry \(r.version) ist verfügbar"),
                message: Text("Du hast \(Updater.current). Quarry startet nach dem Update neu.\n\n\(r.body ?? "")"),
                primaryButton: .default(Text("Jetzt aktualisieren")) {
                    store.run("Update wird geladen …") { try await Updater.install(r) }
                },
                secondaryButton: .cancel(Text("Später"))
            )
        }
        .alert("Hinweis", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } })) {
            Button("OK") {}
        } message: { Text(store.alert ?? "") }
    }
}

/// Kleines Info-Etikett, z. B. „Minecraft 26.3“.
struct Chip: View {
    let text: String
    var symbol: String?
    var body: some View {
        Label { Text(text) } icon: { if let symbol { Image(systemName: symbol) } }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.quaternary.opacity(0.7), in: .capsule)
    }
}

/// Runde Projekt-Grafik von Modrinth mit Ersatzsymbol.
struct ProjectIcon: View {
    let url: String?
    let symbol: String
    var size: CGFloat = 44
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { $0.resizable().scaledToFit() } placeholder: {
            Image(systemName: symbol).font(.system(size: size * 0.42)).foregroundStyle(.tertiary)
        }
        .frame(width: size, height: size)
        .background(.quaternary.opacity(0.5))
        .clipShape(.rect(cornerRadius: size * 0.23))
        .accessibilityHidden(true)
    }
}

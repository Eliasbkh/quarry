import SwiftUI

/// Suche auf Modrinth für eine Inhaltsart; oben steht, was diese Art tut und für welche Instanz gefiltert wird.
struct DiscoverView: View {
    let kind: Kind
    @Environment(Store.self) private var store
    @State private var query = ""
    @State private var hits: [Hit] = []
    @State private var target: String?
    @State private var loading = true
    @State private var loadError: String?
    @State private var attempt = 0

    private var targetInstance: Instance? { store.instances.first { $0.id == target } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if let loadError {
                    ContentUnavailableView {
                        Label("Modrinth nicht erreichbar", systemImage: "wifi.exclamationmark")
                    } description: { Text(loadError) } actions: {
                        Button("Erneut versuchen") { self.loadError = nil; attempt += 1 }
                    }
                } else if hits.isEmpty && !loading {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(hits) { HitRow(hit: $0, kind: kind, target: targetInstance) }
                        .overlay { if loading && hits.isEmpty { ProgressView("Lade \(kind.title) …") } }
                }
            }
            .frame(minHeight: 120, maxHeight: .infinity)
        }
        .navigationTitle(kind.title)
        .searchable(text: $query, prompt: "\(kind.title) auf Modrinth suchen")
        .onAppear { if target == nil, kind != .modpack { target = store.instances.first?.id } }
        .task(id: "\(query)|\(target ?? "")|\(attempt)") {
            try? await Task.sleep(for: .milliseconds(250)) // Tipp-Pause abwarten
            if Task.isCancelled { return }
            loading = true
            defer { loading = false }
            do {
                hits = try await Modrinth.search(query, kind: kind, gameVersion: targetInstance?.gameVersion)
                loadError = nil
            } catch {
                if !Task.isCancelled { loadError = error.localizedDescription }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: kind.symbol).font(.title2).foregroundStyle(brand).frame(width: 30)
                .accessibilityHidden(true)
            Text(kind.explanation).font(.callout).foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 16)
            if kind != .modpack {
                Picker("Passend für", selection: $target) {
                    Text("Alle Versionen").tag(String?.none)
                    if !store.instances.isEmpty { Divider() }
                    ForEach(store.instances) { Text("\($0.name) – \($0.gameVersion)").tag(Optional($0.id)) }
                }
                .fixedSize()
                .help("Zeigt nur Inhalte, die mit dieser Instanz funktionieren")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.background.secondary)
    }
}

private let loaderTags: Set = ["fabric", "forge", "neoforge", "quilt", "iris", "optifine", "minecraft", "vanilla", "canvas", "babric"]

struct HitRow: View {
    let hit: Hit
    let kind: Kind
    let target: Instance?
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            ProjectIcon(url: hit.iconUrl, symbol: kind.symbol, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(hit.title).font(.headline).lineLimit(1)
                    Text("von \(hit.author)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(hit.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    Label(hit.downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(hit.categories.filter { !loaderTags.contains($0) }.prefix(3), id: \.self) {
                        Chip(text: $0.replacingOccurrences(of: "-", with: " ").capitalized)
                    }
                    Link(destination: URL(string: "https://modrinth.com/\(kind.rawValue)/\(hit.slug)")!) {
                        Label("Details", systemImage: "arrow.up.right").font(.caption)
                    }
                    .help("Auf Modrinth ansehen")
                }
            }
            Spacer(minLength: 12)
            installButton.disabled(store.status != nil)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var installButton: some View {
        if kind == .modpack {
            Button("Als Instanz installieren") { store.run("Modpack wird geladen …") { try await store.installModpack(hit) } }
        } else if let target {
            if target.has(hit.projectId) {
                Label("Installiert", systemImage: "checkmark").foregroundStyle(brand).font(.callout.weight(.medium))
            } else {
                Button("Hinzufügen") { install(into: target) }.help("Zu „\(target.name)“ hinzufügen")
            }
        } else {
            Menu("Hinzufügen zu …") {
                ForEach(store.instances) { i in
                    Button("\(i.name) (\(i.gameVersion))") { install(into: i) }.disabled(i.has(hit.projectId))
                }
                if store.instances.isEmpty { Text("Lege zuerst eine Instanz an") }
            }
            .fixedSize()
        }
    }

    private func install(into i: Instance) {
        store.run("\(hit.title) wird installiert …") {
            var i = i
            try await store.installProject(hit.projectId, kind: kind, into: &i)
        }
    }
}

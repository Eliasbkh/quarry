import SwiftUI

@main struct QuarryApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup("Quarry") {
            ContentView().environment(store).frame(minWidth: 900, minHeight: 560)
                .task { await store.checkForUpdates(manual: false) }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") { Task { await store.checkForUpdates(manual: true) } }
            }
        }
    }
}

enum Route: Hashable { case mods, packs, instance(String) }

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var route: Route? = .mods
    @State private var showNew = false

    var body: some View {
        NavigationSplitView {
            List(selection: $route) {
                Section("Entdecken") {
                    Label("Mods", systemImage: "puzzlepiece.extension").tag(Route.mods)
                    Label("Modpacks", systemImage: "shippingbox").tag(Route.packs)
                }
                Section("Bibliothek") {
                    ForEach(store.instances) { i in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(i.name).lineLimit(1)
                                Text("\(i.gameVersion) · Fabric").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "cube") }
                        .tag(Route.instance(i.id))
                    }
                    if store.instances.isEmpty {
                        Button("Erste Instanz anlegen …") { showNew = true }.buttonStyle(.link)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .safeAreaInset(edge: .bottom) {
                if !store.launcherInstalled {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Minecraft Launcher fehlt", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.bold()).symbolRenderingMode(.multicolor)
                        Text("Wird zum Spielen gebraucht. Quarry lädt ihn direkt von Mojang.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Jetzt installieren") {
                            store.run("Minecraft Launcher wird installiert …") { try await store.installLauncher() }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(store.status != nil)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
                    .padding(10)
                }
            }
            .toolbar {
                Button("Neue Instanz", systemImage: "plus") { showNew = true }.disabled(store.status != nil)
            }
        } detail: {
            switch route {
            case .mods, nil: DiscoverView(type: "mod").id("mod")
            case .packs: DiscoverView(type: "modpack").id("modpack")
            case .instance(let id):
                if let i = store.instances.first(where: { $0.id == id }) {
                    InstanceView(instance: i)
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

// MARK: Entdecken

struct DiscoverView: View {
    let type: String
    @Environment(Store.self) private var store
    @State private var query = ""
    @State private var hits: [Hit] = []
    @State private var target: String?
    @State private var loading = true
    @State private var loadError: String?

    private var targetInstance: Instance? { store.instances.first { $0.id == target } }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView("Modrinth nicht erreichbar", systemImage: "wifi.exclamationmark", description: Text(loadError))
            } else if hits.isEmpty && !loading {
                ContentUnavailableView.search(text: query)
            } else {
                List(hits) { HitRow(hit: $0, type: type, target: targetInstance) }
                    .overlay { if loading && hits.isEmpty { ProgressView() } }
            }
        }
        .navigationTitle(type == "mod" ? "Mods" : "Modpacks")
        .navigationSubtitle(type == "mod" ? "Fabric-Mods von Modrinth" : "Nur Fabric-Modpacks")
        .searchable(text: $query, prompt: "Auf Modrinth suchen")
        .toolbar {
            if type == "mod" {
                Picker("Für Instanz", selection: $target) {
                    Text("Alle Versionen").tag(String?.none)
                    ForEach(store.instances) { Text("\($0.name) (\($0.gameVersion))").tag(Optional($0.id)) }
                }
            }
        }
        .task(id: "\(query)|\(target ?? "")") {
            try? await Task.sleep(for: .milliseconds(250)) // Tipp-Pause abwarten
            if Task.isCancelled { return }
            loading = true
            defer { loading = false }
            do {
                hits = try await Modrinth.search(query, type: type, gameVersion: targetInstance?.gameVersion)
                loadError = nil
            } catch {
                if !Task.isCancelled { loadError = error.localizedDescription }
            }
        }
    }
}

struct HitRow: View {
    let hit: Hit
    let type: String
    let target: Instance?
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: hit.iconUrl.flatMap(URL.init(string:))) { $0.resizable().scaledToFit() } placeholder: {
                Image(systemName: "cube").font(.title2).foregroundStyle(.tertiary)
            }
            .frame(width: 48, height: 48)
            .background(.quaternary.opacity(0.5))
            .clipShape(.rect(cornerRadius: 11))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(hit.title).font(.headline).lineLimit(1)
                    Text("von \(hit.author)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(hit.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Label(hit.downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            installButton.disabled(store.status != nil)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var installButton: some View {
        if type == "modpack" {
            Button("Installieren") { store.run("Modpack wird geladen …") { try await store.installModpack(hit) } }
        } else if let target {
            let installed = target.mods[hit.projectId] != nil
            Button(installed ? "Installiert" : "Installieren") { install(into: target) }.disabled(installed)
        } else {
            Menu("Installieren") {
                ForEach(store.instances) { i in
                    Button("\(i.name) (\(i.gameVersion))") { install(into: i) }.disabled(i.mods[hit.projectId] != nil)
                }
                if store.instances.isEmpty { Text("Lege zuerst eine Instanz an") }
            }
            .fixedSize()
        }
    }

    private func install(into i: Instance) {
        store.run("\(hit.title) wird installiert …") {
            var i = i
            try await store.installMod(hit.projectId, into: &i)
        }
    }
}

// MARK: Neue Instanz

struct NewInstanceSheet: View {
    var onCreate: (String) -> Void
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var version = ""

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text(version.isEmpty ? "Meine Welt" : "Minecraft \(version)"))
                Picker("Minecraft-Version", selection: $version) {
                    if store.gameVersions.isEmpty { Text("Lädt …").tag("") }
                    ForEach(store.gameVersions, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Mod-Loader", value: "Fabric (neueste stabile)")
            }
            Section {
                ForEach(macPerformancePack, id: \.slug) { mod in
                    LabeledContent { Text(mod.why).foregroundStyle(.secondary).multilineTextAlignment(.trailing) } label: {
                        Label(mod.name, systemImage: "bolt.fill")
                    }
                }
            } header: {
                Text("macOS-Leistungspaket – wird automatisch installiert")
            } footer: {
                Text("Dazu: Java-RAM passend zu deinem Mac (\(Paths.javaArgs().split(separator: " ")[1].dropFirst(4))) mit G1GC-Flags und FPS-freundliche Startwerte in options.txt.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 460)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Erstellen") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    let v = version
                    dismiss()
                    store.run("Instanz wird angelegt …") {
                        onCreate(try await store.createWithPack(name: n.isEmpty ? "Minecraft \(v)" : n, gameVersion: v))
                    }
                }
                .disabled(version.isEmpty)
            }
        }
        .task {
            await store.loadGameVersions()
            if version.isEmpty { version = store.gameVersions.first ?? "" }
        }
    }
}

// MARK: Instanz

struct InstanceView: View {
    let instance: Instance
    @Environment(Store.self) private var store
    @State private var confirmDelete = false

    var body: some View {
        let files = store.modFiles(instance)
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "cube.fill").font(.system(size: 30)).foregroundStyle(.tint)
                        .frame(width: 64, height: 64)
                        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instance.name).font(.title2.bold()).lineLimit(1)
                        Text("Minecraft \(instance.gameVersion) · Fabric \(instance.loaderVersion)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.play() } label: { Label("Spielen", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .help("Öffnet den Minecraft Launcher – dort das Profil „\(instance.name)“ wählen")
                }
                .padding(.vertical, 6)
            }
            Section("Mods (\(files.count))") {
                if files.isEmpty {
                    Text("Keine Mods. Such welche unter „Mods“.").foregroundStyle(.secondary)
                }
                ForEach(files, id: \.self) { f in
                    HStack {
                        Image(systemName: "puzzlepiece.extension").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(f).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("\(f) entfernen", systemImage: "trash", role: .destructive) { store.removeMod(f, from: instance) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                            .disabled(store.status != nil)
                    }
                }
            }
        }
        .navigationTitle(instance.name)
        .toolbar {
            Button("Mods aktualisieren", systemImage: "arrow.triangle.2.circlepath") {
                store.run("Suche Mod-Updates …") { try await store.updateMods(instance) }
            }
            .disabled(store.status != nil)
            Button("Leistungspaket erneut anwenden", systemImage: "bolt") {
                store.run("Leistungspaket …") { var i = instance; await store.applyPerformancePack(&i) }
            }
            .disabled(store.status != nil)
            Button("Im Finder zeigen", systemImage: "folder") { NSWorkspace.shared.open(store.dir(instance)) }
            Button("Instanz löschen", systemImage: "trash") { confirmDelete = true }.disabled(store.status != nil)
        }
        .confirmationDialog("„\(instance.name)“ löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) { store.deleteInstance(instance) }
        } message: {
            Text("Welten, Mods und Einstellungen dieser Instanz werden endgültig gelöscht.")
        }
    }
}

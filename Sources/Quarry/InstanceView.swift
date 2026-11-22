import SwiftUI

// MARK: Instanz

struct InstanceView: View {
    let instance: Instance
    @Binding var route: Route?
    @Environment(Store.self) private var store
    @State private var tab: Kind = .mod
    @State private var confirmDelete = false

    private let tabs: [Kind] = [.mod, .resourcepack, .shader]

    var body: some View {
        let files = store.files(instance, tab)
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 12) {
                Picker("Inhalt", selection: $tab) {
                    ForEach(tabs) { k in Text("\(k.title) (\(store.files(instance, k).count))").tag(k) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                Button { route = .discover(tab) } label: { Label("\(tab.title) hinzufügen", systemImage: "plus") }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)

            if files.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine \(tab.title)", systemImage: tab.symbol)
                } description: {
                    Text(tab.explanation)
                } actions: {
                    Button("\(tab.title) entdecken") { route = .discover(tab) }.buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(files, id: \.self) { f in
                            FileRow(file: f, kind: tab, instance: instance, project: instance.projectId(for: f, tab).flatMap { store.projectCache[$0] })
                        }
                    } footer: {
                        Text(footer).font(.callout).foregroundStyle(.secondary)
                    }
                }
                // Ohne Mindesthöhe meldet die Liste ihre volle Höhe und schiebt das ganze Fenster nach oben.
                .frame(minHeight: 120, maxHeight: .infinity)
            }
        }
        .navigationTitle(instance.name)
        .task(id: instance.mods.count + (instance.extras?.count ?? 0)) {
            let ids = (Array(instance.mods.keys) + Array((instance.extras ?? [:]).keys)).filter { store.projectCache[$0] == nil }
            if let list = try? await Modrinth.projects(ids) {
                for p in list { store.projectCache[p.id] = p }
            }
        }
        .confirmationDialog("„\(instance.name)“ löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) { route = .home; store.deleteInstance(instance) }
        } message: {
            Text("Welten, Mods und Einstellungen dieser Instanz werden endgültig gelöscht.")
        }
    }

    private var footer: String {
        switch tab {
        case .mod: "Ausgeschaltete Mods bleiben installiert, laden aber nicht. Gilt ab dem nächsten Start."
        case .resourcepack: "Installierte Pakete aktivierst du im Spiel unter Optionen → Ressourcenpakete."
        case .shader: "Im Spiel aktivieren: Optionen → Grafik → Shader-Pakete. Profil „Medium“ gibt gute FPS."
        case .modpack: ""
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "cube.fill").font(.system(size: 30)).foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(brand.gradient, in: .rect(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(instance.name).font(.title.bold()).lineLimit(1)
                HStack(spacing: 6) {
                    Chip(text: "Minecraft \(instance.gameVersion)")
                    Chip(text: "Fabric \(instance.loaderVersion)")
                    Chip(text: "Leistungspaket aktiv", symbol: "bolt.fill")
                }
                Text("„Spielen“ öffnet den Minecraft Launcher mit dieser Instanz – dort nur noch auf Play klicken.")
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 10) {
                Button { store.play(instance) } label: {
                    Label("Spielen", systemImage: "play.fill").frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent).controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
                HStack(spacing: 8) {
                    Button { store.run("Suche Mod-Updates …") { try await store.updateMods(instance) } } label: {
                        Label("Mods aktualisieren", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help("Lädt neuere Versionen aller Mods dieser Instanz von Modrinth")
                    Menu {
                        Button("Leistungspaket ergänzen", systemImage: "bolt") {
                            store.run("Leistungspaket …") { var i = instance; await store.applyPerformancePack(&i) }
                        }
                        Button("Im Finder zeigen", systemImage: "folder") { NSWorkspace.shared.open(store.dir(instance)) }
                        Divider()
                        Button("Instanz löschen …", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: { Label("Mehr", systemImage: "ellipsis.circle") }
                    .fixedSize()
                }
                .disabled(store.status != nil)
            }
        }
        .padding(20)
    }
}

private let performanceSlugs = Set(macPerformancePack.map(\.slug))

struct FileRow: View {
    let file: String
    let kind: Kind
    let instance: Instance
    let project: Project?
    @Environment(Store.self) private var store

    var body: some View {
        let enabled = !file.hasSuffix(".disabled")
        let name = project?.title ?? readableName
        HStack(spacing: 12) {
            ProjectIcon(url: project?.iconUrl, symbol: kind.symbol, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(.headline).lineLimit(1)
                    if let slug = project?.slug, performanceSlugs.contains(slug) {
                        Text("Leistungspaket").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(brand)
                            .background(brand.opacity(0.14), in: .capsule)
                    }
                    if !enabled { Text("Aus").font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
                }
                Text(project?.description ?? file).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            .opacity(enabled ? 1 : 0.55)
            Spacer(minLength: 12)
            if kind == .mod {
                Toggle("\(name) aktiv", isOn: Binding(get: { enabled }, set: { store.setEnabled(file, $0, in: instance) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    .help(enabled ? "Mod ausschalten (bleibt installiert)" : "Mod wieder einschalten")
            }
            Button(role: .destructive) { store.removeFile(file, kind: kind, from: instance) } label: {
                Label("\(name) entfernen", systemImage: "trash")
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless)
            .help("Entfernen")
        }
        .disabled(store.status != nil)
        .padding(.vertical, 3)
    }

    /// „sodium-fabric-0.9.3+mc26.3.jar“ → „sodium-fabric-0.9.3+mc26.3“ für Dateien ohne Modrinth-Zuordnung.
    private var readableName: String {
        file.replacingOccurrences(of: ".disabled", with: "").replacingOccurrences(of: ".jar", with: "").replacingOccurrences(of: ".zip", with: "")
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
            } header: {
                Text("Neue Instanz")
            } footer: {
                Text("Eine Instanz ist eine eigene Minecraft-Installation mit eigenen Mods, Welten und Einstellungen.")
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
                Text("Dazu: Java-RAM passend zu deinem Mac (\(Paths.javaArgs().split(separator: " ")[1].dropFirst(4))) mit G1GC-Flags und FPS-freundliche Startwerte.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 480)
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

import SwiftUI

/// Startseite: Einrichtung in drei Schritten, Instanzen mit „Spielen“ und eine kurze Erklärung.
struct HomeView: View {
    @Binding var showNew: Bool
    @Binding var route: Route?
    @Environment(Store.self) private var store

    private var setupDone: Bool { store.launcherInstalled && store.profilesReady && !store.instances.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(setupDone ? "Bereit zum Spielen" : "Willkommen bei Quarry").font(.largeTitle.bold())
                    Text("Quarry installiert Mods, Shader und Modpacks von Modrinth und macht Minecraft auf deinem Mac automatisch schneller.")
                        .font(.title3).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !setupDone { setup }
                instances
                howItWorks
            }
            .padding(36)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Übersicht")
    }

    // MARK: Einrichtung

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In drei Schritten startklar").font(.title2.bold())
            VStack(spacing: 0) {
                StepRow(number: 1, title: "Minecraft Launcher installieren",
                        detail: "Der offizielle Launcher von Mojang. Quarry startet Minecraft darüber – du lädst ihn hier mit einem Klick.",
                        done: store.launcherInstalled, current: !store.launcherInstalled, action: "Installieren") {
                    store.run("Minecraft Launcher wird installiert …") { try await store.installLauncher() }
                }
                Divider().padding(.leading, 60)
                StepRow(number: 2, title: "Im Launcher anmelden",
                        detail: "Einmal mit deinem Microsoft-Konto anmelden und den Launcher wieder schließen. Quarry merkt das automatisch.",
                        done: store.profilesReady, current: store.launcherInstalled && !store.profilesReady, action: "Launcher öffnen") {
                    store.play()
                }
                .disabled(!store.launcherInstalled)
                Divider().padding(.leading, 60)
                StepRow(number: 3, title: "Erste Instanz anlegen",
                        detail: "Eine Instanz ist eine eigene Minecraft-Installation mit eigenen Mods, Welten und Einstellungen. Das Leistungspaket kommt automatisch mit.",
                        done: !store.instances.isEmpty, current: store.profilesReady && store.instances.isEmpty, action: "Instanz anlegen") {
                    showNew = true
                }
                .disabled(!store.profilesReady)
            }
            .background(.background.secondary, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
        }
    }

    // MARK: Instanzen

    private var instances: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Deine Instanzen").font(.title2.bold())
                Spacer()
                Button { showNew = true } label: { Label("Neue Instanz", systemImage: "plus") }
                    .disabled(store.status != nil || !store.profilesReady)
            }
            if store.instances.isEmpty {
                Text("Noch keine Instanz. Sobald du eine angelegt hast, startest du sie hier mit einem Klick.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.instances) { i in
                        HStack(spacing: 14) {
                            Image(systemName: "cube.fill").font(.title2).foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(brand.gradient, in: .rect(cornerRadius: 10))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(i.name).font(.headline)
                                HStack(spacing: 6) {
                                    Chip(text: "Minecraft \(i.gameVersion)")
                                    Chip(text: "\(i.mods.count) Mods", symbol: "puzzlepiece.extension")
                                }
                            }
                            Spacer()
                            Button("Verwalten") { route = .instance(i.id) }
                            Button { store.play(i) } label: { Label("Spielen", systemImage: "play.fill") }
                                .buttonStyle(.borderedProminent)
                                .help("Öffnet den Minecraft Launcher mit „\(i.name)“")
                        }
                        .padding(14)
                        if i.id != store.instances.last?.id { Divider().padding(.leading, 72) }
                    }
                }
                .background(.background.secondary, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
            }
        }
    }

    // MARK: Erklärung

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("So funktioniert Quarry").font(.title2.bold())
            Explainer(symbol: "bolt.fill", title: "Automatisch schneller",
                      text: "Jede neue Instanz bekommt das macOS-Leistungspaket: "
                        + macPerformancePack.map(\.name).joined(separator: ", ")
                        + ". Dazu passender Arbeitsspeicher für Java und FPS-freundliche Startwerte.")
            Explainer(symbol: "play.fill", title: "Spielen über den offiziellen Launcher",
                      text: "Quarry trägt jede Instanz als Profil im Minecraft Launcher ein. „Spielen“ öffnet den Launcher mit dieser Instanz – dort nur noch auf Play klicken.")
            Explainer(symbol: "magnifyingglass", title: "Inhalte finden",
                      text: "Links unter „Entdecken“ suchst du Mods, Modpacks, Ressourcenpakete und Shader. Wähl oben die Instanz, dann siehst du nur passende Ergebnisse.")
            Explainer(symbol: "arrow.triangle.2.circlepath", title: "Immer aktuell",
                      text: "Quarry aktualisiert sich selbst. Mods aktualisierst du in einer Instanz mit „Mods aktualisieren“.")
        }
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    let current: Bool
    let action: String
    let perform: () -> Void
    @Environment(Store.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? AnyShapeStyle(brand) : AnyShapeStyle(.quaternary))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.callout.weight(.semibold)).foregroundStyle(current ? .primary : .secondary)
                }
            }
            .frame(width: 30, height: 30)
            .accessibilityLabel(done ? "Erledigt" : "Schritt \(number)")

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(done ? .secondary : .primary)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if done {
                Text("Erledigt").font(.callout).foregroundStyle(brand)
            } else if current {
                Button(action, action: perform).buttonStyle(.borderedProminent).disabled(store.status != nil)
            } else {
                Button(action, action: perform).disabled(store.status != nil)
            }
        }
        .padding(16)
    }
}

private struct Explainer: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(brand).frame(width: 22).padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

import SwiftUI
import AppKit

/// Estado de UI só do painel (engrenagem de Ajustes). `@State` não compila nesta
/// toolchain sem Xcode — espelha o padrão de `LoginItemUIState`.
@MainActor
@Observable
final class PanelUIState {
    static let shared = PanelUIState()
    var settingsExpanded = false
    var confirmingRemove = false
    private init() {}
}

extension Color {
    /// Acento único do painel, fixado em systemBlue. `Color.accentColor` segue o
    /// acento do macOS e com "Grafite" deixava o "+1 garrafa" e a barra cinzas.
    static let gotaAccent = Color(nsColor: .systemBlue)
}

struct PanelView: View {
    @Bindable var store = HydrationStore.shared
    @Bindable private var loginState = LoginItemUIState.shared
    @Bindable private var uiState = PanelUIState.shared
    @Bindable private var updater = UpdateChecker.shared

    private var goalMet: Bool { store.log.metGoalToday }

    private var progress: Double { store.log.progress }

    private var todayBottles: Int { store.log.todayBottles }

    private var litersLabel: String {
        let log = store.log
        let drankL = Double(log.todayML) / 1000.0
        let goalL = Double(log.goalML) / 1000.0
        return String(format: "%.1f L de %.1f L", drankL, goalL).replacingOccurrences(of: ".", with: ",")
    }

    private var streakLabel: String {
        let streak = store.log.streak
        return streak == 1 ? "1 dia" : "\(streak) dias"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            progressBar
            litersAndStreak
            actions
            Divider()
            if uiState.settingsExpanded {
                settings
                Divider()
            }
            if let release = updater.available {
                updateRow(release)
            }
            footer
        }
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .frame(width: 250)
        .tint(.gotaAccent)
        .onAppear {
            NotificationManager.shared.refreshStatus()
            updater.checkIfDue()
        }
        .onDisappear {
            uiState.settingsExpanded = false
            uiState.confirmingRemove = false
        }
    }

    // MARK: - [1] Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Gota").font(.headline).foregroundStyle(.primary)
            if NotificationManager.shared.authorizationDenied {
                Image(systemName: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Lembretes desativados")
            }
            Spacer()
            HStack(spacing: 5) {
                if goalMet {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.gotaAccent)
                }
                countText
            }
        }
    }

    private var countText: some View {
        (Text("\(todayBottles)").fontWeight(.semibold).foregroundStyle(.primary)
         + Text(" de \(store.settings.goalBottles) garrafas").foregroundStyle(.secondary))
            .font(.body)
    }

    // MARK: - [2] Barra de progresso

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.gotaAccent)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.2), value: todayBottles)
    }

    // MARK: - [3] Litros · Streak

    private var litersAndStreak: some View {
        HStack(spacing: 6) {
            Text(litersLabel).font(.caption).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 3) {
                ForEach(store.log.last7Days) { day in
                    streakDot(day)
                }
            }
            Text(streakLabel).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.log.streak) dias seguidos com meta batida")
        .animation(.easeOut(duration: 0.2), value: todayBottles)
    }

    @ViewBuilder
    private func streakDot(_ day: StreakDay) -> some View {
        if day.met {
            Circle().fill(Color.gotaAccent).frame(width: 5, height: 5)
        } else if day.isToday {
            Circle().strokeBorder(Color.gotaAccent, lineWidth: 1).frame(width: 5, height: 5)
        } else {
            Circle().fill(.quaternary).frame(width: 5, height: 5)
        }
    }

    // MARK: - [4] Ações

    @ViewBuilder
    private var actions: some View {
        if uiState.confirmingRemove {
            removeConfirmation
        } else {
            HStack {
                Group {
                    if goalMet {
                        Button("+1 garrafa") { withAnimation(.easeOut(duration: 0.2)) { store.add(1) } }
                            .buttonStyle(.bordered)
                    } else {
                        Button("+1 garrafa") { withAnimation(.easeOut(duration: 0.2)) { store.add(1) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.regular)
                Spacer()
                if todayBottles > 0 {
                    Button("−1") { uiState.confirmingRemove = true }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .controlSize(.regular)
                        .padding(.trailing, -6)
                }
            }
        }
    }

    private var removeConfirmation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Deseja realmente remover uma garrafa?")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancelar") { uiState.confirmingRemove = false }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Remover") {
                    withAnimation(.easeOut(duration: 0.2)) { store.add(-1) }
                    uiState.confirmingRemove = false
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.regular)
        }
    }

    // MARK: - [6] Ajustes (expandido)

    private var loginToggleBinding: Binding<Bool> {
        Binding(
            get: { loginState.enabled },
            set: { newValue in loginState.setEnabled(newValue) }
        )
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ajustes")
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            settingsRow("Garrafa", value: "\(store.settings.bottleML) ml") {
                Stepper("", value: store.binding(\.bottleML), in: 100...3000, step: 50)
                    .labelsHidden()
                    .controlSize(.small)
            }
            settingsRow("Meta", value: "\(store.settings.goalBottles) garrafas") {
                Stepper("", value: store.binding(\.goalBottles), in: 1...20)
                    .labelsHidden()
                    .controlSize(.small)
            }
            settingsRow("Intervalo", value: "\(store.settings.intervalMin) min") {
                Stepper("", value: store.binding(\.intervalMin), in: 15...240, step: 15)
                    .labelsHidden()
                    .controlSize(.small)
            }
            settingsRow("Início", value: String(format: "%02d:00", store.settings.startHour)) {
                Stepper("", value: store.binding(\.startHour), in: 0...23)
                    .labelsHidden()
                    .controlSize(.small)
            }
            settingsRow("Fim", value: String(format: "%02d:00", store.settings.endHour)) {
                Stepper("", value: store.binding(\.endHour), in: 0...23)
                    .labelsHidden()
                    .controlSize(.small)
            }

            Toggle("Abrir ao iniciar sessão", isOn: loginToggleBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .frame(height: 20)
            if loginState.needsApproval {
                Button("Aprovar nos Ajustes") {
                    LoginItemManager.openSettings()
                }
                .buttonStyle(.link)
            }
            if let error = loginState.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Toggle("Mostrar contagem na barra", isOn: store.binding(\.showCountInBar))
                .toggleStyle(.switch)
                .controlSize(.small)
                .frame(height: 20)

            Spacer().frame(height: 2)

            Button("Testar lembrete") {
                NotificationManager.shared.postReminder()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private func settingsRow<Content: View>(
        _ label: String, value: String, @ViewBuilder stepper: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.body).foregroundStyle(.primary)
            Spacer()
            Text(value).font(.body).foregroundStyle(.secondary)
            stepper()
        }
        .frame(height: 20)
    }

    // MARK: - Nova versão (só quando a release do GitHub é mais nova)

    private func updateRow(_ release: UpdateChecker.Release) -> some View {
        Button {
            NSWorkspace.shared.open(release.url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle").foregroundStyle(Color.gotaAccent)
                Text("Nova versão \(release.version) disponível").foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .buttonStyle(.borderless)
    }

    // MARK: - [6] Rodapé

    private var footer: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { uiState.settingsExpanded.toggle() }
            } label: {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(uiState.settingsExpanded ? .primary : .secondary)
                    .background(
                        uiState.settingsExpanded ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 5)
                    )
            }
            .buttonStyle(.borderless)
            .padding(.leading, -4)
            Spacer()
            Button("Sair") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
            .padding(.trailing, -6)
        }
    }
}

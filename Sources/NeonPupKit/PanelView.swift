import SwiftUI
import AppKit
import ServiceManagement
import NeonPupCore

public struct PanelView: View {
    @ObservedObject var model: AppModel
    @State private var startsAtLogin = SMAppService.mainApp.status == .enabled
    /// A double-click must not wake and then immediately nap (live drill 2026-10-09).
    @State private var lastTap = Date.distantPast
    let appVersion: String

    public init(model: AppModel, appVersion: String) {
        self.model = model
        self.appVersion = appVersion
    }

    public var body: some View {
        VStack(spacing: 14) {
            DogStage(mood: AppStateMachine.mood(model.phase))
            GlowButton(title: AppStateMachine.buttonTitle(model.phase, chinaMode: model.chinaMode), wakes: !model.isOn) {
                guard Date().timeIntervalSince(lastTap) > 1.0 else { return }
                lastTap = Date()
                Task {
                    if model.phase == .hotelLogin { await model.endHotelLogin() }
                    else if model.isOn { await model.nap() }
                    else { await model.wake() }
                }
            }
            StatusLine(text: AppStateMachine.status(model.phase, mode: model.mode))
            if model.chinaMode && model.phase == .off {
                StatusLine(text: "China mode is on: no internet until you wake me up")
            }
            if model.phase == .trouble(.needsApproval) {
                TextLink(title: "Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
            if model.phase == .trouble(.noRoads) {
                TextLink(title: "Add my servers") { RoadsWindow.show(model: model) }
            }
            if model.phase == .failed {
                // In China mode napping keeps everything blocked, so don't promise normal internet.
                TextLink(title: model.chinaMode ? "Stop trying for now" : "Back to normal internet") { Task { await model.nap() } }
            }
            if AppStateMachine.showsHotelLogin(model.phase, chinaMode: model.chinaMode) {
                TextLink(title: "Securely open public Wi-Fi login") { Task { await model.startHotelLogin() } }
            }
            ModeToggle(mode: model.mode) { newMode in
                Task {
                    await model.setMode(newMode)
                    if newMode == .manual { await model.refreshDelays() }
                }
            }
            if model.mode == .manual {
                VStack(spacing: 2) {
                    ForEach(model.roads, id: \.tag) { road in
                        RoadRow(road: road,
                                hearts: model.isOn ? Hearts.count(delayMs: model.delays[road.tag]) : nil,
                                selected: model.pickedRoad == road.tag) {
                            Task { await model.pick(road.tag); await model.refreshDelays() }
                        }
                    }
                }
            }
            FooterBar(startsAtLogin: startsAtLogin, chinaMode: model.chinaMode,
                      help: { GuideWindow.show(copyReport: { await model.helpReport(appVersion: appVersion) }) }, toggleLogin: toggleLogin,
                      toggleChinaMode: { Task { await model.setChinaMode(!model.chinaMode) } },
                      showGuide: { GuideWindow.show(copyReport: { await model.helpReport(appVersion: appVersion) }) }, showRoads: { RoadsWindow.show(model: model) }, quit: quit)
        }
        .padding(16)
        .frame(width: Theme.panelWidth)
        .background(Theme.night)
        .task { if model.mode == .manual { await model.refreshDelays() } }
    }

    private func toggleLogin() {
        if startsAtLogin { try? SMAppService.mainApp.unregister() } else { try? SMAppService.mainApp.register() }
        startsAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func quit() { NSApp.terminate(nil) }
}

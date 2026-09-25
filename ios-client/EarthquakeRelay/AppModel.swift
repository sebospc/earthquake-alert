import CoreLocation
import Observation
import RelayCore
import UIKit
import UserNotifications

/// Glue between iOS and RelayCore. Decisions live in RelayCore; this only feeds it and keeps state.
@Observable @MainActor
final class AppModel {
    private(set) var permission: Permission = .notDetermined
    private(set) var timeSensitiveOn = true
    private(set) var locationDenied = false
    private(set) var registration: Registration = .pending
    private(set) var coverage: [String: Bool]?
    private(set) var tier: CoverageTier = .limited
    private(set) var followed: [Sensor] = []
    private(set) var lastFix: Fix?
    private(set) var alert: EarthquakeAlert?
    private(set) var alertReceivedAt: Date?
    private(set) var testAlert = TestAlertTracker()
    private(set) var consented = Consent.isGiven()
    /// Consent withdrawn but the DELETE has not reached the server yet. The consent screen says so.
    private(set) var serverDeletePending = false

    var state: AppState {
        AppState.derive(permission: permission, timeSensitiveOn: timeSensitiveOn, locationDenied: locationDenied,
                        registration: registration, receptorCoverage: coverage, tier: { [tier] _ in tier },
                        alert: alert, now: .now)
    }

    private let gateway = GatewayClient(baseURL: AppModel.gatewayURL, apnsEnvironment: AppModel.apnsEnvironment)
    private let lifecycle: TokenLifecycle
    private let engine: SubscriptionEngine
    private let uploader = ArrivalUploader()
    private let location = LocationService()
    private var token: Data?
    private var syncTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var uploadTask: Task<Void, Never>?
    private var deleteTask: Task<Void, Never>?

    init() {
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        lifecycle = TokenLifecycle(registrar: gateway, deviceID: deviceID)
        engine = SubscriptionEngine(lifecycle: lifecycle)
        location.onFix = { [weak self] fix in
            self?.lastFix = fix
            self?.sync()
        }
        location.onDenied = { [weak self] denied in self?.locationDenied = denied }
    }

    // MARK: events

    func launched() {
        Task {
            // Last confirmed set, shown while this launch's POST is in flight. A failed POST turns it red.
            followed = await engine.followedSensors
            if !followed.isEmpty { registration = .receptors(followed.map(\.id)) }
            await refreshNotificationSettings()
        }
        location.start()
    }

    func becameActive() {
        if let log = AppGroup.pushArrivalsFile { testAlert.check(PushArrivalLog.read(from: log)) }
        Task { await refreshNotificationSettings() }
        location.requestFreshFix()
        startStatusPolling()
        sync()
        uploadArrivals()
        if !consented { retryServerDelete() }
    }

    func tokenArrived(_ newToken: Data) {
        if newToken != token { registration = .pending }
        token = newToken
        sync()
    }

    /// nil for pushes that are not alerts (coverage notices).
    func received(_ newAlert: EarthquakeAlert?) {
        guard let newAlert, newAlert.eventID != alert?.eventID else { return }
        if newAlert.isTest { testAlert.pushArrived() }
        alert = newAlert
        alertReceivedAt = .now
    }

    func dismissAlert() { alert = nil }

    /// "Probar alerta" in the Cobertura sheet.
    func sendTestAlert() {
        guard let token, testAlert.canSend(at: .now) else { return }
        testAlert.started()
        Task {
            do throws(GatewayClient.TestAlertFailure) {
                _ = try await gateway.sendTestAlert(deviceToken: token)
                testAlert.accepted(at: .now)
            } catch {
                testAlert.failed(error)
            }
        }
    }

    /// "Acepto" on the consent screen leads straight into the permission prompts.
    func acceptConsent() {
        // Registering again takes the token off the pending deletes, so the retry loop has nothing left.
        deleteTask?.cancel()
        deleteTask = nil
        serverDeletePending = false
        Consent.give()
        consented = true
        Task { await enableAlerts() }
    }

    /// "Retirar consentimiento" (Ley 1581): stop, forget locally, DELETE on the server. A failed
    /// DELETE still clears the phone, is retried with backoff, and the consent screen says so.
    func withdrawConsent() {
        Consent.withdraw()
        consented = false
        let inFlightSync = syncTask
        syncTask?.cancel()
        uploadTask?.cancel()
        registration = .pending
        followed = []
        lastFix = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [DeadManReminder.identifier])
        Task {
            // A POST still in flight could land after the DELETE and register the phone again.
            await inFlightSync?.value
            await engine.forget()
            serverDeletePending = !(await lifecycle.unregister())
            if serverDeletePending { retryServerDelete() }
        }
    }

    /// The one button on the main screen.
    func primaryAction() {
        switch state {
        case .notSetUp: Task { await enableAlerts() }
        default: UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        }
    }

    // MARK: work

    private func enableAlerts() async {
        permission = .requesting
        #if CRITICAL_ALERTS
        let options = NotificationPermission.options(criticalAlertsEntitled: true)
        #else
        let options = NotificationPermission.options(criticalAlertsEntitled: false)
        #endif
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: options)
        await refreshNotificationSettings()
        if permission == .granted { location.requestPermission() }
    }

    private func refreshNotificationSettings() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permission = NotificationPermission.permission(settings.authorizationStatus)
        timeSensitiveOn = settings.timeSensitiveSetting != .disabled
        // Every launch and wake: the token is never cached as the truth.
        if permission == .granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Choose receptors and POST. Newest call wins; retried with backoff until a 201 or a 4xx.
    private func sync() {
        guard consented, let token else { return }
        syncTask?.cancel()
        syncTask = Task {
            let background = UIApplication.shared.beginBackgroundTask()
            defer { UIApplication.shared.endBackgroundTask(background) }
            let sensors = try? await gateway.sensors()
            do {
                registration = try await retrying { () async throws(GatewayClient.Failure) in
                    try await engine.sync(token: token, fix: lastFix, sensors: sensors, coverage: coverage, now: .now)
                }
                if registration != .pending {
                    try? await UNUserNotificationCenter.current().add(DeadManReminder.request())
                    if case .receptors = registration { location.requestAlwaysOnce() }
                    uploadArrivals()
                }
            } catch {
                if !Task.isCancelled { registration = .pending }
            }
            followed = await engine.followedSensors
            await refreshTier()
        }
    }

    /// Test phones only (the 201 said `telemetry: true`). Low priority, own task, retried with
    /// backoff; nothing waits for it.
    private func uploadArrivals() {
        guard consented, uploadTask == nil, let token, let log = AppGroup.pushArrivalsFile else { return }
        uploadTask = Task(priority: .utility) {
            defer { uploadTask = nil }
            guard await lifecycle.telemetryEnabled else { return }
            let arrivals = PushArrivalLog.read(from: log)
            let result = try? await retrying { () async throws(GatewayClient.Failure) in
                try await uploader.upload(arrivals) { [gateway] batch async throws(GatewayClient.Failure) in
                    try await gateway.uploadArrivals(deviceToken: token, batch)
                }
            }
            if result == .telemetryOff { await lifecycle.telemetryTurnedOff() }
        }
    }

    private func retryServerDelete() {
        guard deleteTask == nil else { return }
        deleteTask = Task {
            defer { deleteTask = nil }
            // Known before the first retry, so a relaunch shows the notice while offline.
            serverDeletePending = await lifecycle.hasPendingDeletes
            try? await retrying { () async throws(GatewayClient.Failure) in
                await lifecycle.retryPendingDeletes()
                if await lifecycle.hasPendingDeletes { throw .retryLater }
            }
            serverDeletePending = await lifecycle.hasPendingDeletes
        }
    }

    private func startStatusPolling() {
        guard statusTask == nil else { return }
        statusTask = Task {
            for await latest in gateway.watchCoverage() {
                coverage = latest
                await refreshTier()
            }
        }
    }

    private func refreshTier() async {
        guard case .receptors(let ids) = registration else { return }
        tier = await engine.tier(ofUp: ids.filter { coverage?[$0] == true })
    }

    private static var gatewayURL: URL {
        #if DEBUG
        GatewayEndpoint.url(isDebugBuild: true, launchOverride: UserDefaults.standard.string(forKey: "gateway"))
        #else
        GatewayEndpoint.url(isDebugBuild: false, launchOverride: nil)
        #endif
    }

    private static var apnsEnvironment: GatewayClient.APNsEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}

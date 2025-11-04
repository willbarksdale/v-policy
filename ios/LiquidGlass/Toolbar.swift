import UIKit
import Flutter
import SwiftUI

// ============================================================================
// TOOLBAR COMPONENTS - iOS 26+ Liquid Glass
// ============================================================================
// Contains all floating toolbar buttons: Power, Info, Back, Play
// Plus the shared GlassEffectContainer utility
// ============================================================================

// ============================================================================
// MARK: - Shared Glass Effect Container
// ============================================================================

struct GlassEffectContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
    }
}

// ============================================================================
// MARK: - Power Button (SSH Screen - Bottom Right)
// ============================================================================

class PowerButtonState: ObservableObject {
    @Published var isConnected: Bool
    
    init(isConnected: Bool) {
        self.isConnected = isConnected
    }
}

struct AuthenticLiquidGlassPowerButton: View {
    @ObservedObject var state: PowerButtonState
    let onPowerTapped: () -> Void
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer {
            Button(action: onPowerTapped) {
                Image(systemName: "power")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(state.isConnected ? .blue : .primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())
            .glassEffectID("powerButton", in: namespace)
        }
    }
}

class SimpleLiquidGlassPowerButtonPlugin: NSObject, FlutterPlugin {
    private var buttonState: PowerButtonState?
    private var hostingController: UIHostingController<AnyView>?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_power_button", binaryMessenger: registrar.messenger())
        let instance = SimpleLiquidGlassPowerButtonPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            result(true)
        case "enableNativeLiquidGlassPowerButton":
            let args = call.arguments as? [String: Any]
            let isConnected = args?["isConnected"] as? Bool ?? false
            enableLiquidGlassForCurrentScreen(isConnected: isConnected, result: result)
        case "disableNativeLiquidGlassPowerButton":
            disableLiquidGlassForCurrentScreen(result: result)
        case "updatePowerButtonState":
            let args = call.arguments as? [String: Any]
            let isConnected = args?["isConnected"] as? Bool ?? false
            updatePowerButtonState(isConnected: isConnected, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func enableLiquidGlassForCurrentScreen(isConnected: Bool, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if let hostingController = self.hostingController {
                hostingController.view.isHidden = false
                self.buttonState?.isConnected = isConnected
                result(true)
                return
            }
            
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }

            flutterViewController.view.subviews.filter { $0.tag == 9998 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9998 {
                    child.removeFromParent()
                }
            }

            let state = PowerButtonState(isConnected: isConnected)
            self.buttonState = state

            let liquidGlassOverlay = AuthenticLiquidGlassPowerButton(state: state) {
                let channel = FlutterMethodChannel(name: "liquid_glass_power_button", binaryMessenger: flutterViewController.binaryMessenger)
                channel.invokeMethod("onPowerButtonTapped", arguments: nil)
            }

            let hostingController = UIHostingController(rootView: AnyView(liquidGlassOverlay))
            hostingController.view.backgroundColor = UIColor.clear
            hostingController.view.tag = 9998
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.isAccessibilityElement = false
            hostingController.view.accessibilityViewIsModal = false
            
            flutterViewController.addChild(hostingController)
            flutterViewController.view.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.bottomAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
                hostingController.view.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor, constant: -16),
                hostingController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                hostingController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ])
            
            hostingController.didMove(toParent: flutterViewController)
            self.hostingController = hostingController

            result(true)
        }
    }
    
    private func updatePowerButtonState(isConnected: Bool, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if let buttonState = self.buttonState {
                buttonState.isConnected = isConnected
                result(true)
            } else {
                result(false)
            }
        }
    }
    
    private func disableLiquidGlassForCurrentScreen(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if let hostingController = self.hostingController {
                hostingController.view.isHidden = true
                result(true)
            } else {
                result(false)
            }
        }
    }
}

// ============================================================================
// MARK: - Info Button (SSH Screen - Bottom Left)
// ============================================================================

struct AuthenticLiquidGlassInfoButton: View {
    let onInfoTapped: () -> Void
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer {
            Button(action: onInfoTapped) {
                Image(systemName: "info")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())
            .glassEffectID("infoButton", in: namespace)
        }
    }
}

class SimpleLiquidGlassInfoButtonPlugin: NSObject, FlutterPlugin {
    private var hostingController: UIHostingController<AnyView>?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_info_button", binaryMessenger: registrar.messenger())
        let instance = SimpleLiquidGlassInfoButtonPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            result(true)
        case "enableNativeLiquidGlassInfoButton":
            enableLiquidGlassForCurrentScreen(result: result)
        case "disableNativeLiquidGlassInfoButton":
            disableLiquidGlassForCurrentScreen(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func enableLiquidGlassForCurrentScreen(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if let hostingController = self.hostingController {
                hostingController.view.isHidden = false
                result(true)
                return
            }
            
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }

            flutterViewController.view.subviews.filter { $0.tag == 9997 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9997 {
                    child.removeFromParent()
                }
            }

            let liquidGlassOverlay = AuthenticLiquidGlassInfoButton {
                let channel = FlutterMethodChannel(name: "liquid_glass_info_button", binaryMessenger: flutterViewController.binaryMessenger)
                channel.invokeMethod("onInfoButtonTapped", arguments: nil)
            }

            let hostingController = UIHostingController(rootView: AnyView(liquidGlassOverlay))
            hostingController.view.backgroundColor = UIColor.clear
            hostingController.view.tag = 9997
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.isAccessibilityElement = false
            hostingController.view.accessibilityViewIsModal = false
            
            flutterViewController.addChild(hostingController)
            flutterViewController.view.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.bottomAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
                hostingController.view.leadingAnchor.constraint(equalTo: flutterViewController.view.leadingAnchor, constant: 16),
                hostingController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                hostingController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ])
            
            hostingController.didMove(toParent: flutterViewController)
            self.hostingController = hostingController

            result(true)
        }
    }
    
    private func disableLiquidGlassForCurrentScreen(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if let hostingController = self.hostingController {
                hostingController.view.isHidden = true
                result(true)
            } else {
                result(false)
            }
        }
    }
}

// ============================================================================
// MARK: - Back Button (Info Screen - Top Left)
// ============================================================================

struct AuthenticLiquidGlassBackButton: View {
    let onBackTapped: () -> Void
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer {
            Button(action: onBackTapped) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())
            .glassEffectID("backButton", in: namespace)
        }
    }
}

class SimpleLiquidGlassBackButtonPlugin: NSObject, FlutterPlugin {
    private var hostingController: UIHostingController<AnyView>?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_back_button", binaryMessenger: registrar.messenger())
        let instance = SimpleLiquidGlassBackButtonPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            result(true)
        case "enableNativeLiquidGlassBackButton":
            enableLiquidGlassForCurrentScreen(result: result)
        case "disableNativeLiquidGlassBackButton":
            disableLiquidGlassForCurrentScreen(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func enableLiquidGlassForCurrentScreen(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }

            flutterViewController.view.subviews.filter { $0.tag == 9999 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9999 {
                    child.removeFromParent()
                }
            }

            let liquidGlassOverlay = AuthenticLiquidGlassBackButton {
                let channel = FlutterMethodChannel(name: "liquid_glass_back_button", binaryMessenger: flutterViewController.binaryMessenger)
                channel.invokeMethod("onBackButtonTapped", arguments: nil)
            }

            let hostingController = UIHostingController(rootView: AnyView(liquidGlassOverlay))
            hostingController.view.backgroundColor = UIColor.clear
            hostingController.view.tag = 9999
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.isAccessibilityElement = false
            hostingController.view.accessibilityViewIsModal = false
            
            flutterViewController.addChild(hostingController)
            flutterViewController.view.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.topAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: flutterViewController.view.leadingAnchor, constant: 16),
                hostingController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                hostingController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ])
            
            hostingController.didMove(toParent: flutterViewController)
            self.hostingController = hostingController

            result(true)
        }
    }
    
    private func disableLiquidGlassForCurrentScreen(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }
            
            flutterViewController.view.subviews.filter { $0.tag == 9999 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9999 {
                    child.removeFromParent()
                }
            }
            self.hostingController = nil
            result(true)
        }
    }
}

// ============================================================================
// MARK: - Play Button (Preview Screen - Bottom Right)
// ============================================================================

class PlayButtonState: ObservableObject {
    @Published var isLoading: Bool
    
    init(isLoading: Bool) {
        self.isLoading = isLoading
    }
}

struct AuthenticLiquidGlassPlayButton: View {
    let isLoading: Bool
    let onPlayTapped: () -> Void
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer {
            Button(action: onPlayTapped) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())
            .glassEffectID("playButton", in: namespace)
            .disabled(isLoading)
        }
    }
}

class SimpleLiquidGlassPlayButtonPlugin: NSObject, FlutterPlugin {
    private var buttonState: PlayButtonState?
    private var hostingController: UIHostingController<AnyView>?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_play_button", binaryMessenger: registrar.messenger())
        let instance = SimpleLiquidGlassPlayButtonPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            result(true)
        case "enableNativeLiquidGlassPlayButton":
            let args = call.arguments as? [String: Any]
                let isLoading = args?["isLoading"] as? Bool ?? false
                enableLiquidGlassForCurrentScreen(isLoading: isLoading, result: result)
        case "disableNativeLiquidGlassPlayButton":
            disableLiquidGlassForCurrentScreen(result: result)
        case "updatePlayButtonState":
            let args = call.arguments as? [String: Any]
                let isLoading = args?["isLoading"] as? Bool ?? false
                updatePlayButtonState(isLoading: isLoading, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func enableLiquidGlassForCurrentScreen(isLoading: Bool, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }

            flutterViewController.view.subviews.filter { $0.tag == 9995 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9995 {
                    child.removeFromParent()
                }
            }

            let state = PlayButtonState(isLoading: isLoading)
            self.buttonState = state

            let liquidGlassOverlay = AuthenticLiquidGlassPlayButton(isLoading: state.isLoading) {
                let channel = FlutterMethodChannel(name: "liquid_glass_play_button", binaryMessenger: flutterViewController.binaryMessenger)
                channel.invokeMethod("onPlayButtonTapped", arguments: nil)
            }

            let hostingController = UIHostingController(rootView: AnyView(liquidGlassOverlay))
            hostingController.view.backgroundColor = UIColor.clear
            hostingController.view.tag = 9995
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.isAccessibilityElement = false
            hostingController.view.accessibilityViewIsModal = false
            
            flutterViewController.addChild(hostingController)
            flutterViewController.view.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.bottomAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
                hostingController.view.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor, constant: -16),
                hostingController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                hostingController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ])
            
            hostingController.didMove(toParent: flutterViewController)
            self.hostingController = hostingController

            result(true)
        }
    }
    
    private func updatePlayButtonState(isLoading: Bool, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if let buttonState = self.buttonState {
                buttonState.isLoading = isLoading
                result(true)
            } else {
                result(false)
            }
        }
    }
    
    private func disableLiquidGlassForCurrentScreen(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }
            
            flutterViewController.view.subviews.filter { $0.tag == 9995 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9995 {
                    child.removeFromParent()
                }
            }
            self.hostingController = nil
            result(true)
        }
    }
}


import UIKit
import Flutter
import SwiftUI

// ============================================================================
// LIQUID GLASS UI COMPONENTS - iOS 26+
// ============================================================================
// Complete Liquid Glass component library for the app:
//   1. Shared: GlassEffectContainer utility
//   2. Buttons: Power, Info, Back, Play, History
//   3. Inputs: Terminal Input Bar, URL Bar
//   4. Tabs: Terminal Tabs
//   5. Notifications: Toast
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
// MARK: - Power Button (Top Right - SSH & Terminal Screens)
// ============================================================================

class PowerButtonState: ObservableObject {
    @Published var isConnected: Bool
    @Published var showCheckmark: Bool = false
    
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
                Image(systemName: state.showCheckmark ? "checkmark" : "power")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(state.isConnected ? .blue : .primary)  // Blue only when connected
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
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
        case "showSuccessAnimation":
            showSuccessAnimation(result: result)
        case "showDisconnectAlert":
            showDisconnectAlert(result: result)
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
            
            // Position: Top Right (16pt from right, 8pt from top safe area)
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.topAnchor, constant: 8),
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
    
    private func showSuccessAnimation(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if let buttonState = self.buttonState {
                // Show checkmark
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    buttonState.showCheckmark = true
                }
                
                // Hide checkmark after 600ms
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        buttonState.showCheckmark = false
                    }
                }
                
                result(true)
            } else {
                result(false)
            }
        }
    }
    
    private func showDisconnectAlert(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }
            
            let alert = UIAlertController(
                title: "End session?",
                message: "This will disconnect your SSH session.",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                let channel = FlutterMethodChannel(name: "liquid_glass_power_button", binaryMessenger: rootViewController.binaryMessenger)
                channel.invokeMethod("onDisconnectCancelled", arguments: nil)
            })
            
            alert.addAction(UIAlertAction(title: "End Session", style: .destructive) { _ in
                let channel = FlutterMethodChannel(name: "liquid_glass_power_button", binaryMessenger: rootViewController.binaryMessenger)
                channel.invokeMethod("onDisconnectConfirmed", arguments: nil)
            })
            
            rootViewController.present(alert, animated: true)
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
// MARK: - Info Button (Top Left - SSH Screen)
// ============================================================================

struct InfoSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Namespace private var namespace
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    // Welcome section
                    InfoSection(
                        title: "Welcome",
                        content: "Terminal-based vibe coding on your own server. Optimized for web development. Connect via SSH, use CLI AI tools like Gemini CLI, Qwen CLI, or Claude Code to generate projects, and preview results—all from your phone or tablet."
                    )
                    
                    // Getting Started section
                    InfoSection(
                        title: "Getting Started",
                        content: "1. Connect to your SSH server\n2. Use AI CLI tools in terminal to code\n3. Start web server in terminal\n4. Preview websites or web apps live"
                    )
                    
                    // Help section
                    InfoSection(
                        title: "Need Help?",
                        content: "1. Check SSH credentials & network connection\n2. Each terminal tab is a separate shell session\n3. Install tmux & CLI AI tools on your server for best experience"
                    )
                    
                    // Policy links
                    HStack(spacing: 24) {
                        Link("Privacy", destination: URL(string: "https://willbarksdale.github.io/v/privacy.html")!)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Link("Terms", destination: URL(string: "https://willbarksdale.github.io/v/terms.html")!)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Link("Support", destination: URL(string: "https://willbarksdale.github.io/v/support.html")!)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 20)
                }
                .padding(32)
            }
            .background(Color(red: 10/255, green: 10/255, blue: 10/255))
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct InfoSection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Text(content)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AuthenticLiquidGlassInfoButton: View {
    @State private var showingInfo = false
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer {
            Button(action: { showingInfo = true }) {
                Image(systemName: "info")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())
            .glassEffectID("infoButton", in: namespace)
        }
        .sheet(isPresented: $showingInfo) {
            InfoSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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

            let liquidGlassOverlay = AuthenticLiquidGlassInfoButton()

            let hostingController = UIHostingController(rootView: AnyView(liquidGlassOverlay))
            hostingController.view.backgroundColor = UIColor.clear
            hostingController.view.tag = 9997
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.isAccessibilityElement = false
            hostingController.view.accessibilityViewIsModal = false
            
            flutterViewController.addChild(hostingController)
            flutterViewController.view.addSubview(hostingController.view)
            
            // Position: Top Left (16pt from left, 8pt from top safe area)
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: flutterViewController.view.leadingAnchor, constant: 16),
                hostingController.view.topAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.topAnchor, constant: 8),
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
    private var bottomConstraint: NSLayoutConstraint?
    private var keyboardObservers: [Any] = []
    
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
            
            // Position: Bottom Right (16pt from right, 8pt from bottom safe area)
            let constraint = hostingController.view.bottomAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
            self.bottomConstraint = constraint
            
            NSLayoutConstraint.activate([
                constraint,
                hostingController.view.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor, constant: -16),
                hostingController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                hostingController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ])
            
            // Add keyboard observers to move button up with keyboard
            let showObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillShowNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak flutterViewController] notification in
                guard let self = self,
                      let flutterViewController = flutterViewController,
                      let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      let constraint = self.bottomConstraint else { return }
                
                let keyboardHeight = keyboardFrame.height
                let safeAreaBottom = flutterViewController.view.safeAreaInsets.bottom
                
                // Move button to align with terminal input (keyboard height - safe area + 8pt padding)
                constraint.constant = -(keyboardHeight - safeAreaBottom + 8)
                
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    flutterViewController.view.layoutIfNeeded()
                }
            }
            
            let hideObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak flutterViewController] _ in
                guard let self = self,
                      let flutterViewController = flutterViewController,
                      let constraint = self.bottomConstraint else { return }
                
                // Move back to original position
                constraint.constant = -8
                
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    flutterViewController.view.layoutIfNeeded()
                }
            }
            
            self.keyboardObservers = [showObserver, hideObserver]
            
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
            
            // Remove keyboard observers
            for observer in self.keyboardObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            self.keyboardObservers.removeAll()
            
            flutterViewController.view.subviews.filter { $0.tag == 9995 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9995 {
                    child.removeFromParent()
                }
            }
            self.hostingController = nil
            self.bottomConstraint = nil
            result(true)
        }
    }
}

// ============================================================================
// MARK: - History Button (Bottom Right - SSH Screen)
// ============================================================================
// Recent credentials button - loads last used SSH credentials

struct AuthenticLiquidGlassHistoryButton: View {
    let onHistoryTapped: () -> Void
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer {
            Button(action: onHistoryTapped) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())
            .glassEffectID("historyButton", in: namespace)
        }
    }
}

@available(iOS 26.0, *)
class SimpleLiquidGlassHistoryButtonPlugin: NSObject, FlutterPlugin {
    private var hostingController: UIHostingController<AuthenticLiquidGlassHistoryButton>?
    private var onHistoryTappedCallback: (() -> Void)?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_history_button", binaryMessenger: registrar.messenger())
        let instance = SimpleLiquidGlassHistoryButtonPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            result(true)
        case "enableNativeLiquidGlassHistoryButton":
            enableNativeButton(result: result)
        case "disableNativeLiquidGlassHistoryButton":
            disableNativeButton(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func enableNativeButton(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }
            
            // Remove existing button if any
            flutterViewController.view.subviews.filter { $0.tag == 9996 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9996 {
                    child.removeFromParent()
                }
            }
            
            // Create the button
            let buttonView = AuthenticLiquidGlassHistoryButton(
                onHistoryTapped: { [weak self] in
                    self?.handleHistoryTapped(flutterViewController: flutterViewController)
                }
            )
            
            let hosting = UIHostingController(rootView: buttonView)
            hosting.view.backgroundColor = .clear
            hosting.view.tag = 9996
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            
            flutterViewController.addChild(hosting)
            flutterViewController.view.addSubview(hosting.view)
            
            // Position: Bottom Right (16pt from right, 8pt from bottom safe area)
            NSLayoutConstraint.activate([
                hosting.view.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor, constant: -16),
                hosting.view.bottomAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
                hosting.view.widthAnchor.constraint(equalToConstant: 44),
                hosting.view.heightAnchor.constraint(equalToConstant: 44)
            ])
            
            hosting.didMove(toParent: flutterViewController)
            self.hostingController = hosting
            
            result(true)
        }
    }
    
    private func handleHistoryTapped(flutterViewController: FlutterViewController) {
        print("🕐 History button tapped")
        let channel = FlutterMethodChannel(name: "liquid_glass_history_button", binaryMessenger: flutterViewController.binaryMessenger)
        channel.invokeMethod("onHistoryTapped", arguments: nil)
    }
    
    private func disableNativeButton(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }
            
            flutterViewController.view.subviews.filter { $0.tag == 9996 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9996 {
                    child.removeFromParent()
                }
            }
            self.hostingController = nil
            result(true)
        }
    }
}

// ============================================================================
// MARK: - URL Bar (Bottom - Preview Screen)
// ============================================================================
// Safari-style URL bar with navigation buttons and terminal button

struct LiquidGlassURLBar: View {
    let url: String
    let canGoBack: Bool
    let canGoForward: Bool
    let onBackTapped: () -> Void
    let onForwardTapped: () -> Void
    let onCloseTapped: () -> Void
    let onRefreshTapped: () -> Void
    let onURLSubmitted: (String) -> Void
    
    @State private var isEditingURL: Bool = false
    @State private var editingURL: String
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var namespace
    
    init(
        url: String,
        canGoBack: Bool,
        canGoForward: Bool,
        onBackTapped: @escaping () -> Void,
        onForwardTapped: @escaping () -> Void,
        onCloseTapped: @escaping () -> Void,
        onRefreshTapped: @escaping () -> Void,
        onURLSubmitted: @escaping (String) -> Void
    ) {
        self.url = url
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.onBackTapped = onBackTapped
        self.onForwardTapped = onForwardTapped
        self.onCloseTapped = onCloseTapped
        self.onRefreshTapped = onRefreshTapped
        self.onURLSubmitted = onURLSubmitted
        self._editingURL = State(initialValue: url)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if isEditingURL {
                // Editing mode: Just URL field and X button (Safari style)
                HStack(spacing: 8) {
                    // URL TextField container with Liquid Glass
                    HStack(spacing: 8) {
                        TextField("Search or enter website name", text: $editingURL, onCommit: {
                            onURLSubmitted(editingURL)
                            isEditingURL = false
                            isTextFieldFocused = false
                        })
                        .font(.system(size: 17))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.primary)
                        .focused($isTextFieldFocused)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .glassEffect(.regular.interactive())
                    .glassEffectID("urlFieldEditing", in: namespace)
                    
                    // X button to dismiss keyboard (cancel editing)
                    Button(action: {
                        isEditingURL = false
                        isTextFieldFocused = false
                        editingURL = url // Reset to original URL
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive())
                    .glassEffectID("closeButton", in: namespace)
                }
                .padding(.horizontal, 16)
                .onAppear {
                    // Auto-focus when entering edit mode (Safari behavior)
                    if isEditingURL {
                        isTextFieldFocused = true
                    }
                }
            } else {
                // Display mode: Navigation buttons + URL + Terminal button
                // Combined back/forward button (Safari-style pill)
                HStack(spacing: 0) {
                    Button(action: onBackTapped) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .opacity(canGoBack ? 1.0 : 0.3)
                            .frame(width: 32, height: 40)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoBack)
                    
                    Divider()
                        .frame(height: 20)
                        .foregroundStyle(.primary)
                        .opacity(0.2)
                    
                    Button(action: onForwardTapped) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .opacity(canGoForward ? 1.0 : 0.3)
                            .frame(width: 32, height: 40)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoForward)
                }
                .glassEffect(.regular.interactive())
                .glassEffectID("navigationButtons", in: namespace)
                
                // URL bar display (tap to edit)
                Button(action: {
                    isEditingURL = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        Text(simplifiedURL(url))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive())
                .glassEffectID("urlBarDisplay", in: namespace)
                
                // Refresh button (separate from URL bar)
                Button(action: onRefreshTapped) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive())
                .glassEffectID("refreshButton", in: namespace)
                
                // Back to Terminal button
                Button(action: onCloseTapped) {
                    Image(systemName: "apple.terminal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive())
                .glassEffectID("terminalButton", in: namespace)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: url) { _, newURL in
            editingURL = newURL
        }
        .onChange(of: isEditingURL) { _, isEditing in
            // Auto-focus when entering edit mode (Safari behavior)
            if isEditing {
                // Delay slightly to ensure UI transition completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTextFieldFocused = true
                }
            }
        }
    }
    
    // Helper to simplify URL for display (remove http://, etc.)
    private func simplifiedURL(_ urlString: String) -> String {
        var simplified = urlString
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        
        // Remove trailing slash
        if simplified.hasSuffix("/") {
            simplified.removeLast()
        }
        
        return simplified
    }
}

class SimpleLiquidGlassURLBarPlugin: NSObject, FlutterPlugin {
    private var hostingController: UIHostingController<LiquidGlassURLBar>?
    private var methodChannel: FlutterMethodChannel?
    private var bottomConstraint: NSLayoutConstraint?
    private var keyboardObservers: [Any] = []
    private var currentURL: String = ""
    private var currentCanGoBack: Bool = false
    private var currentCanGoForward: Bool = false
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_url_bar", binaryMessenger: registrar.messenger())
        let instance = SimpleLiquidGlassURLBarPlugin()
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            result(true)
        case "show":
            let args = call.arguments as? [String: Any]
            let url = args?["url"] as? String ?? ""
            let canGoBack = args?["canGoBack"] as? Bool ?? false
            let canGoForward = args?["canGoForward"] as? Bool ?? false
            show(url: url, canGoBack: canGoBack, canGoForward: canGoForward, result: result)
        case "hide":
            hide(result: result)
        case "updateState":
            let args = call.arguments as? [String: Any]
            let url = args?["url"] as? String
            let canGoBack = args?["canGoBack"] as? Bool
            let canGoForward = args?["canGoForward"] as? Bool
            updateState(url: url, canGoBack: canGoBack, canGoForward: canGoForward, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func show(url: String, canGoBack: Bool, canGoForward: Bool, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                result(false)
                return
            }
            
            // Store current state
            self.currentURL = url
            self.currentCanGoBack = canGoBack
            self.currentCanGoForward = canGoForward
            
            // Remove existing if any
            window.subviews.filter { $0.tag == 9990 }.forEach { $0.removeFromSuperview() }
            
            let urlBar = LiquidGlassURLBar(
                url: url,
                canGoBack: canGoBack,
                canGoForward: canGoForward,
                onBackTapped: { [weak self] in
                    self?.methodChannel?.invokeMethod("onBackTapped", arguments: nil)
                },
                onForwardTapped: { [weak self] in
                    self?.methodChannel?.invokeMethod("onForwardTapped", arguments: nil)
                },
                onCloseTapped: { [weak self] in
                    self?.methodChannel?.invokeMethod("onCloseTapped", arguments: nil)
                },
                onRefreshTapped: { [weak self] in
                    self?.methodChannel?.invokeMethod("onRefreshTapped", arguments: nil)
                },
                onURLSubmitted: { [weak self] newURL in
                    self?.methodChannel?.invokeMethod("onURLSubmitted", arguments: ["url": newURL])
                }
            )
            
            let hosting = UIHostingController(rootView: urlBar)
            hosting.view.backgroundColor = .clear
            hosting.view.tag = 9990
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            
            window.addSubview(hosting.view)
            
            // Position at bottom with safe area (very close to bottom for sleeker look)
            let safeAreaBottom = window.safeAreaInsets.bottom
            let constraint = hosting.view.bottomAnchor.constraint(equalTo: window.bottomAnchor, constant: -(safeAreaBottom + 0))
            self.bottomConstraint = constraint
            
            NSLayoutConstraint.activate([
                hosting.view.leadingAnchor.constraint(equalTo: window.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: window.trailingAnchor),
                constraint,
                hosting.view.heightAnchor.constraint(equalToConstant: 56)
            ])
            
            // Observe keyboard to move URL bar above it
            let showObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillShowNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak window] notification in
                guard let self = self,
                      let window = window,
                      let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      let constraint = self.bottomConstraint else { return }
                
                let keyboardHeight = keyboardFrame.height
                
                // Move URL bar above keyboard
                constraint.constant = -keyboardHeight - 8
                
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    window.layoutIfNeeded()
                }
            }
            
            let hideObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self = self,
                      let window = window,
                      let constraint = self.bottomConstraint else { return }
                
                // Move URL bar back to bottom
                let safeAreaBottom = window.safeAreaInsets.bottom
                constraint.constant = -(safeAreaBottom + 0)
                
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    window.layoutIfNeeded()
                }
            }
            
            self.keyboardObservers = [showObserver, hideObserver]
            self.hostingController = hosting
            result(true)
        }
    }
    
    private func hide(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                result(false)
                return
            }
            
            // Remove keyboard observers
            for observer in self.keyboardObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            self.keyboardObservers.removeAll()
            
            window.subviews.filter { $0.tag == 9990 }.forEach { $0.removeFromSuperview() }
            self.hostingController = nil
            self.bottomConstraint = nil
            result(true)
        }
    }
    
    private func updateState(url: String?, canGoBack: Bool?, canGoForward: Bool?, result: @escaping FlutterResult) {
        // Use provided values or keep current state
        let updatedURL = url ?? self.currentURL
        let updatedCanGoBack = canGoBack ?? self.currentCanGoBack
        let updatedCanGoForward = canGoForward ?? self.currentCanGoForward
        
        // Recreate the view with updated state
        show(url: updatedURL, canGoBack: updatedCanGoBack, canGoForward: updatedCanGoForward, result: result)
    }
}

// ============================================================================
// MARK: - Toast Notifications (Bottom Center)
// ============================================================================
// System-wide toast messages for success, error, and info

@available(iOS 26.0, *)
struct LiquidGlassToast: View {
    let message: String
    let style: ToastStyle
    @Namespace private var namespace
    
    enum ToastStyle {
        case success
        case error
        case info
        
        var backgroundColor: Color {
            switch self {
            case .success: return .blue.opacity(0.9)  // System blue for success
            case .error: return .red.opacity(0.9)
            case .info: return .blue.opacity(0.9)
            }
        }
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: style.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            
            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(style.backgroundColor)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

@available(iOS 26.0, *)
class LiquidGlassToastPlugin: NSObject, FlutterPlugin {
    private var hostingController: UIHostingController<AnyView>?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_toast", binaryMessenger: registrar.messenger())
        let instance = LiquidGlassToastPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "show":
            let args = call.arguments as? [String: Any]
            let message = args?["message"] as? String ?? ""
            let styleString = args?["style"] as? String ?? "info"
            let duration = args?["duration"] as? Double ?? 2.0
            
            let style: LiquidGlassToast.ToastStyle
            switch styleString {
            case "success": style = .success
            case "error": style = .error
            default: style = .info
            }
            
            show(message: message, style: style, duration: duration, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func show(message: String, style: LiquidGlassToast.ToastStyle, duration: Double, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                result(false)
                return
            }
            
            // Remove existing toast if any
            window.subviews.filter { $0.tag == 9989 }.forEach { $0.removeFromSuperview() }
            
            let toast = LiquidGlassToast(message: message, style: style)
            let hosting = UIHostingController(rootView: AnyView(toast))
            hosting.view.backgroundColor = .clear
            hosting.view.tag = 9989
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            
            window.addSubview(hosting.view)
            
            let safeAreaBottom = window.safeAreaInsets.bottom
            NSLayoutConstraint.activate([
                hosting.view.centerXAnchor.constraint(equalTo: window.centerXAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: window.bottomAnchor, constant: -(safeAreaBottom + 20)),
                hosting.view.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 20),
                hosting.view.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -20)
            ])
            
            self.hostingController = hosting
            
            // Animate in
            hosting.view.alpha = 0
            hosting.view.transform = CGAffineTransform(translationX: 0, y: 20)
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                hosting.view.alpha = 1
                hosting.view.transform = .identity
            }
            
            // Auto-dismiss after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn, animations: {
                    hosting.view.alpha = 0
                    hosting.view.transform = CGAffineTransform(translationX: 0, y: 20)
                }) { _ in
                    hosting.view.removeFromSuperview()
                    self.hostingController = nil
                }
            }
            
            result(true)
        }
    }
}

// ============================================================================
// MARK: - Terminal Input Bar (Bottom - Terminal Screen)
// ============================================================================
// Native command input with keyboard handling, send button, and animations

@available(iOS 16.0, *)
class LiquidGlassTerminalInputPlugin: NSObject, FlutterPlugin {
    private var hostingController: Any? // Use Any to avoid iOS 26 requirement on class level
    private var terminalInputView: Any? // Use Any to avoid iOS 26 requirement
    private var bottomConstraint: NSLayoutConstraint? // Keep track of keyboard constraint
    private var keyboardObservers: [Any] = [] // Track observers for cleanup
    static var shared: LiquidGlassTerminalInputPlugin?
    private var methodChannel: FlutterMethodChannel?
    
    // State tracking to prevent duplicate creation
    private var isTerminalInputVisible = false

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_terminal_input", binaryMessenger: registrar.messenger())
        let instance = LiquidGlassTerminalInputPlugin()
        instance.methodChannel = channel
        LiquidGlassTerminalInputPlugin.shared = instance
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            if #available(iOS 26.0, *) {
                result(true)
            } else {
                result(false)
            }
        case "showTerminalInput":
            if #available(iOS 26.0, *) {
                showTerminalInput(call: call, result: result)
            } else {
                result(false)
            }
        case "hideTerminalInput":
            hideTerminalInput(result: result)
        case "clearTerminalInput":
            if #available(iOS 26.0, *) {
                clearTerminalInput(result: result)
            } else {
                result(false)
            }
        case "setTerminalInputText":
            if #available(iOS 26.0, *) {
                setTerminalInputText(call: call, result: result)
            } else {
                result(false)
            }
        case "dismissKeyboard":
            dismissKeyboard(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @available(iOS 26.0, *)
    private func showTerminalInput(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Check if already visible
        if isTerminalInputVisible {
            print("ℹ️ Terminal input already visible, skipping creation")
            result(true)
            return
        }
        
        guard let window = UIApplication.shared.windows.first,
              let flutterViewController = window.rootViewController as? FlutterViewController else {
            result(false)
            return
        }

        let args = call.arguments as? [String: Any]
        let placeholder = args?["placeholder"] as? String ?? "Type command..."

        // Create terminal input view model
        let viewModel = TerminalInputViewModel(
            placeholder: placeholder,
            onSendCommand: { [weak self] text in
                self?.methodChannel?.invokeMethod("onCommandSent", arguments: ["text": text])
            },
            onInputChanged: { [weak self] text in
                self?.methodChannel?.invokeMethod("onInputChanged", arguments: ["text": text])
            },
            onDismissKeyboard: { [weak self] in
                self?.methodChannel?.invokeMethod("onDismissKeyboard", arguments: nil)
            },
            onControlKey: { [weak self] key in
                self?.methodChannel?.invokeMethod("onControlKey", arguments: ["key": key])
            }
        )
        
        let inputView = TerminalInputView(viewModel: viewModel)
        terminalInputView = inputView

        // Create hosting controller
        let hosting = UIHostingController(rootView: inputView)
        hosting.view.backgroundColor = .clear
        hosting.view.isUserInteractionEnabled = true
        self.hostingController = hosting

        // Add to window directly (not as subview of Flutter view controller)
        window.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Position at same height as Info/Power buttons (between them)
        let safeAreaBottom = window.safeAreaInsets.bottom
        let bottomOffset = 8 + safeAreaBottom // Same as toolbar buttons (-8 from safe area = 8 + safeAreaBottom from window bottom)
        let inputHeight: CGFloat = 44 // Match button height for visual consistency
        
        let constraint = hosting.view.bottomAnchor.constraint(equalTo: window.bottomAnchor, constant: -bottomOffset)
        self.bottomConstraint = constraint
        
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 20), // Standard left padding
            hosting.view.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -76), // 16px gap + 44px power button + 16px padding
            constraint,
            hosting.view.heightAnchor.constraint(equalToConstant: inputHeight)
        ])
        
        // Listen for keyboard notifications to move input above keyboard
        let showObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self, weak window] notification in
            guard let self = self,
                  let window = window,
                  let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let constraint = self.bottomConstraint else { return }
            
            let keyboardHeight = keyboardFrame.height
            
            // Notify Flutter that keyboard is showing
            self.methodChannel?.invokeMethod("onKeyboardShow", arguments: ["height": keyboardHeight])
            
            // Animate input above keyboard
            constraint.constant = -keyboardHeight - 8
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                window.layoutIfNeeded()
            }
        }
        
        let hideObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self, weak window] _ in
            guard let self = self,
                  let window = window,
                  let constraint = self.bottomConstraint else { return }
            
            // Notify Flutter that keyboard is hiding
            self.methodChannel?.invokeMethod("onKeyboardHide", arguments: nil)
            
            // Animate back to original position
            constraint.constant = -bottomOffset
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                window.layoutIfNeeded()
            }
        }
        
        keyboardObservers = [showObserver, hideObserver]
        
        // Bring to front to ensure it's above Flutter content
        window.bringSubviewToFront(hosting.view)
        
        isTerminalInputVisible = true
        print("✅ Liquid Glass terminal input created with keyboard observer")
        result(true)
    }
    
    private func hideTerminalInput(result: @escaping FlutterResult) {
        if #available(iOS 26.0, *) {
            if let hosting = hostingController as? UIHostingController<TerminalInputView> {
                // Remove keyboard observers properly
                for observer in keyboardObservers {
                    NotificationCenter.default.removeObserver(observer)
                }
                keyboardObservers.removeAll()
                
                hosting.view.removeFromSuperview()
                hostingController = nil
                terminalInputView = nil
                bottomConstraint = nil
                isTerminalInputVisible = false
                print("✅ Liquid Glass terminal input hidden and cleaned up")
            }
        }
        result(true)
    }

    @available(iOS 26.0, *)
    private func clearTerminalInput(result: @escaping FlutterResult) {
        if let inputView = terminalInputView as? TerminalInputView {
            inputView.viewModel.clearInput()
        }
        result(true)
    }

    @available(iOS 26.0, *)
    private func setTerminalInputText(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let text = args?["text"] as? String ?? ""
        
        if let inputView = terminalInputView as? TerminalInputView {
            inputView.viewModel.setText(text)
        }
        result(true)
    }
    
    private func dismissKeyboard(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            // Resign first responder to dismiss keyboard
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            print("⌨️ Keyboard dismissed")
            result(true)
        }
    }
}

// MARK: - Terminal Input View Model

@available(iOS 26.0, *)
class TerminalInputViewModel: ObservableObject {
    @Published var commandText: String = ""
    @Published var placeholder: String
    
    var onSendCommand: ((String) -> Void)?
    var onInputChanged: ((String) -> Void)?
    var onDismissKeyboard: (() -> Void)?
    var onControlKey: ((String) -> Void)?
    
    init(placeholder: String, onSendCommand: ((String) -> Void)?, onInputChanged: ((String) -> Void)?, onDismissKeyboard: (() -> Void)?, onControlKey: ((String) -> Void)? = nil) {
        self.placeholder = placeholder
        self.onSendCommand = onSendCommand
        self.onInputChanged = onInputChanged
        self.onDismissKeyboard = onDismissKeyboard
        self.onControlKey = onControlKey
    }
    
    func sendCommand() {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        onSendCommand?(trimmed)
        commandText = ""
    }
    
    func clearInput() {
        commandText = ""
    }
    
    func setText(_ text: String) {
        commandText = text
    }
    
    func dismissKeyboard() {
        onDismissKeyboard?()
    }
    
    func sendControlKey(_ key: String) {
        onControlKey?(key)
    }
}

// MARK: - Terminal Input View (Liquid Glass Style)

@available(iOS 26.0, *)
struct TerminalInputView: View {
    @ObservedObject var viewModel: TerminalInputViewModel
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var namespace
    
    var body: some View {
        VStack(spacing: 8) {
            // Ctrl Shortcuts Toolbar (only show when keyboard is focused)
            if isTextFieldFocused {
                HStack(spacing: 8) {
                    // Ctrl+C - Terminate process
                    ShortcutButton(label: "^C", description: "Cancel") {
                        viewModel.sendControlKey("c")
                    }
                    
                    // Ctrl+L - Clear screen
                    ShortcutButton(label: "^L", description: "Clear") {
                        viewModel.sendControlKey("l")
                    }
                    
                    // Ctrl+R - Reverse search
                    ShortcutButton(label: "^R", description: "Search") {
                        viewModel.sendControlKey("r")
                    }
                    
                    // Ctrl+U - Delete to start
                    ShortcutButton(label: "^U", description: "Delete") {
                        viewModel.sendControlKey("u")
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.3))
                .cornerRadius(12)
                .padding(.horizontal, 20)
            }
            
            // Main Input Bar
            let content = HStack(spacing: 12) {
                // Dismiss Keyboard Button (left side)
                Button(action: {
                    isTextFieldFocused = false
                    viewModel.dismissKeyboard()
                }) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                
                // TextField - single line terminal input
                TextField(viewModel.placeholder, text: $viewModel.commandText)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.send)
                    .onChange(of: viewModel.commandText) { oldValue, newValue in
                        // Notify Flutter of text changes for real-time sync
                        viewModel.onInputChanged?(newValue)
                    }
                    .onSubmit {
                        viewModel.sendCommand()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Send Button (right side) - arrow.up.circle (no fill)
                Button(action: {
                    viewModel.sendCommand()
                }) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(hasText ? Color.blue : Color.gray.opacity(0.5))
                }
                .disabled(!hasText)
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: hasText)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            
            // Apply same glass effect as chat input
            return AnyView(
                GlassEffectContainer {
                    content
                }
                .glassEffect(.regular.interactive())
                .glassEffectID("terminalInput", in: namespace)
                .frame(height: 64)
            )
        }
    }
    
    private var hasText: Bool {
        !viewModel.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Shortcut Button Component
@available(iOS 26.0, *)
struct ShortcutButton: View {
    let label: String
    let description: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 60, height: 44)
            .background(Color.white.opacity(0.15))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// ============================================================================
// MARK: - Shortcut Alerts (Native SwiftUI Alerts for ctrl/srvr/bkup)
// ============================================================================

@available(iOS 16.0, *)
class ShortcutAlertsPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "shortcut_alerts", binaryMessenger: registrar.messenger())
        let instance = ShortcutAlertsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showCtrlAlert":
            showCtrlAlert(result: result)
        case "showServerAlert":
            showServerAlert(result: result)
        case "showBackupAlert":
            showBackupAlert(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func showCtrlAlert(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootViewController = window.rootViewController as? FlutterViewController else {
                result(nil)
                return
            }
            
            let alert = UIAlertController(
                title: "Ctrl Shortcuts",
                message: "Select a control sequence",
                preferredStyle: .actionSheet
            )
            
            // The 4 essential Ctrl shortcuts
            alert.addAction(UIAlertAction(title: "^C - Cancel Process", style: .default) { _ in
                result("\u{03}") // Ctrl+C
            })
            
            alert.addAction(UIAlertAction(title: "^L - Clear Screen", style: .default) { _ in
                result("\u{0c}") // Ctrl+L
            })
            
            alert.addAction(UIAlertAction(title: "^R - Search History", style: .default) { _ in
                result("\u{12}") // Ctrl+R
            })
            
            alert.addAction(UIAlertAction(title: "^U - Delete Line", style: .default) { _ in
                result("\u{15}") // Ctrl+U
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                result(nil)
            })
            
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func showServerAlert(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootViewController = window.rootViewController as? FlutterViewController else {
                result(nil)
                return
            }
            
            let alert = UIAlertController(
                title: "Start Web Server",
                message: "Select a server command",
                preferredStyle: .actionSheet
            )
            
            alert.addAction(UIAlertAction(title: "npm run dev", style: .default) { _ in
                result("npm run dev")
            })
            
            alert.addAction(UIAlertAction(title: "python3 -m http.server 8000", style: .default) { _ in
                result("python3 -m http.server 8000")
            })
            
            alert.addAction(UIAlertAction(title: "php -S localhost:8000", style: .default) { _ in
                result("php -S localhost:8000")
            })
            
            alert.addAction(UIAlertAction(title: "npx serve -l 3000", style: .default) { _ in
                result("npx serve -l 3000")
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                result(nil)
            })
            
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func showBackupAlert(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootViewController = window.rootViewController as? FlutterViewController else {
                result(nil)
                return
            }
            
            let alert = UIAlertController(
                title: "Quick Commands",
                message: "Select a command",
                preferredStyle: .actionSheet
            )
            
            alert.addAction(UIAlertAction(title: "tar -czf backup.tar.gz .", style: .default) { _ in
                result("tar -czf backup.tar.gz .")
            })
            
            alert.addAction(UIAlertAction(title: "git add . && git commit -m \"checkpoint\"", style: .default) { _ in
                result("git add . && git commit -m \"checkpoint\"")
            })
            
            alert.addAction(UIAlertAction(title: "npm run build", style: .default) { _ in
                result("npm run build")
            })
            
            alert.addAction(UIAlertAction(title: "docker-compose up -d", style: .default) { _ in
                result("docker-compose up -d")
            })
            
            alert.addAction(UIAlertAction(title: "pm2 restart all", style: .default) { _ in
                result("pm2 restart all")
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                result(nil)
            })
            
            rootViewController.present(alert, animated: true)
        }
    }
}

// ============================================================================
// MARK: - Terminal Tabs (Top Center - Terminal Screen)
// ============================================================================
// 3 native tabs for tmux sessions with tap/long-press reset functionality

@available(iOS 26.0, *)
class LiquidGlassTerminalTabsPlugin: NSObject, FlutterPlugin {
    private var hostingController: UIHostingController<TerminalTabsView>?
    private var methodChannel: FlutterMethodChannel?
    private var tabsState: TerminalTabsState?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_terminal_tabs", binaryMessenger: registrar.messenger())
        let instance = LiquidGlassTerminalTabsPlugin()
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            result(true)
        case "show":
            let args = call.arguments as? [String: Any]
            let activeTab = args?["activeTab"] as? Int ?? 0
            let tabCount = args?["tabCount"] as? Int ?? 0
            show(activeTab: activeTab, tabCount: tabCount, result: result)
        case "hide":
            hide(result: result)
        case "updateTabs":
            let args = call.arguments as? [String: Any]
            let activeTab = args?["activeTab"] as? Int ?? 0
            let tabCount = args?["tabCount"] as? Int ?? 0
            updateTabs(activeTab: activeTab, tabCount: tabCount, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func show(activeTab: Int, tabCount: Int, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }
            
            // Remove existing if any
            window.subviews.filter { $0.tag == 9994 }.forEach { $0.removeFromSuperview() }
            
            let state = TerminalTabsState(activeTab: activeTab, tabCount: tabCount)
            self.tabsState = state
            
            let tabsView = TerminalTabsView(
                state: state,
                onTabTapped: { [weak self] index in
                    self?.methodChannel?.invokeMethod("onTabTapped", arguments: ["index": index])
                },
                onTabLongPressed: { [weak self] index in
                    self?.methodChannel?.invokeMethod("onTabLongPressed", arguments: ["index": index])
                }
            )
            
            let hosting = UIHostingController(rootView: tabsView)
            hosting.view.backgroundColor = .clear
            hosting.view.tag = 9994
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            
            window.addSubview(hosting.view)
            
            // Position at top center
            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 10),
                hosting.view.centerXAnchor.constraint(equalTo: window.centerXAnchor),
                hosting.view.heightAnchor.constraint(equalToConstant: 44)
            ])
            
            self.hostingController = hosting
            result(true)
        }
    }
    
    private func hide(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                result(false)
                return
            }
            
            window.subviews.filter { $0.tag == 9994 }.forEach { $0.removeFromSuperview() }
            self.hostingController = nil
            result(true)
        }
    }
    
    private func updateTabs(activeTab: Int, tabCount: Int, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if let state = self.tabsState {
                state.activeTab = activeTab
                state.tabCount = tabCount
                result(true)
            } else {
                result(false)
            }
        }
    }
}

// MARK: - Terminal Tabs State

@available(iOS 26.0, *)
class TerminalTabsState: ObservableObject {
    @Published var activeTab: Int
    @Published var tabCount: Int
    
    init(activeTab: Int, tabCount: Int) {
        self.activeTab = activeTab
        self.tabCount = tabCount
    }
}

// MARK: - Terminal Tabs View

@available(iOS 26.0, *)
struct TerminalTabsView: View {
    @ObservedObject var state: TerminalTabsState
    let onTabTapped: (Int) -> Void
    let onTabLongPressed: (Int) -> Void
    @Namespace private var namespace
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                let tabExists = index < state.tabCount
                let isActive = tabExists && index == state.activeTab
                
                GlassEffectContainer {
                    ZStack {
                        Text("\(index + 1)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isActive ? Color.blue : (tabExists ? Color.primary : Color.primary.opacity(0.3)))
                            .frame(width: 44, height: 44)
                            .allowsHitTesting(false)
                        
                        Color.clear
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if tabExists {
                                    onTabTapped(index)
                                }
                            }
                            .contextMenu(menuItems: {
                                if tabExists && isActive {
                                    Button(role: .destructive, action: {
                                        onTabLongPressed(index)
                                    }) {
                                        Label("Reset Terminal \(index + 1)", systemImage: "arrow.clockwise")
                                    }
                                }
                            })
                    }
                    .glassEffect(.regular.interactive())
                    .glassEffectID("terminalTab\(index)", in: namespace)
                }
            }
        }
    }
}

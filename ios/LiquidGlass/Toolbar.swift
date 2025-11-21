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
    private var bottomConstraint: NSLayoutConstraint?
    private var keyboardObservers: [NSObjectProtocol] = []
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_power_button", binaryMessenger: registrar.messenger())
        let instance = SimpleLiquidGlassPowerButtonPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    deinit {
        keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
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
            
            let bottomConstraint = hostingController.view.bottomAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
            self.bottomConstraint = bottomConstraint
            
            NSLayoutConstraint.activate([
                bottomConstraint,
                hostingController.view.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor, constant: -16),
                hostingController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                hostingController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ])
            
            hostingController.didMove(toParent: flutterViewController)
            self.hostingController = hostingController
            
            // Listen for keyboard notifications to move button with keyboard
            self.setupKeyboardObservers(flutterViewController: flutterViewController)

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
    
    private func setupKeyboardObservers(flutterViewController: FlutterViewController) {
        // Keyboard will show - move button up with keyboard
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
            
            // Move button to match terminal input position (above keyboard)
            constraint.constant = -(keyboardHeight - safeAreaBottom + 8)
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                flutterViewController.view.layoutIfNeeded()
            }
        }
        
        // Keyboard will hide - move button back to original position
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
        
        keyboardObservers.append(showObserver)
        keyboardObservers.append(hideObserver)
    }
}

// ============================================================================
// MARK: - Info Button (SSH Screen - Bottom Left)
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
                        Link("Privacy", destination: URL(string: "https://willbarksdale.github.io/v-policy/privacy.html")!)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Link("Terms", destination: URL(string: "https://willbarksdale.github.io/v-policy/terms.html")!)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Link("Support", destination: URL(string: "https://willbarksdale.github.io/v-policy/support.html")!)
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
                hostingController.view.topAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.topAnchor, constant: 10),
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

// ============================================================================
// MARK: - History Button (SSH Screen - Top Left)
// ============================================================================

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
            
            // Position: Top Right (16pt from right, 8pt from top safe area)
            NSLayoutConstraint.activate([
                hosting.view.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor, constant: -16),
                hosting.view.topAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.topAnchor, constant: 8),
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
// MARK: - URL Bar (Preview Screen)
// ============================================================================

struct LiquidGlassURLBar: View {
    let url: String
    let canGoBack: Bool
    let canGoForward: Bool
    let onBackTapped: () -> Void
    let onForwardTapped: () -> Void
    let onCloseTapped: () -> Void
    let onURLSubmitted: (String) -> Void
    
    @State private var isEditingURL: Bool = false
    @State private var editingURL: String
    @Namespace private var namespace
    
    init(
        url: String,
        canGoBack: Bool,
        canGoForward: Bool,
        onBackTapped: @escaping () -> Void,
        onForwardTapped: @escaping () -> Void,
        onCloseTapped: @escaping () -> Void,
        onURLSubmitted: @escaping (String) -> Void
    ) {
        self.url = url
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.onBackTapped = onBackTapped
        self.onForwardTapped = onForwardTapped
        self.onCloseTapped = onCloseTapped
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
                        })
                        .font(.system(size: 17))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .glassEffect(.regular.interactive())
                    .glassEffectID("urlFieldEditing", in: namespace)
                    
                    // X button to close preview
                    Button(action: onCloseTapped) {
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
                        
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive())
                .glassEffectID("urlBarDisplay", in: namespace)
                
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
                onURLSubmitted: { [weak self] newURL in
                    self?.methodChannel?.invokeMethod("onURLSubmitted", arguments: ["url": newURL])
                }
            )
            
            let hosting = UIHostingController(rootView: urlBar)
            hosting.view.backgroundColor = .clear
            hosting.view.tag = 9990
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            
            window.addSubview(hosting.view)
            
            // Position at bottom with safe area
            let safeAreaBottom = window.safeAreaInsets.bottom
            NSLayoutConstraint.activate([
                hosting.view.leadingAnchor.constraint(equalTo: window.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: window.trailingAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: window.bottomAnchor, constant: -(safeAreaBottom + 8)),
                hosting.view.heightAnchor.constraint(equalToConstant: 56)
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
            
            window.subviews.filter { $0.tag == 9990 }.forEach { $0.removeFromSuperview() }
            self.hostingController = nil
            result(true)
        }
    }
    
    private func updateState(url: String?, canGoBack: Bool?, canGoForward: Bool?, result: @escaping FlutterResult) {
        // State updates are handled via SwiftUI @State - recreate the view
        if let url = url {
            let canBack = canGoBack ?? false
            let canForward = canGoForward ?? false
            show(url: url, canGoBack: canBack, canGoForward: canForward, result: result)
        } else {
            result(true)
        }
    }
}


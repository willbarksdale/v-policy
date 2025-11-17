import UIKit
import Flutter
import SwiftUI
import Combine

// ============================================================================
// TERMINAL COMPONENTS - iOS 26+ Liquid Glass
// ============================================================================
// Contains both Terminal Tab Bar and Terminal Input components
// ============================================================================

// ============================================================================
// MARK: - Terminal Tab Bar (Top of Screen)
// ============================================================================

struct LiquidGlassTerminalTabBar: View {
    let tabs: [TerminalTabInfo]
    let activeIndex: Int
    let onTabSelected: (Int) -> Void
    let onTabClosed: (Int) -> Void
    let onNewTab: () -> Void
    let canAddTab: Bool
    @Namespace private var namespace
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side: Tab buttons starting from left, populating right
            HStack(spacing: 12) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    if index == activeIndex {
                        // Active tab: expanded with terminal icon and close button
                        HStack(spacing: 6) {
                            Button(action: { onTabSelected(index) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "apple.terminal")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("\(index + 1)")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundStyle(.blue)
                                .padding(.leading, 12)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { onTabClosed(index) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                        }
                        .frame(height: 44)
                        .glassEffect(.regular.interactive())
                        .glassEffectID("tab-\(index)", in: namespace)
                    } else {
                        // Inactive tab: simple circular button with number
                        Button(action: { onTabSelected(index) }) {
                            Text("\(index + 1)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive())
                        .glassEffectID("tab-\(index)", in: namespace)
                    }
                }
            }
            .padding(.leading, 16)
            
            Spacer()
            
            // Right side: Plus button fixed on the right
            if canAddTab && tabs.count < 3 {
                Button(action: onNewTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive())
                .glassEffectID("newTabButton", in: namespace)
                .padding(.trailing, 16)
            }
        }
        .padding(.vertical, 10)
        .background(Color.clear)
    }
}

// MARK: - Terminal Tab Info Model

struct TerminalTabInfo: Identifiable {
    let id: String
    let name: String
}

// MARK: - Terminal Tab Bar Plugin

class LiquidGlassTabBarPlugin: NSObject, FlutterPlugin {
    private var hostingController: UIHostingController<AnyView>?
    private var currentTabs: [TerminalTabInfo] = []
    private var currentActiveIndex: Int = 0
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_tab_bar", binaryMessenger: registrar.messenger())
        let instance = LiquidGlassTabBarPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("🎯 [Swift] LiquidGlassTabBarPlugin received method call: \(call.method)")
        
        switch call.method {
        case "isLiquidGlassSupported":
            result(true)
        case "showLiquidGlassTabBar":
            print("   → showLiquidGlassTabBar")
            let args = call.arguments as? [String: Any]
                let tabsData = args?["tabs"] as? [[String: String]] ?? []
                let activeIndex = args?["activeIndex"] as? Int ?? 0
                let canAddTab = args?["canAddTab"] as? Bool ?? true
                showTabBar(tabsData: tabsData, activeIndex: activeIndex, canAddTab: canAddTab, result: result)
        case "hideLiquidGlassTabBar":
            print("   → hideLiquidGlassTabBar")
            hideTabBar(result: result)
        case "updateTabs":
            print("   → updateTabs with args: \(call.arguments ?? "nil")")
            let args = call.arguments as? [String: Any]
                let tabsData = args?["tabs"] as? [[String: String]] ?? []
                let activeIndex = args?["activeIndex"] as? Int ?? 0
                let canAddTab = args?["canAddTab"] as? Bool ?? true
                updateTabs(tabsData: tabsData, activeIndex: activeIndex, canAddTab: canAddTab, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func showTabBar(tabsData: [[String: String]], activeIndex: Int, canAddTab: Bool, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }
            
            // Remove any existing tab bar
            flutterViewController.view.subviews.filter { $0.tag == 9994 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9994 {
                    child.removeFromParent()
                }
            }
            
            // Convert tab data
            self.currentTabs = tabsData.map { TerminalTabInfo(id: $0["id"] ?? "", name: $0["name"] ?? "") }
            self.currentActiveIndex = activeIndex
            
            // Create liquid glass tab bar (active tab has close button)
            let tabBar = LiquidGlassTerminalTabBar(
                tabs: self.currentTabs,
                activeIndex: self.currentActiveIndex,
                onTabSelected: { index in
                    let channel = FlutterMethodChannel(name: "liquid_glass_tab_bar", binaryMessenger: flutterViewController.binaryMessenger)
                    channel.invokeMethod("onTabSelected", arguments: index)
                },
                onTabClosed: { index in
                    let channel = FlutterMethodChannel(name: "liquid_glass_tab_bar", binaryMessenger: flutterViewController.binaryMessenger)
                    channel.invokeMethod("onTabClosed", arguments: index)
                },
                onNewTab: {
                    // Simply forward to Flutter - debounce is handled on Flutter side
                    print("➕ [Swift] New tab button tapped, forwarding to Flutter")
                    let channel = FlutterMethodChannel(name: "liquid_glass_tab_bar", binaryMessenger: flutterViewController.binaryMessenger)
                    channel.invokeMethod("onNewTab", arguments: nil)
                },
                canAddTab: canAddTab
            )
            
            let hostingController = UIHostingController(rootView: AnyView(tabBar))
            hostingController.view.backgroundColor = UIColor.clear
            hostingController.view.tag = 9994
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            
            flutterViewController.addChild(hostingController)
            flutterViewController.view.addSubview(hostingController.view)
            
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.topAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: flutterViewController.view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor),
                // Let SwiftUI determine natural height - no fixed height constraint for "free balling" effect
            ])
            
            hostingController.didMove(toParent: flutterViewController)
            self.hostingController = hostingController
            
            result(true)
        }
    }
    
    private func updateTabs(tabsData: [[String: String]], activeIndex: Int, canAddTab: Bool, result: @escaping FlutterResult) {
        print("🔄 [Swift] updateTabs called with \(tabsData.count) tabs, active: \(activeIndex), canAdd: \(canAddTab)")
        print("   Tab data: \(tabsData)")
        
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                print("   ❌ Failed to get Flutter view controller")
                result(false)
                return
            }
            
            // Update tab data
            self.currentTabs = tabsData.map { TerminalTabInfo(id: $0["id"] ?? "", name: $0["name"] ?? "") }
            self.currentActiveIndex = activeIndex
            
            print("   ✅ Updated tab data: \(self.currentTabs.count) tabs")
            print("   Tab names: \(self.currentTabs.map { $0.name }.joined(separator: ", "))")
            
            // Remove old tab bar
            flutterViewController.view.subviews.filter { $0.tag == 9994 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9994 {
                    child.removeFromParent()
                }
            }
            
            // Recreate with new data (active tab has close button)
            let tabBar = LiquidGlassTerminalTabBar(
                tabs: self.currentTabs,
                activeIndex: self.currentActiveIndex,
                onTabSelected: { index in
                    let channel = FlutterMethodChannel(name: "liquid_glass_tab_bar", binaryMessenger: flutterViewController.binaryMessenger)
                    channel.invokeMethod("onTabSelected", arguments: index)
                },
                onTabClosed: { index in
                    let channel = FlutterMethodChannel(name: "liquid_glass_tab_bar", binaryMessenger: flutterViewController.binaryMessenger)
                    channel.invokeMethod("onTabClosed", arguments: index)
                },
                onNewTab: {
                    // Simply forward to Flutter - debounce is handled on Flutter side
                    print("➕ [Swift] New tab button tapped, forwarding to Flutter")
                    let channel = FlutterMethodChannel(name: "liquid_glass_tab_bar", binaryMessenger: flutterViewController.binaryMessenger)
                    channel.invokeMethod("onNewTab", arguments: nil)
                },
                canAddTab: canAddTab
            )
            
            let hostingController = UIHostingController(rootView: AnyView(tabBar))
            hostingController.view.backgroundColor = UIColor.clear
            hostingController.view.tag = 9994
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            
            flutterViewController.addChild(hostingController)
            flutterViewController.view.addSubview(hostingController.view)
            
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.topAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: flutterViewController.view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor),
                // Let SwiftUI determine natural height - no fixed height constraint for "free balling" effect
            ])
            
            hostingController.didMove(toParent: flutterViewController)
            self.hostingController = hostingController
            
            print("   ✅ Tab bar recreated and added to view hierarchy")
            result(true)
        }
    }
    
    private func hideTabBar(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }
            
            flutterViewController.view.subviews.filter { $0.tag == 9994 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9994 {
                    child.removeFromParent()
                }
            }
            self.hostingController = nil
            
            result(true)
        }
    }
}

// ============================================================================
// MARK: - Terminal Input Bar (Bottom of Terminal Screen)
// ============================================================================

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
        let placeholder = args?["placeholder"] as? String ?? "Type commands here..."

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
        
        // Position above tab bar (matching ChatInput layout)
        let safeAreaBottom = window.safeAreaInsets.bottom
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let padding: CGFloat = isIPad ? 20 : 0
        let bottomOffset = 55 + safeAreaBottom + padding // Distance from bottom (above nav bar)
        let inputHeight: CGFloat = 64
        
        let constraint = hosting.view.bottomAnchor.constraint(equalTo: window.bottomAnchor, constant: -bottomOffset)
        self.bottomConstraint = constraint
        
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 20),
            hosting.view.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -20),
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
    
    init(placeholder: String, onSendCommand: ((String) -> Void)?, onInputChanged: ((String) -> Void)?, onDismissKeyboard: (() -> Void)?) {
        self.placeholder = placeholder
        self.onSendCommand = onSendCommand
        self.onInputChanged = onInputChanged
        self.onDismissKeyboard = onDismissKeyboard
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
}

// MARK: - Terminal Input View (Liquid Glass Style)

@available(iOS 26.0, *)
struct TerminalInputView: View {
    @ObservedObject var viewModel: TerminalInputViewModel
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var namespace
    
    var body: some View {
        // Content with Dismiss Button, TextField, and Send Button
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
    
    private var hasText: Bool {
        !viewModel.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}


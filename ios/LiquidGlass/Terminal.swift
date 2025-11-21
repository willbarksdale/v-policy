import UIKit
import Flutter
import SwiftUI
import Combine

// ============================================================================
// TERMINAL INPUT - iOS 26+ Liquid Glass
// ============================================================================
// Native iOS terminal input bar at the bottom of the terminal screen
// ============================================================================

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

// ============================================================================
// MARK: - Terminal Tabs (Top of Terminal Screen)
// ============================================================================

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

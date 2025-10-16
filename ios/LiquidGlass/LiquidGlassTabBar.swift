import UIKit
import Flutter
import SwiftUI

// MARK: - iOS 18 Liquid Glass Terminal Tab Bar

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
            if canAddTab && tabs.count < 5 {
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

// TabButton struct removed - now using simple circular buttons in LiquidGlassTerminalTabBar

// MARK: - Terminal Tab Info Model

struct TerminalTabInfo: Identifiable {
    let id: String
    let name: String
}

// MARK: - Liquid Glass Tab Bar Plugin

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
        switch call.method {
        case "isLiquidGlassSupported":
            result(true)
        case "showLiquidGlassTabBar":
            let args = call.arguments as? [String: Any]
                let tabsData = args?["tabs"] as? [[String: String]] ?? []
                let activeIndex = args?["activeIndex"] as? Int ?? 0
                let canAddTab = args?["canAddTab"] as? Bool ?? true
                showTabBar(tabsData: tabsData, activeIndex: activeIndex, canAddTab: canAddTab, result: result)
        case "hideLiquidGlassTabBar":
            hideTabBar(result: result)
        case "updateTabs":
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
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }
            
            // Update tab data
            self.currentTabs = tabsData.map { TerminalTabInfo(id: $0["id"] ?? "", name: $0["name"] ?? "") }
            self.currentActiveIndex = activeIndex
            
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


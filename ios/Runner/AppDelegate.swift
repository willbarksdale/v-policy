import Flutter
import UIKit

@main
@available(iOS 26.0, *)
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Register Liquid Glass navigation plugin
    VPolicyLiquidGlassNavPlugin.register(with: self.registrar(forPlugin: "VPolicyLiquidGlassNavPlugin")!)
    
    // Register Liquid Glass power button plugin
    SimpleLiquidGlassPowerButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassPowerButtonPlugin")!)
    
    // Register Liquid Glass info button plugin
    SimpleLiquidGlassInfoButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassInfoButtonPlugin")!)
    
    // Register Liquid Glass back button plugin
    SimpleLiquidGlassBackButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassBackButtonPlugin")!)
    
    // Register Liquid Glass play button plugin
    SimpleLiquidGlassPlayButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassPlayButtonPlugin")!)
    
    // Register Liquid Glass tab bar plugin
    LiquidGlassTabBarPlugin.register(with: self.registrar(forPlugin: "LiquidGlassTabBarPlugin")!)
    
    // Register Liquid Glass terminal input plugin
    LiquidGlassTerminalInputPlugin.register(with: self.registrar(forPlugin: "LiquidGlassTerminalInputPlugin")!)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

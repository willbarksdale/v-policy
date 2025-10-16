import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Register Liquid Glass navigation plugin
    if #available(iOS 16.0, *) {
      VPolicyLiquidGlassNavPlugin.register(with: self.registrar(forPlugin: "VPolicyLiquidGlassNavPlugin")!)
    }
    
    // Register Liquid Glass power button plugin
    if #available(iOS 16.0, *) {
      SimpleLiquidGlassPowerButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassPowerButtonPlugin")!)
    }
    
    // Register Liquid Glass info button plugin
    if #available(iOS 16.0, *) {
      SimpleLiquidGlassInfoButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassInfoButtonPlugin")!)
    }
    
    // Register Liquid Glass back button plugin
    if #available(iOS 16.0, *) {
      SimpleLiquidGlassBackButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassBackButtonPlugin")!)
    }
    
    // Register Liquid Glass play button plugin
    if #available(iOS 16.0, *) {
      SimpleLiquidGlassPlayButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassPlayButtonPlugin")!)
    }
    
    // Register Liquid Glass tab bar plugin
    if #available(iOS 16.0, *) {
      LiquidGlassTabBarPlugin.register(with: self.registrar(forPlugin: "LiquidGlassTabBarPlugin")!)
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

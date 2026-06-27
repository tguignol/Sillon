#if os(iOS)
import UIKit

/// AppDelegate minimal (iOS) : capture le completion handler du réveil en arrière-plan de la session
/// de téléchargement et le route vers le `DownloadManager`. Branché via `UIApplicationDelegateAdaptor`.
///
/// Sur macOS, ce mécanisme n'existe pas (pas de réveil d'app pour événements URLSession de fond) —
/// d'où le `#if os(iOS)`.
final class SillonAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        DownloadManager.shared?.backgroundCompletionHandler = completionHandler
    }
}
#endif

#if os(macOS)
import AppKit

/// AppDelegate macOS : **quitter l'app quand la dernière fenêtre est fermée**. L'utilisateur ne veut pas
/// que la lecture (ni quoi que ce soit) continue en arrière-plan, ni avoir à faire « Quit Sillon » :
/// fermer la fenêtre = fermer l'app, le processus se termine et le moteur audio s'arrête avec lui.
final class SillonMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif

import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramCore
import SwiftSignalKit
import AccountContext
import SwiftUI
import Translation
import TelegramUIPreferences

public func presentTranslateScreen(
    context: AccountContext,
    text: String,
    entities: [MessageTextEntity] = [],
    canCopy: Bool,
    fromLanguage: String?,
    toLanguage: String? = nil,
    isExpanded: Bool = false,
    ignoredLanguages: [String]? = nil,
    replaceText: ((String, [MessageTextEntity]) -> Void)? = nil,
    translateChat: ((String, String) -> Void)? = nil,
    pushController: @escaping (ViewController) -> Void = { _ in },
    presentController: @escaping (ViewController) -> Void = { _ in },
    wasDismissed: (() -> Void)? = nil,
    display: (ViewController) -> Void
) {
    let translationConfiguration = TranslationConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
    var useSystemTranslation = false
    switch translationConfiguration.manual {
    case .system:
        if #available(iOS 18.0, macCatalyst 26.0, *) {
            useSystemTranslation = true
        }
    default:
        break
    }
    
    if useSystemTranslation {
        presentSystemTranslateScreen(context: context, text: text)
    } else {
    }
}

private func presentSystemTranslateScreen(context: AccountContext, text: String) {
    if #available(iOS 18.0, macCatalyst 26.0, *), let rootViewController = context.sharedContext.mainWindow?.viewController?.view.window?.rootViewController {
        var dismissImpl: (() -> Void)?
        let pickerView = TranslateScreenHostingView(text: text, completionHandler: { [weak rootViewController] in
            DispatchQueue.main.async(execute: {
                guard let presentedController = rootViewController?.presentedViewController, presentedController.isBeingDismissed == false else { return }
                dismissImpl?()
            })
        })
        let hostingController = UIHostingController(rootView: pickerView)
        #if targetEnvironment(macCatalyst)
        hostingController.modalPresentationStyle = .pageSheet
        #else
        hostingController.view.isHidden = true
        hostingController.modalPresentationStyle = .overCurrentContext
        #endif
        rootViewController.present(hostingController, animated: true)
        dismissImpl = { [weak hostingController] in
            Queue.mainQueue().after(0.4, {
                hostingController?.dismiss(animated: false)
            })
        }
    }
}

#if targetEnvironment(macCatalyst)
@available(macCatalyst 26.0, *)
struct TranslateScreenHostingView: View {
    let text: String
    let handler: () -> Void
    @State private var result: String?
    @State private var failure: String?
    @State private var configuration: TranslationSession.Configuration?

    init(text: String, completionHandler: @escaping () -> Void) {
        self.text = text
        self.handler = completionHandler
        self._configuration = State(initialValue: .init(source: nil, target: Locale.current.language))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20.0) {
            Text("Translate").font(.title2)
            ScrollView {
                Text(text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                Divider().padding(.vertical)
                if let result {
                    Text(result).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                } else if let failure {
                    Text(failure).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            Button("Done", action: handler).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24.0)
        .frame(minWidth: 420.0, minHeight: 360.0)
        .translationTask(configuration) { session in
            do {
                result = try await session.translate(text).targetText
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
#else
@available(iOS 18.0, *)
struct TranslateScreenHostingView: View {
    @State var presented = true
    var text: String
    var handler: () -> Void
    
    init(text: String, completionHandler: @escaping () -> Void) {
        self.text = text
        self.handler = completionHandler
    }
    
    var body: some View {
        Spacer()
            .translationPresentation(
                isPresented: $presented,
                text: text
            )
            .onChange(of: presented) { newValue in
                if newValue == false {
                    handler()
                }
            }
    }
}
#endif

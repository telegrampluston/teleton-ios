import Foundation
import UIKit
import AppBundle
import AsyncDisplayKit
import Display
import SolidRoundedButtonNode
import SwiftSignalKit
import OverlayStatusController
import WalletCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import WalletContext

private final class WalletSettingsControllerArguments {
    let openConfiguration: () -> Void
    let exportWallet: () -> Void
    let deleteWallet: () -> Void
    
    init(openConfiguration: @escaping () -> Void, exportWallet: @escaping () -> Void, deleteWallet: @escaping () -> Void) {
        self.openConfiguration = openConfiguration
        self.exportWallet = exportWallet
        self.deleteWallet = deleteWallet
    }
}

private enum WalletSettingsSection: Int32 {
    case configuration
    case exportWallet
    case deleteWallet
}

private enum WalletSettingsEntry: ItemListNodeEntry {
    case configuration(PresentationTheme, String)
    case configurationInfo(PresentationTheme, String)
    case exportWallet(PresentationTheme, String)
    case deleteWallet(PresentationTheme, String)
    case deleteWalletInfo(PresentationTheme, String)
    
    var section: ItemListSectionId {
        switch self {
        case .configuration, .configurationInfo:
            return WalletSettingsSection.configuration.rawValue
        case .exportWallet:
            return WalletSettingsSection.exportWallet.rawValue
        case .deleteWallet, .deleteWalletInfo:
            return WalletSettingsSection.deleteWallet.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
        case .configuration:
            return 0
        case .configurationInfo:
            return 1
        case .exportWallet:
            return 2
        case .deleteWallet:
            return 3
        case .deleteWalletInfo:
            return 4
        }
    }
    
    static func <(lhs: WalletSettingsEntry, rhs: WalletSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WalletSettingsControllerArguments
        switch self {
        case let .configuration(_, text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openConfiguration()
            })
        case let .configurationInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .exportWallet(_, text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.exportWallet()
            })
        case let .deleteWallet(_, text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.deleteWallet()
            })
        case let .deleteWalletInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private struct WalletSettingsControllerState: Equatable {
}

private func walletSettingsControllerEntries(presentationData: PresentationData, state: WalletSettingsControllerState, supportsCustomConfigurations: Bool) -> [WalletSettingsEntry] {
    var entries: [WalletSettingsEntry] = []
    
    if supportsCustomConfigurations {
        entries.append(.configuration(presentationData.theme, presentationData.walletStrings.Wallet_Settings_Configuration))
        entries.append(.configurationInfo(presentationData.theme,presentationData.walletStrings.Wallet_Settings_ConfigurationInfo))
    }
    entries.append(.exportWallet(presentationData.theme, presentationData.walletStrings.Wallet_Settings_BackupWallet))
    entries.append(.deleteWallet(presentationData.theme, presentationData.walletStrings.Wallet_Settings_DeleteWallet))
    entries.append(.deleteWalletInfo(presentationData.theme, presentationData.walletStrings.Wallet_Settings_DeleteWalletInfo))

    return entries
}

public func walletSettingsController(context: WalletContext, walletInfo: WalletInfo, blockchainNetwork: LocalWalletConfiguration.ActiveNetwork) -> ViewController {
    let statePromise = ValuePromise(WalletSettingsControllerState(), ignoreRepeated: true)
    
    var presentControllerImpl: ((ViewController, Any?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    
    var replaceAllWalletControllersImpl: ((ViewController) -> Void)?
    
    let arguments = WalletSettingsControllerArguments(openConfiguration: {
        let _ = (context.storage.localWalletConfiguration()
        |> take(1)
        |> deliverOnMainQueue).start(next: { configuration in
            pushControllerImpl?(walletConfigurationScreen(context: context, currentConfiguration: configuration))
        })
    }, exportWallet: {
        let presentationData = context.presentationData
        let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
        presentControllerImpl?(controller, nil)
        let _ = (context.keychain.decrypt(walletInfo.encryptedSecret)
        |> deliverOnMainQueue).start(next: { [weak controller] decryptedSecret in
            let _ = (context.getServerSalt()
            |> deliverOnMainQueue).start(next: { serverSalt in
                let _ = (walletRestoreWords(tonInstance: context.tonInstance, publicKey: walletInfo.publicKey, decryptedSecret:  decryptedSecret, localPassword: serverSalt)
                |> deliverOnMainQueue).start(next: { [weak controller] wordList in
                    controller?.dismiss()
                    pushControllerImpl?(WalletWordDisplayScreen(context: context, blockchainNetwork: blockchainNetwork, walletInfo: walletInfo, wordList: wordList, mode: .export, walletCreatedPreloadState: nil))
                    }, error: { [weak controller] _ in
                        controller?.dismiss()
                })
            }, error: { [weak controller] _ in
                controller?.dismiss()
            })
        }, error: { [weak controller] _ in
            controller?.dismiss()
        })
    }, deleteWallet: {
        let presentationData = context.presentationData
        let actionSheet = ActionSheetController(theme: .init(presentationData: presentationData))
        actionSheet.setItemGroups([ActionSheetItemGroup(items: [
            ActionSheetTextItem(title: presentationData.walletStrings.Wallet_Settings_DeleteWalletInfo),
            ActionSheetButtonItem(title: presentationData.walletStrings.Wallet_Settings_DeleteWallet, color: .destructive, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                presentControllerImpl?(controller, nil)
                let _ = (deleteAllLocalWalletsData(storage: context.storage, tonInstance: context.tonInstance)
                |> deliverOnMainQueue).start(error: { [weak controller] _ in
                    controller?.dismiss()
                }, completed: { [weak controller] in
                    controller?.dismiss()
                    replaceAllWalletControllersImpl?(WalletSplashScreen(context: context, blockchainNetwork: blockchainNetwork, mode: .intro, walletCreatedPreloadState: nil))
                })
            })
        ]), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.walletStrings.Wallet_Navigation_Cancel, color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, nil)
    })
    
    let signal = combineLatest(queue: .mainQueue(), .single(context.presentationData), statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: .init(presentationData), title: .text(presentationData.walletStrings.Wallet_Settings_Title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.walletStrings.Wallet_Navigation_Back))
        let listState = ItemListNodeState(presentationData: .init(presentationData), entries: walletSettingsControllerEntries(presentationData: presentationData, state: state, supportsCustomConfigurations: context.supportsCustomConfigurations), style: .blocks, animateChanges: false)
        
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
    }
    let updatedPresentationData = context.presentationDataSignal |> map { ItemListPresentationData($0) }
    let controller = ItemListController(presentationData: .init(context.presentationData), updatedPresentationData: updatedPresentationData, state: signal, tabBarItem: nil)
    controller.navigationPresentation = .modal
    controller.enableInteractiveDismiss = true
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    replaceAllWalletControllersImpl = { [weak controller] c in
        if let navigationController = controller?.navigationController as? NavigationController {
            var controllers = navigationController.viewControllers
            controllers = controllers.filter { listController in
                if listController === controller {
                    return false
                }
                if listController is WalletInfoScreen {
                    return false
                }
                return true
            }
            controllers.append(c)
            navigationController.setViewControllers(controllers, animated: true)
        }
    }
    
    return controller
}

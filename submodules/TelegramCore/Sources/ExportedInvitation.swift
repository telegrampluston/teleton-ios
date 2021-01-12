import Foundation
import Postbox
import TelegramApi

import SyncCore

extension ExportedInvitation {
    init?(apiExportedInvite: Api.ExportedChatInvite) {
        switch apiExportedInvite {
            case .chatInviteEmpty:
                return nil
            case let .chatInviteExported(flags, link, adminId, date, expireDate, usageLimit, usage):
                self = ExportedInvitation(link: link)
        }
    }
}

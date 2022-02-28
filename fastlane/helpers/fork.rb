#!/usr/bin/ruby

class Fork
  
  TeamId = 'ZDYX45DG63'
  
  class AppIdentifier
    Development = "io.teleton.app"
    Production = 'XXXXXXXXXXX'
  end

  class WidgetIdentifier
    Development = "io.teleton.app.Widget"
  end

  class ShareIdentifier
    Development = "io.teleton.app.Share"
  end

  class SiriIdentifier
    Development = "io.teleton.app.SiriIntents"
  end

  class NotificationContentIdentifier
    Development = "io.teleton.app.NotificationContent"
  end

  class NotificationServiceIdentifier
    Development = "io.teleton.app.NotificationService"
  end

  class WatchIdentifier
    Development = "io.teleton.app.watchkitapp"
  end

  class WatchExtIdentifier
    Development = "io.teleton.app.watchkitapp.watchkitextension"
  end

  class BroadcastUploadIdentifier
      Development = "io.teleton.app.BroadcastUpload"
  end
end

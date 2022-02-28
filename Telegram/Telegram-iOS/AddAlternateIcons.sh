set -euo pipefail

# ADD_PLIST="${0}.runfiles/__main__/Telegram/Telegram-iOS/AlternateIcons.plist" Fork Commented
# ADD_PLIST_IPAD="${0}.runfiles/__main__/Telegram/Telegram-iOS/AlternateIcons-iPad.plist" Fork Commented

#Fork
FORK_ADD_PLIST="${0}.runfiles/__main__/Telegram/Telegram-iOS/ForkAlternateIcons.plist"
FORK_ADD_PLIST_IPAD="${0}.runfiles/__main__/Telegram/Telegram-iOS/ForkAlternateIcons-iPad.plist"


if [ -f "$1/Payload/Telegram.app/Info.plist" ]; then
    INFO_PLIST="$1/Payload/Telegram.app/Info.plist"
else
    INFO_PLIST="$1/Telegram.app/Info.plist"
fi

/usr/libexec/PlistBuddy -c "add :CFBundleIcons:CFBundleAlternateIcons dict" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "add :CFBundleIcons~ipad:CFBundleAlternateIcons dict" "$INFO_PLIST"

# /usr/libexec/PlistBuddy -c "merge $ADD_PLIST :CFBundleIcons:CFBundleAlternateIcons" "$INFO_PLIST" Fork Commented
# /usr/libexec/PlistBuddy -c "merge $ADD_PLIST_IPAD :CFBundleIcons~ipad:CFBundleAlternateIcons" "$INFO_PLIST" Fork Commented

#Fork
/usr/libexec/PlistBuddy -c "merge $FORK_ADD_PLIST :CFBundleIcons:CFBundleAlternateIcons" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "merge $FORK_ADD_PLIST_IPAD :CFBundleIcons~ipad:CFBundleAlternateIcons" "$INFO_PLIST"

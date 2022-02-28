#!/bin/bash
for f in build-system/fork-configuration/development/provisioning/*.mobileprovision
do 
newFilename=$(echo $f | sed -e 's/Development_io.teleton.app.mobileprovision/Telegram.mobileprovision/' | sed -e 's/Development_io.teleton.app.//g' | sed -e 's/watchkitapp.watchkitextension./WatchExtension./' | sed -e 's/watchkitapp./WatchApp./' | sed -e 's/SiriIntents./Intents./' | sed -e 's/watchkitapp.watchkitextension./WatchExtension./')
echo ${newFilename%}
echo ${f%}
mv -f ${f%} ${newFilename%}
done

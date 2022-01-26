#!/bin/bash
set -ex
commitHash=$(echo $git_commit_hash | cut -c1-7)
echo "current git hash:$commitHash"
echo "uploading app apk to browserstack"
upload_app_response="$(curl -u $browserstack_username:$browserstack_access_key -X POST https://api-cloud.browserstack.com/app-automate/upload -F file=@$app_apk_path)"
app_url=$(echo "$upload_app_response" | jq .app_url)

echo "uploading test apk to browserstack"
upload_test_response="$(curl -u $browserstack_username:$browserstack_access_key -X POST https://api-cloud.browserstack.com/app-automate/espresso/test-suite -F file=@$test_apk_path)"
test_url=$(echo "$upload_test_response" | jq .test_url)

echo "starting automated tests"
json=$( jq -n \
                --argjson app_url $app_url \
                --argjson test_url $test_url \
                --argjson project "$browserstack_project" \
                --argjson devices ["$browserstack_device_list"] \
                --argjson package ["$browserstack_package"] \
                --argjson annotation ["$browserstack_annotation"] \
                --arg size "$browserstack_size" \
                --arg logs "$browserstack_device_logs" \
                --arg video "$browserstack_video" \
                --arg screenshot "$enable_spoon_framework" \
		            --arg loc "$browserstack_local" \
                --arg locId "$browserstack_local_identifier" \
                --arg gpsLocation "$browserstack_gps_location" \
                --arg language "$browserstack_language" \
                --arg locale "$browserstack_locale" \
                --arg callback "$callback_url?hash=$commitHash" \
                '{devices: $devices, app: $app_url, testSuite: $test_url, project: $project, package: $package, annotation: $annotation, size: $size, logs: $logs, enableSpoonFramework: $screenshot, video: $video, local: $loc, localIdentifier: $locId, gpsLocation: $gpsLocation, language: $language, callbackURL: $callback,locale: $locale, deviceLogs: true, networkLogs: true, singleRunnerInvocation: true}')
run_test_response="$(curl -X POST https://api-cloud.browserstack.com/app-automate/espresso/build -d \ "$json" -H "Content-Type: application/json" -u "$browserstack_username:$browserstack_access_key")"
build_id=$(echo "$run_test_response" | jq .build_id | sed 's/"//g')
envman add --key BROWSERSTACK_BUILD_ID --value "$build_id"
echo "build id: $build_id"

echo "monitor build state"
get_build_status_response="$(curl -u $browserstack_username:$browserstack_access_key -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id")"
build_status=$(echo "$get_build_status_response" | jq .status)
echo "build status: $build_status"
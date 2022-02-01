#!/bin/bash
set -e
echo "Uploading app apk to browserstack"
# shellcheck disable=SC2154
upload_app_response="$(curl -u "$browserstack_username":"$browserstack_access_key" -X POST https://api-cloud.browserstack.com/app-automate/upload -F file=@"$app_apk_path")"
app_url=$(echo "$upload_app_response" | jq .app_url)

echo "Uploading test apk to browserstack"
# shellcheck disable=SC2154
upload_test_response="$(curl -u "$browserstack_username":"$browserstack_access_key" -X POST https://api-cloud.browserstack.com/app-automate/espresso/test-suite -F file=@"$test_apk_path")"
test_url=$(echo "$upload_test_response" | jq .test_url)

echo "Starting automated tests"
# shellcheck disable=SC2154
json=$(jq -n \
  --argjson app_url "$app_url" \
  --argjson test_url "$test_url" \
  --argjson devices ["$browserstack_device_list"] \
  --argjson class ["$browserstack_class"] \
  --argjson package ["$browserstack_package"] \
  --argjson annotation ["$browserstack_annotation"] \
  --arg size "$browserstack_size" \
  --arg logs "$browserstack_device_logs" \
  --arg video "$browserstack_video" \
  --arg screenshot "$browserstack_screenshot" \
  --arg loc "$browserstack_local" \
  --arg locId "$browserstack_local_identifier" \
  --arg gpsLocation "$browserstack_gps_location" \
  --arg language "$browserstack_language" \
  --arg locale "$browserstack_locale" \
  '{app: $app_url, testSuite: $test_url, devices: $devices, class: $class, package: $package, annotation: $annotation, size: $size, deviceLogs: $logs, networkLogs: $logs, video: $video, enableSpoonFramework: $screenshot, local: $loc, localIdentifier: $locId, gpsLocation: $gpsLocation, language: $language, locale: $locale}')

run_test_response="$(curl -X POST https://api-cloud.browserstack.com/app-automate/espresso/build -d \ "$json" -H "Content-Type: application/json" -u "$browserstack_username:$browserstack_access_key")"
build_id=$(echo "$run_test_response" | jq .build_id | sed 's/"//g')
session_id=$(curl -u "$browserstack_username":"$browserstack_access_key" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id" | jq '.devices[].sessions[].id' | sed 's/"//g')
envman add --key BROWSERSTACK_BUILD_ID --value "$build_id"
envman add --key BROWSERSTACK_SESSION_ID --value "$session_id"

function getBuildStatus() {
  curl -u "$browserstack_username":"$browserstack_access_key" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id" | jq .status | sed 's/"//g'
}

echo "---Monitor build state---"
until [[ "$(getBuildStatus)" != "running" ]]; do
  echo "Automation is running......"
  sleep 60s
done
echo "---Automation $(getBuildStatus)!---"

echo "---Wait for report---"
echo "Build id: $build_id"
echo "Session id: $session_id"
sleep 60s

echo "---Save report---"
curl -u "$browserstack_username":"$browserstack_access_key" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id/sessions/$session_id/report" > $BITRISE_DEPLOY_DIR/report.xml

echo "---Save video---"
curl -o $BITRISE_DEPLOY_DIR/video.mp4 "https://www.browserstack.com/s3-upload/bs-video-logs-use/s3/$session_id/video-$session_id.mp4"

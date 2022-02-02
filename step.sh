#!/bin/bash
set -e

echo "Uploading app apk to browserstack"
# shellcheck disable=SC2154
upload_app_response="$(curl -u "$username:$access_key" -X POST "https://api-cloud.browserstack.com/app-automate/espresso/v2/app" -F "file=@$app_apk_path")"
app_url=$(echo "$upload_app_response" | jq .app_url)
echo "App URL: $app_url"

echo "Uploading test apk to browserstack"
# shellcheck disable=SC2154
upload_test_response="$(curl -u "$username:$access_key" -X POST "https://api-cloud.browserstack.com/app-automate/espresso/v2/test-suite" -F "file=@$test_apk_path")"
test_url=$(echo "$upload_test_response" | jq .test_url)
echo "Test URL: $test_url"

echo "Starting automated tests"
# shellcheck disable=SC2154
json=$(jq -n \
  --argjson app_url "$app_url" \
  --argjson test_url "$test_url" \
  --argjson devices ["$bs_device_list"] \
  --argjson class ["$bs_class"] \
  --argjson package ["$bs_package"] \
  --argjson annotation ["$bs_annotation"] \
  --arg size "$bs_size" \
  --arg logs "$bs_logs" \
  --arg video "$bs_video" \
  --arg screenshot "$bs_screenshot" \
  --arg loc "$bs_local" \
  --arg locId "$bs_local_identifier" \
  --arg gpsLocation "$bs_gps_location" \
  --arg language "$bs_language" \
  --arg locale "$bs_locale" \
  '{app: $app_url, testSuite: $test_url, devices: $devices, class: $class, package: $package, annotation: $annotation, size: $size, deviceLogs: $logs, networkLogs: $logs, video: $video, enableSpoonFramework: $screenshot, local: $loc, localIdentifier: $locId, gpsLocation: $gpsLocation, language: $language, locale: $locale}')

run_test_response="$(curl -u "$username:$access_key" -X POST "https://api-cloud.browserstack.com/app-automate/espresso/build" -d \ "$json" -H "Content-Type: application/json")"
build_id=$(echo "$run_test_response" | jq .build_id | sed 's/"//g')
echo "Build id: $build_id"

function getBuildStatus() {
  curl -u "$username:$access_key" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id" | jq .status | sed 's/"//g'
}

function getSessionStatus() {
  curl -u "$username:$access_key" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id" | jq .devices[].sessions[].status | sed 's/"//g'
}

while [[ "$(getSessionStatus)" != "running" ]]; do
  echo "Waiting for session ID......"
  sleep 5s
done

session_id="$(curl -u "$username:$access_key" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id" | jq .devices[].sessions[].id | sed 's/"//g')"

echo "Build id: $build_id"
echo "Session id: $session_id"
envman add --key BROWSERSTACK_BUILD_ID --value "$build_id"
envman add --key BROWSERSTACK_SESSION_ID --value "$session_id"

function getSessionResponse() {
  curl -u "$username:$access_key" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id/sessions/$session_id"
}

echo "---Monitor build state---"
while [[ "$(getBuildStatus)" == "running" ]]; do
  echo "Automation is running......"
  sleep 60s
done

echo "---Automation $(getBuildStatus)!---"

echo "---Save report---"
curl -u "$username:$access_key" -o "$BITRISE_DEPLOY_DIR/report.xml" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id/sessions/$session_id/report"

echo "---Save video---"
video_link="https://www.browserstack.com/s3-upload/bs-video-logs-use/s3/$session_id/video-$session_id.mp4"
curl -o "$BITRISE_DEPLOY_DIR/video.mp4" "$video_link"

echo "---Save env vars---"
session_response=$(getSessionResponse)
test_all=$($session_response | jq .testcases.count)
test_failed=$($session_response | jq .testcases.status.passed)
echo "Test all: $test_all"
echo "Test failed: $test_failed"
envman add --key BS_TEST_ALL --value "$build_id"
envman add --key BS_TEST_FAILED --value "$session_id"
envman add --key BS_VIDEO_URL --value "$video_link"
envman add --key BS_EXECUTION_URL --value "https://app-automate.browserstack.com/dashboard/v2/builds/$build_id"

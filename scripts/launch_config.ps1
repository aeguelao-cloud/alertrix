@{
  # Cloud API from your deployed backend stack output.
  ApiBaseUrl = "https://b4sm23mlze.execute-api.ap-southeast-5.amazonaws.com/prod"

  # Flutter web runtime config.
  WebPort = 18082
  Device = "web-server"
  EnableWebFcm = $true
  UseFreshChromeProfile = $true
  ChromeUserDataDir = "F:\\403\\demo\\.chrome_fcm_profile"
  DisableChromeExtensions = $true

  # Optional Firebase/FCM values (keep empty if not needed).
  FirebaseApiKey = "AIzaSyCdaebCdME_g0QDjFYhysnQUpvEqlcmW3w"
  FirebaseAppId = "1:509883742045:web:a755fe97ce4aa0c5c99ab4"
  FirebaseMessagingSenderId = "509883742045"
  FirebaseProjectId = "alertrix-eb014"
  FirebaseStorageBucket = "alertrix-eb014.firebasestorage.app"
  FirebaseAuthDomain = "alertrix-eb014.firebaseapp.com"
  # Set this to your Firebase Web Push certificate key (VAPID public key).
  # If empty, web getToken may fail on some browsers.
  FcmWebVapidKey = "BNNhmKgShm2p2SYFBymJwGWnrmt_o-i9AKG3weWEll2cfraqH1CgGbimMaaGvI5jodCxC6DGY9ITd2_a2SV3swg"
}

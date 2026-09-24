# L11 iOS privacy check

Run on a signed iOS development build before P1 participant data.

- Use a synthetic capture with a unique sentinel. Move the app to the app switcher, then verify the snapshot and return animation do not show the sentinel or any private loop text.
- Repeat while the keyboard is open and during an interruption such as Control Center or an incoming call.
- Force the native app switcher protection call to fail in a test build; verify the app remains covered.
- After logout, consent withdrawal, and account deletion, verify the app has no Raw in its visible state. Inspect sanitized application and Edge logs for the sentinel, Expo token, prompt, and response text; each must have zero matches.
- Record device, iOS/build version, date, result, and reviewer. Do not use participant Raw in the check.

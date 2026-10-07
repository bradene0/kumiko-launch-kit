# App Store submission checklist

What we check before sending a Mac or iPhone build to App Review. It comes from shipping App Archaeology to the Mac App Store in September and October 2026, including two rejections. App Store Connect changes over time, so treat menu names as a guide and Apple's current documentation as the authority.

## 1. Before you archive

- [ ] Unit tests and UI tests pass on a Release-like build.
- [ ] **Test on the newest OS that reviewers use.** Our first design rejection only showed up on macOS 26, whose sidebar and toolbar chrome differ from earlier versions.
- [ ] **Check every window and sheet at its minimum size, in light and dark.** App Review rejects text that is cut off (Guideline 4, Design). Fixing only the screen in their screenshot isn't enough; sweep the whole app.
- [ ] Debug-only code is really Debug-only. If you use a screenshot or demo mode, a Release build must contain none of it: `strings <binary> | grep UITest` should print nothing.
- [ ] Entitlements are only the ones you need, and every permission prompt your app triggers has a clear reason in the app and in the review notes.
- [ ] Bump the build number (`CURRENT_PROJECT_VERSION`). Bump the version (`MARKETING_VERSION`) for a new public release.
- [ ] Commit and push, so the build you upload matches a commit.

## 2. Signing, archive and upload (Xcode)

- [ ] Xcode › Settings › Apple Accounts shows your team, with a role that can upload (Admin or Account Holder).
- [ ] Signing & Capabilities: automatic signing, the right team, no errors.
- [ ] Destination is a generic device (**Any Mac** or **Any iOS Device**). If **Product › Archive** is greyed out, the destination is still a specific Mac or simulator.
- [ ] Product › Archive, then **Validate App** in the Organizer. Fix every error before uploading.
- [ ] **Distribute App** › App Store Connect › Upload. Wait for the "finished processing" email (often 10 to 30 minutes).

Common errors:
- "No signing certificate" or "no account for team": Settings › Apple Accounts › Manage Certificates › add the distribution certificates.
- "Cloud signing permission error": your role isn't high enough; the Account Holder changes it in Users and Access.

## 3. App Store Connect listing

- [ ] Select the new build on the version page, and remove the old one.
- [ ] Screenshots match the current UI, at sizes App Store Connect accepts, as opaque PNGs (no alpha channel). `AppStoreScreenshots/` checks all three.
  - Mac: 1280×800, 1440×900, 2560×1600 or 2880×1800.
  - iPhone 6.9": 1320×2868, 1290×2796 or 1260×2736 (or 6.5": 1284×2778, 1242×2688).
- [ ] Demo content in screenshots is fictional: invented names, fixed dates, and no other companies' names, logos or trademarks (Guideline 5.2).
- [ ] The app icon is your own artwork. Apple's SF Symbols license doesn't allow symbols in app icons or logos. `AppIconKit/` rejects the obvious cases.
- [ ] Keywords don't repeat the category name or the app name, and don't use other companies' trademarks.
- [ ] App Privacy answers match what the app actually does.
- [ ] Accessibility declarations only claim what you've verified (for example Dark Interface, or VoiceOver after a manual pass).

## 4. Notes for the reviewer

- [ ] **If you attach a screen recording, say so in the first line of the notes.** A reviewer missed our attached video and rejected the build asking for one.
- [ ] Record the real app, not a demo or screenshot mode, on a current OS.
- [ ] Explain every permission prompt, any account or sign-in (or say none is needed), and anything a reviewer might not find on their own.
- [ ] Choose manual or automatic release, Save, then **Add for Review**.

## 5. If App Review rejects the build

1. Read the message and download any attachment. Their screenshot shows the reviewer's device and OS version.
2. Reproduce it exactly, on that OS version, in the same state.
3. Fix every instance of the problem, not just the one they showed.
4. Add a test that fails without the fix, so it can't come back.
5. Upload a new build. You don't need to cancel the submission: on the submission page, choose **Edit**, select the new build and **Save**.
6. Reply in the same thread with the cause, the fix, how you verified it, and the new build number. Attach a fresh recording if behavior changed.
7. Update the review notes, then **Update Review** or **Resubmit to App Review**. If the button is greyed out, open the version page, Save, and read any red banner.
8. Write down what happened and why, so the next release avoids it.

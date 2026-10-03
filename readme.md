# Audiobookshelf clients

This fork maintains the Next.js browser client in `web/`, the SwiftUI Apple clients in
`apple/` and `tvos/`, and the native Android client in `android-native/`. Builds, signing
and internal delivery run locally. Connect them to your existing Audiobookshelf server.

## Browser entrypoints

Use Node.js 22 or later. From the repository root:

```sh
npm ci --prefix web
npm run dev
# Production build and local start:
npm run build
npm run start
```

The default port is 19881. Arguments pass through, for example `npm run dev -- --port 19901`.
Set `ABS_WEB_BASE_PATH=/web` for both build and local start when using the documented subpath deployment.
See [web/README.md](web/README.md) and [self-hosted deployment](web/docs/DEPLOYMENT.md).
The upstream server's Vue administration interface remains unchanged.

## Native builds and recovery

Use the maintained [Apple](apple/README.md), [TV](tvos/README.md) and
[Android](android-native/HANDOFF.md) entrypoints, with root coordinating signing,
installation and internal distribution. Never replace the upstream app before migration
and rollback are validated.

The Nuxt/Capacitor fork is retained for recovery and migration export. It is no longer the
default client or a hosted build target. Its source, dependencies, native shells, artifacts,
[GPL license](LICENSE), upstream attribution and third-party notices remain intact.
See [legacy recovery and export](docs/modernization/LEGACY-RECOVERY.md) for the pinned tag,
explicit `legacy:*` commands, reauthentication, native import and rollback.

<details>
<summary>Historical upstream Nuxt/Capacitor client documentation</summary>

The following upstream instructions describe the retained legacy client and public upstream
apps. They are historical information, not this fork's delivery or maintenance entrypoints.
Run recovery commands only in a separate recovery checkout.

# Audiobookshelf Mobile App

Audiobookshelf is a self-hosted audiobook and podcast server.

### Android (beta)

Get the Android app on the [Google Play Store](https://play.google.com/store/apps/details?id=com.audiobookshelf.app)

### iOS (early beta)

**Beta is currently full. Apple has a hard limit of 10k beta testers. Updates will be posted in Discord.**

Using Test Flight: https://testflight.apple.com/join/wiic7QIW **_(beta is full)_**

---

[Go to the main project repo github.com/advplyr/audiobookshelf](https://github.com/advplyr/audiobookshelf) or the project site [audiobookshelf.org](https://audiobookshelf.org)

Join us on [discord](https://discord.gg/pJsjuNCKRq)

**Requires an Audiobookshelf server to connect with**

<img alt="Screenshot" src="https://github.com/advplyr/audiobookshelf-app/raw/master/screenshots/DeviceDemoScreens.png" />

## Contributing

This application is built using [NuxtJS](https://nuxtjs.org/) and [Capacitor](https://capacitorjs.com/) in order to run on both iOS and Android on the same code base.

### Localization

Thank you to [Weblate](https://hosted.weblate.org/engage/audiobookshelf/) for hosting our localization infrastructure pro-bono. If you want to see Audiobookshelf in your language, please help us localize. Additional information on helping with the translations [here](https://www.audiobookshelf.org/faq#how-do-i-help-with-translations). <a href="https://hosted.weblate.org/engage/audiobookshelf/"> <img src="https://hosted.weblate.org/widget/audiobookshelf/abs-mobile-app/horizontal-auto.svg" alt="Translation status" /> </a>

### Windows Environment Setup for Android

Required Software:

- [Git](https://git-scm.com/downloads)
- [Node.js](https://nodejs.org/en/) (version 20)
- Code editor of choice([VSCode](https://code.visualstudio.com/download), etc)
- [Android Studio](https://developer.android.com/studio)
- [Android SDK](https://developer.android.com/studio)

<details>
<summary>Install the required software with <a href=(https://docs.microsoft.com/en-us/windows/package-manager/winget/#production-recommended)>winget</a></summary>

<p>
Note: This requires a PowerShell prompt with winget installed.  You should be able to copy and paste the code block to install.  If you use an elevated PowerShell prompt, UAC will not pop up during the installs.

```PowerShell
winget install -e --id Git.Git; `
winget install -e --id Microsoft.VisualStudioCode; `
winget install -e --id  Google.AndroidStudio; `
winget install -e --id OpenJS.NodeJS --version 20.11.0;
```

![](/screenshots/dev_setup_windows_winget.png)

</p>
</details>
<br>

Your Windows environment should now be set up and ready to proceed!

### Mac Environment Setup for Android

Required Software:

- [Android Studio](https://developer.android.com/studio)
- [Node.js](https://nodejs.org/en/) (version 20)
- [Cocoapods](https://guides.cocoapods.org/using/getting-started.html#installation)
- [Android SDK](https://developer.android.com/studio)

<details>
<summary>Install the required software with <a href=(https://brew.sh/)>homebrew</a></summary>

<p>

```zsh
brew install android-studio node cocoapods
```

</p>
</details>

### Start working on the Android app

Clone or fork the project from terminal or powershell and `cd` into the project directory.

Install the required node packages:

```shell
npm install
```

<details>
<summary>Expand for screenshot</summary>

![](/screenshots/dev_setup_android_npm_install.png)

</details>
<br>

Generate static web app:

```shell
npm run legacy:generate
```

<details>
<summary>Expand for screenshot</summary>

![](/screenshots/dev_setup_android_npm_run.png)

</details>
<br>

Copy web app into native android/ios folders:

```shell
npm run legacy:sync
```

<details>
<summary>Expand for screenshot</summary>

![](/screenshots/dev_setup_android_cap_sync.png)

</details>
<br>

Open Android Studio:

```shell
npm run legacy:open-android
```

<details>
<summary>Expand for screenshot</summary>

![](/screenshots/dev_setup_cap_android.png)

</details>
<br>

Start coding!

After making changes to the JS layer you need to rebuild the nuxt pages and sync them to the native shells:

```shell
npm run legacy:sync
```

### Mac Environment Setup for iOS

Required Software:

- [Xcode](https://developer.apple.com/xcode/)
- [Node.js](https://nodejs.org/en/)
- [Cocoapods](https://guides.cocoapods.org/using/getting-started.html#installation)

### Start working on the iOS app

Clone or fork the project in the terminal and `cd` into the project directory.

Install the required node packages:

```shell
npm install
```

<details>
<summary>Expand for screenshot</summary>

![](/screenshots/dev_setup_ios_npm_install.png)

</details>
<br>

Generate static web app:

```shell
npm run legacy:generate
```

<details>
<summary>Expand for screenshot</summary>

![](/screenshots/dev_setup_ios_npm_generate.png)

</details>
<br>

Copy web app into native android/ios folders:

```shell
npm run legacy:sync
```

<details>
<summary>Expand for screenshot</summary>

![](/screenshots/dev_setup_ios_cap_sync.png)

</details>
<br>

Open Xcode:

```shell
npm run legacy:open-ios
```

<details>
<summary>Expand for screenshot</summary>

![](/screenshots/dev_setup_ios_cap_open.png)

</details>
<br>

Start coding!

After making changes to the JS layer you need to rebuild the nuxt pages and sync them to the native shells:

```shell
npm run legacy:sync
```

</details>

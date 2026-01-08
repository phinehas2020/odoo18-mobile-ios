# MobileOdoo iOS App

## Build
This repo uses XcodeGen.

1. Install XcodeGen
2. Generate the project:

```
xcodegen generate
```

3. Open `MobileOdoo.xcodeproj` in Xcode.

## Run
- Set the development team in the project settings.
- Configure the server URL and database on the login screen.
- If multiple companies are returned, select the active company when prompted.

## Notes
- Push requires a valid APNS key and bundle identifier that matches the app.
- Camera permissions are declared in `MobileApp/Info.plist`.
- UI smoke tests live in `MobileOdooUITests`.

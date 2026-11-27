# MousePlus

MousePlus opens a radial menu at the pointer on macOS 14 and later.

## Project folders

| Folder | Contents |
| --- | --- |
| `01_Project/` | Xcode workspace, app source, asset catalog, tests, and build configuration |
| `02_Design/` | Original artwork and app icon concepts |
| `04_Exports/` | Current local installer, with older installers in `Archive/` |
| `build/` | Local app bundles and builds kept for testing |
| `docs/` | Project status, decisions, and session handoffs |
| `specs/` | Feature specifications |

On a Mac with local exports, open the DMG directly inside `04_Exports/`. Name new installers
`MousePlus-<version>-<build>.dmg` using the version and build number from the app bundle.
Give each new installer build its own number and move the previous installer to `Archive/`.
These local artifacts are excluded from Git.

## Development

Open [the Xcode workspace](01_Project/MousePlus.xcworkspace) and select the MousePlus scheme.
The app source lives in [01_Project/MousePlus](01_Project/MousePlus), and signing settings
and entitlements live in [01_Project/Config](01_Project/Config). The workspace uses Swift
Package Manager for dependencies. MousePlus runs outside the App Sandbox so it can monitor
global triggers and access other apps’ menus.

## Notes

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted macOS development workflows.

## License

MousePlus is licensed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE).

This is a copyleft license: forks and derivative works must also be released under GPLv3 with source code available. The choice of GPLv3 (rather than MIT) reflects the project goal of preventing closed-source commercial forks while keeping the source open for anyone to study, modify, and redistribute.
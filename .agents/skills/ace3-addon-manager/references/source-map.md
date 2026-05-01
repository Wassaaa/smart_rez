# Ace3 Source Map

## Core sources

- Overview: https://www.wowace.com/projects/ace3
- Getting Started: https://www.wowace.com/projects/ace3/pages/getting-started
- GitHub mirror: https://github.com/WoWUIDev/Ace3
- Primary packaging authority for `.pkgmeta`: https://repos.wowace.com/wow/ace3/trunk

## Research snapshot

- As of 2026-04-01, the WowAce overview page listed Retail `Release-r1390` dated 2026-02-03 and `r1391-alpha` dated 2026-03-06.
- Treat that as a snapshot, not a permanent fact. If the user asks for the latest release, latest docs, or current packaging details, browse the official overview again.
- The GitHub mirror README says the WowAce SVN remains the primary authority for packaging and recommends referencing only the specific Ace3 libraries you use.

## Tutorials and guides

- AceConfig options tables: https://www.wowace.com/projects/ace3/pages/ace-config-3-0-options-tables
- AceDB tutorial: https://www.wowace.com/projects/ace3/pages/ace-db-3-0-tutorial
- AceGUI tutorial: https://www.wowace.com/projects/ace3/pages/ace-gui-3-0-tutorial
- AceGUI widgets: https://www.wowace.com/projects/ace3/pages/ace-gui-3-0-widgets

## API pages

- AceAddon-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-addon-3-0
- AceBucket-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-bucket-3-0
- AceComm-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-comm-3-0
- AceConfig-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-config-3-0
- AceConfigCmd-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-config-cmd-3-0
- AceConfigDialog-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-config-dialog-3-0
- AceConfigRegistry-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-config-registry-3-0
- AceConsole-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-console-3-0
- AceDB-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-db-3-0
- AceDBOptions-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-dboptions-3-0
- AceEvent-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-event-3-0
- AceGUI-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-gui-3-0
- AceHook-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-hook-3-0
- AceLocale-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-locale-3-0
- AceSerializer-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-serializer-3-0
- AceTab-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-tab-3-0
- AceTimer-3.0: https://www.wowace.com/projects/ace3/pages/api/ace-timer-3-0

## Notes

- `AceConfig-3.0` is a wrapper around the config subcomponents. If the addon embeds the top-level AceConfig XML, it typically pulls in `AceConfigRegistry-3.0`, `AceConfigCmd-3.0`, and `AceConfigDialog-3.0`.
- `AceTab-3.0` has sparse docs, and the official API page says it is not yet finalized. Inspect current source before relying on it in a new addon.

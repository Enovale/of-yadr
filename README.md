[![Nightly Build](https://github.com/Enovale/of-yadr/workflows/Nightly%20Build/badge.svg)](https://github.com/Enovale/of-yadr/actions?query=workflow:"Nightly+Build")
[![GitHub release](https://img.shields.io/github/release/Enovale/of-yadr?include_prereleases=&sort=semver&color=blue)](https://github.com/Enovale/of-yadr/releases/)
[![License](https://img.shields.io/badge/License-GPLv3-blue)](#license)

# Yet Another Discord Relay for SourceMod

Proper readme WIP

> [!WARNING]  
> This project has only been tested with Open Fortress on Sourcemod 1.12.
> A few features will NOT work on SM 1.11.
> Absolutely no testing has been done with other configurations, though they should theoretically work.
> I would love reports to be made in the Issues section if issues are found in other games/setups

Until 1.0.0, the Translation format will break FREQUENTLY, and this can cause sensitive info to be leaked accidentally.

## Screenshots

![Basic Usage Screenshot](https://github.com/user-attachments/assets/8f4ccd97-7417-4480-923b-4799161ed06c)  
![Status Command Screenshot](https://github.com/user-attachments/assets/ea573787-1426-43fb-86f7-3e29be0af75c)

## Requirements

- Sourcemod 1.12+ is required.
- [sm-ext-discord](https://github.com/ProjectSky/sm-ext-discord) (You can download the latest version [here](https://github.com/ProjectSky/sm-ext-discord/actions/workflows/ci.yml)).
- [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556)
- [log4sp](https://github.com/F1F88/sm-ext-log4sp)
- [Chat Processor](https://github.com/KeithGDR/chat-processor)
- [More Colors](https://forums.alliedmods.net/showthread.php?t=185016)
- [SourceBans++](https://github.com/sbpp/sourcebans-pp) (Optional)
- [Updater](https://forums.alliedmods.net/showthread.php?t=169095) (Optional)

## Quick Start

Download the latest [release](https://github.com/Enovale/of-yadr/releases/) or a [dev build](https://github.com/Enovale/of-yadr/actions?query=workflow:"Nightly+Build"), and download and install the required extensions.

Launch the server once to get everything to configure itself, then you can edit `<server>/cfg/sourcemod/yadr.cfg`.
The cvars should be documented enough to get you started.

If you want to change or translate the text the bot outputs, check out the two translation files in the install. They are also documented.

More detailed installation help with pictures can be found on the [wiki](https://github.com/Enovale/of-yadr/wiki).

## Features

- Relay messages from Discord to a Server, and vice versa.
- Relay events like player connect/disconnect, map change, bans/reports to Discord
- Run rcon commands, ban/kick players, psay to players, remotely with slash commands.
- Makes sure player names and SteamIDs are searchable in the discord history, without clogging up the conversation

## Building

I highly recommend [Sourcepawn Studio](https://github.com/Sarrus1/sourcepawn-studio).
With a proper setup it can create a seamless workflow and means I don't have to push hacky scripts to my repository.

## License

Released under [GPLv3](/LICENSE) by [@Enovale](https://github.com/Enovale).
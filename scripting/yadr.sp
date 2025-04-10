#define PLUGIN_NAME           "Yet Another Discord Relay"
#define PLUGIN_SHORTNAME      "yadr"
#define PLUGIN_TRANS_FILE     "yadr.phrases"
#define PLUGIN_AUTHOR         "Enova"
#define PLUGIN_DESCRIPTION    "Discord Relay with a focus on clean compact output and performance."
#define PLUGIN_VERSION        "1.0"
#define PLUGIN_URL            "https://github.com/Enovale/of-yadr"

#include <sourcemod>
#include <sdktools>
#include <chat-processor>
#include <discord>

#include "yadr/format_vars.sp"

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

ConVar g_cvBotToken;
ConVar g_cvSteamApiKey;
ConVar g_cvChannelIds;
ConVar g_cvWebsocketModeEnable;
ConVar g_cvDiscordSendEnable;
ConVar g_cvServerSendEnable;
ConVar g_cvDiscordColorCodesEnable;

ConVar g_cvVerboseEnable;

// 255 channel list limit is arbitrary.
// TODO Use ArrayList instead
char g_ChannelList[255][SNOWFLAKE_SIZE];
char g_ChannelNameList[sizeof(g_ChannelList)][MAX_DISCORD_CHANNEL_NAME_LENGTH];
int g_ChannelListCount;

Discord g_Discord;
char g_BotId[SNOWFLAKE_SIZE];

Handle t_Timer;

public void OnPluginStart()
{
	LoadTranslations(PLUGIN_TRANS_FILE);

	g_cvBotToken = CreateConVar("sm_discord_bot_token", "", "Token for the discord bot to connect to.", FCVAR_PROTECTED);
	g_cvSteamApiKey = CreateConVar("sm_discord_steam_api_key", "", "Steam Web API key for fetching player avatars.", FCVAR_PROTECTED);
	g_cvChannelIds = CreateConVar("sm_discord_channel_ids", "", "List of channel IDs, separated by semicolons, to relay between.");
	g_cvWebsocketModeEnable = CreateConVar("sm_discord_websocket_mode_enable", "1", "Enable pretty output with a webhook rather than the more limited bot output.");
	g_cvDiscordSendEnable = CreateConVar("sm_discord_dc_send_enable", "1", "Enable discord messages to be sent to the server.");
	g_cvServerSendEnable = CreateConVar("sm_discord_server_send_enable", "1", "Enable player messages to be sent to discord.");
	g_cvDiscordColorCodesEnable = CreateConVar("sm_discord_dc_color_codes_enable", "0", "Allows discord messages to contain color codes like {grey} or {green}.");
	
	g_cvVerboseEnable = CreateConVar("sm_discord_verbose", "0", "Enable verbose logging for the discord backend.");

	if (g_cvVerboseEnable.BoolValue)
	{
		// TODO This seems bad but also I don't know why translations don't reload anyway
		ServerCommand("sm_reload_translations");
	}

	g_cvBotToken.AddChangeHook(OnBotTokenChange);
	g_cvChannelIds.AddChangeHook(OnCvarChange);
	g_cvSteamApiKey.AddChangeHook(OnCvarChange);

	AutoExecConfig(true, PLUGIN_SHORTNAME);
	UpdateCvars();

	SetupDiscordBot();

	if (g_HttpClient != null)
    	delete g_HttpClient;

    g_HttpClient = new HTTPClient("https://api.steampowered.com");
	
	if (SteamApiAvailable())
	{
		// Get steam avatars for existing players in case of plugin reload
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientConnected(i) && !IsFakeClient(i) && !IsClientSourceTV(i)) {
				GetProfilePic(i);
			}
		}
	}

	LogMessage("Plugin Started!");
}

public void OnConfigsExecuted()
{
	CacheFormatVars();
}

public void OnCvarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	UpdateCvars();
}

public void OnBotTokenChange(ConVar convar, char[] oldValue, char[] newValue)
{
	SetupDiscordBot();
}

public void OnMapStart()
{
	if (g_Discord == INVALID_HANDLE)
	{
		SetupDiscordBot();
	}
}

public void OnMapInit(const char[] mapName)
{
	CacheExplicitMapName(mapName);
}

// Make sure to update presence immediately when entering hibernation
public void OnServerEnterHibernation()
{
	TriggerTimer(t_Timer);
}

public void OnClientPostAdminCheck(int client)
{
    GetProfilePic(client);
}

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
	if (!g_cvServerSendEnable.BoolValue || message[0] == '!' || (message[0] == '!' && message[1] == '!')) // Ignore chat commands
	{
		return Plugin_Continue;
	}

	int team = GetClientTeam(author);
	char teamName[MAX_TEAM_NAME];
	teamName = GetTeamNameEx(team);
	char cMessage[MAX_DISCORD_NITRO_MESSAGE_LENGTH];
	FormatEx(cMessage, sizeof(cMessage), "%t", "Server->Discord Message Content",
											name,
											message,
											author,
											team,
											teamName,
											StrEqual("Spectator", teamName) ? teamName : "", // TODO This seems not adaptable to other games
											GetClientAuthId2(author),
											GetClientAuthId64(author),
											GetClientAuthId3(author),
											GetClientAuthIdEngine(author),
											GetClientConnectionTime(author),
											g_SteamAvatars[author],
											g_CachedMapName,
											GetNextMapEx(),
											g_ServerHostname,
											g_ServerIpStr,
											GetPlayers(false),
											g_MaxPlayers
			);
	SanitiseText(cMessage, sizeof(cMessage));
	for (int i = 0; i < g_ChannelListCount; i++)
	{
		LogMessage(cMessage);
		g_Discord.SendMessage(g_ChannelList[i], cMessage);
	}
	
	return Plugin_Continue;
}

void UpdateCvars()
{
	char channelIdsString[sizeof(g_ChannelList) * sizeof(g_ChannelList[0])];
	GetConVarString(g_cvChannelIds, channelIdsString, sizeof(channelIdsString));

	if (!StrContains(channelIdsString, ";"))
	{
		FormatEx(g_ChannelList[0], sizeof(g_ChannelList[0]), channelIdsString);
		g_ChannelListCount = 1;
	}
	else
	{
		g_ChannelListCount = ExplodeString(channelIdsString, ";", g_ChannelList, sizeof(g_ChannelList), sizeof(g_ChannelList[0]));
	}

	GetConVarString(g_cvSteamApiKey, g_SteamApiKey, sizeof(g_SteamApiKey));
}

void SetupDiscordBot()
{
	TeardownDiscordBot();

	char tokenString[80];
	GetConVarString(g_cvBotToken, tokenString, sizeof(tokenString));

	if (IsNullString(tokenString))
	{
		LogError("Discord token needs to be filled in, you can set it in cfg/sourcemod/%s.cfg", PLUGIN_SHORTNAME);
		return;
	}

	g_Discord = new Discord(tokenString);

	bool startedSuccess = g_Discord.Start();

	if (g_Discord == INVALID_HANDLE || !startedSuccess)
	{
		LogError("Could not create Discord object, try checking your token, you can set it in cfg/sourcemod/%s.cfg", PLUGIN_SHORTNAME);
		return;
	}
}

void TeardownDiscordBot()
{
	if (g_Discord != INVALID_HANDLE)
	{
		g_Discord.Stop();
	}

	delete t_Timer;
	delete g_Discord;
}

public void Discord_OnReady(Discord discord)
{
	char botName[MAX_DISCORD_NAME_LENGTH], botId[MAX_DISCORD_NAME_LENGTH];
	discord.GetBotName(botName, sizeof(botName));
	discord.GetBotId(botId, sizeof(botId));

	LogMessage("Bot %s (ID: %s) is ready!", botName, botId);

	g_Discord.RegisterGlobalSlashCommand("ping", "Check bot latency");
	g_Discord.RegisterGlobalSlashCommand("status", "Fetch various information about the server.");
	//g_Discord.RegisterGlobalSlashCommand("ban", "Ban a player from the server.");
	//g_Discord.RegisterGlobalSlashCommand("kick", "Kick a player from the server.");

	LogMessage("Getting output channel names...");
	for(int i = 0; i < g_ChannelListCount; i++)
	{
		g_Discord.GetChannel(g_ChannelList[i], OnGetChannelCallback, i);
	}

	t_Timer = CreateTimer(5.0, UpdatePresenceTimer, 0, TIMER_REPEAT);
}

public void Discord_OnSlashCommand(Discord discord, DiscordInteraction interaction)
{
	char commandName[32];
	interaction.GetCommandName(commandName, sizeof(commandName));

	if (strcmp(commandName, "ping") == 0)
	{
		interaction.CreateEphemeralResponse("Pong!");
	}
	if (strcmp(commandName, "status") == 0)
	{
		char playersString[3 * 2 + 1];
		FormatEx(playersString, sizeof(playersString), "%d/%d", GetClientCount(), MaxClients);

		// Source SDK 2013's MAX_MAP_NAME
		char mapName[MAX_MAP_NAME];
		GetCurrentMap(mapName, sizeof(mapName));

		DiscordEmbed embed = new DiscordEmbed();
		embed.SetTitle("Server Status");
		embed.SetDescription("Current server information");
		embed.AddField("Players", playersString, true);
		embed.AddField("Map", mapName, true);
		embed.SetFooter("Test!");

		interaction.CreateEphemeralResponseEmbed("", embed);
		delete embed;
	}
}

public void Discord_OnMessage(Discord discord, DiscordMessage message)
{
	char authorId[SNOWFLAKE_SIZE];
	message.GetAuthorId(authorId, sizeof(authorId));

	if (StrEqual(authorId, g_BotId) || message.IsBot() || !g_cvDiscordSendEnable.BoolValue)
	{
		return;
	}

	char content[MAX_MESSAGE_LENGTH];
	message.GetContent(content, sizeof(content));

	char channelId[SNOWFLAKE_SIZE];
	message.GetChannelId(channelId, sizeof(channelId));

	for (int i = 0; i < g_ChannelListCount; i++)
	{
		if (StrEqual(channelId, g_ChannelList[i]))
		{
			LogMessage(content);

			char authorName[MAX_DISCORD_NAME_LENGTH];
			message.GetAuthorName(authorName, sizeof(authorName));

			if (!g_cvDiscordColorCodesEnable.BoolValue)
			{
				CRemoveTags(authorName, sizeof(authorName));
				CRemoveTags(content, sizeof(content));
			}

			int authorDescriminator = message.GetAuthorDiscriminator();

			CPrintToChatAll("%t", "Discord->Server Message Content", authorName,
																	content,
																	g_ChannelNameList[i],
																	authorId,
																	authorDescriminator,
																	channelId
							);
			break;
		}
	}
}

public void Discord_OnError(Discord discord, const char[] error)
{
	if (g_cvVerboseEnable.BoolValue)
	{
		LogMessage(error);
	}
}

void OnGetChannelCallback(Discord discord, DiscordChannel channel, int index)
{
	channel.GetName(g_ChannelNameList[index], sizeof(g_ChannelNameList[0]));
	CRemoveTags(g_ChannelNameList[index], sizeof(g_ChannelNameList[0]));

	LogMessage("Outputting to: #%s", g_ChannelNameList[index]);
}

public Action UpdatePresenceTimer(Handle timer, any data)
{
	UpdatePresence();

	return Plugin_Continue;
}

void UpdatePresence()
{
	char playerCountStr[MAX_DISCORD_PRESENCE_LENGTH];	
	int clientCount = GetPlayers(false);
	FormatEx(playerCountStr, sizeof(playerCountStr), "%t",
											clientCount == 1 ? "Status" : "Status Plural",
											clientCount,
											g_MaxPlayers,
											g_CachedMapName,
											GetNextMapEx(),
											g_ServerHostname,
											g_ServerIpStr
			);
	g_Discord.SetPresence(Presence_Online, Activity_Custom, playerCountStr);
}

public void OnPluginEnd()
{
	TeardownDiscordBot();
}

#define DEBUG 1

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
#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

#define SNOWFLAKE_SIZE_WITH_TERMINATOR 20
#define MAX_DISCORD_NAME_LENGTH_WITH_TERMINATOR 33

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

ConVar g_cvBotToken;
ConVar g_cvChannelIds;
ConVar g_cvWebsocketModeEnable;
ConVar g_cvDiscordSendEnable;
ConVar g_cvServerSendEnable;

char g_ChannelList[255][SNOWFLAKE_SIZE_WITH_TERMINATOR];
int g_ChannelListCount;

Discord g_Discord;
char g_BotId[SNOWFLAKE_SIZE_WITH_TERMINATOR];

Handle t_Timer;

public void OnPluginStart()
{
	LoadTranslations(PLUGIN_TRANS_FILE);

	g_cvBotToken = CreateConVar("sm_discord_bot_token", "", "Token for the discord bot to connect to.", FCVAR_PROTECTED);
	g_cvChannelIds = CreateConVar("sm_discord_channel_ids", "", "List of channel IDs, separated by semicolons, to relay between.");
	g_cvWebsocketModeEnable = CreateConVar("sm_discord_websocket_mode_enable", "1", "Enable pretty output with a webhook rather than the more limited bot output.");
	g_cvDiscordSendEnable = CreateConVar("sm_discord_dc_send_enable", "1", "Enable discord messages to be sent to the server.");
	g_cvServerSendEnable = CreateConVar("sm_discord_server_send_enable", "1", "Enable player messages to be sent to discord.");

	if (DEBUG)
	{
		ServerCommand("sm_reload_translations");
	}

	g_cvBotToken.AddChangeHook(OnBotTokenChange);
	g_cvChannelIds.AddChangeHook(OnCvarChange);

	AutoExecConfig(true, PLUGIN_SHORTNAME);
	UpdateCvars();

	SetupDiscordBot();

	LogMessage("Plugin Started!");
}

public void OnCvarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	UpdateCvars();
}

void UpdateCvars()
{
	char channelIdsString[sizeof(g_ChannelList) * sizeof(g_ChannelList[0])];
	GetConVarString(g_cvChannelIds, channelIdsString, sizeof(channelIdsString));

	if (!StrContains(channelIdsString, ";"))
	{
		Format(g_ChannelList[0], sizeof(g_ChannelList[0]), channelIdsString);
		g_ChannelListCount = 1;
	}
	else
	{
		g_ChannelListCount = ExplodeString(channelIdsString, ";", g_ChannelList, sizeof(g_ChannelList), sizeof(g_ChannelList[0]));
	}
}

public void OnBotTokenChange(ConVar convar, char[] oldValue, char[] newValue)
{
	SetupDiscordBot();
}

public void OnPluginEnd()
{
	TeardownDiscordBot();
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

public void OnMapStart()
{
	if (g_Discord == INVALID_HANDLE)
	{
		SetupDiscordBot();
	}
}

public void Discord_OnReady(Discord discord)
{
	char botName[32], botId[32];
	discord.GetBotName(botName, sizeof(botName));
	discord.GetBotId(botId, sizeof(botId));

	PrintToServer("Bot %s (ID: %s) is ready!", botName, botId);

	g_Discord.RegisterGlobalSlashCommand("ping", "Check bot latency");
	g_Discord.RegisterGlobalSlashCommand("status", "Fetch various information about the server.");
	//g_Discord.RegisterGlobalSlashCommand("ban", "Ban a player from the server.");
	//g_Discord.RegisterGlobalSlashCommand("kick", "Kick a player from the server.");f

	t_Timer = CreateTimer(5.0, UpdatePresenceTimer, 0, TIMER_REPEAT);
}

public void OnServerEnterHibernation()
{
	TriggerTimer(t_Timer);
}

public Action UpdatePresenceTimer(Handle timer, any data)
{
	UpdatePresence();

	return Plugin_Continue;
}

void UpdatePresence()
{
	char playerCount[20];
	int clientCount = GetClientCount(false);
	Format(playerCount, sizeof(playerCount), "%d player%s connected.", clientCount, clientCount == 1 ? "" : "s");
	g_Discord.SetPresence(Presence_Online, Activity_Custom, playerCount);
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
		Format(playersString, sizeof(playersString), "%d/%d", GetClientCount(), MaxClients);

		// https://tf2maps.net/threads/what-exactly-is-the-maximum-map-name-length.53568/
		char mapName[64];
		GetCurrentMap(mapName, sizeof(mapName));

		DiscordEmbed embed = new DiscordEmbed();
		embed.SetTitle("Server Status");
		embed.SetDescription("Current server information");
		//embed.SetColor(0x00FF00);  // Green color
		embed.AddField("Players", playersString, true);
		embed.AddField("Map", mapName, true);

		interaction.CreateEphemeralResponseEmbed("", embed);
		delete embed;
	}
}

public void Discord_OnMessage(Discord discord, DiscordMessage message)
{
	char authorId[SNOWFLAKE_SIZE_WITH_TERMINATOR];
	message.GetAuthorId(authorId, sizeof(authorId));

	if (StrEqual(authorId, g_BotId) || message.IsBot() || !g_cvDiscordSendEnable.BoolValue)
	{
		return;
	}

	char content[MAX_MESSAGE_LENGTH];
	message.GetContent(content, sizeof(content));

	char channelId[SNOWFLAKE_SIZE_WITH_TERMINATOR];
	message.GetChannelId(channelId, sizeof(channelId));

	for (int i = 0; i < g_ChannelListCount; i++)
	{
		if (StrEqual(channelId, g_ChannelList[i]))
		{
			LogMessage(content);

			char authorName[MAX_DISCORD_NAME_LENGTH_WITH_TERMINATOR];
			message.GetAuthorName(authorName, sizeof(authorName));

			char outputMessage[MAX_DISCORD_NAME_LENGTH_WITH_TERMINATOR + MAX_MESSAGE_LENGTH + 100];
			Format(outputMessage, sizeof(outputMessage), "[DISCORD] %s: %s", authorName, content);

			CPrintToChatAll("%s", outputMessage);
			break;
		}
	}
}

public void Discord_OnError(Discord discord, const char[] error)
{
	// Stub
}

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
	if (!g_cvServerSendEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	for (int i = 0; i < g_ChannelListCount; i++)
	{
		LogMessage(message);
		g_Discord.SendMessage(g_ChannelList[i], message);
	}
	
	return Plugin_Continue;
}

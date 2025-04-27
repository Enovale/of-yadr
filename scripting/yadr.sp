#define PLUGIN_NAME          "Yet Another Discord Relay"
#define PLUGIN_SHORTNAME     "yadr"
#define PLUGIN_TRANS_FILE    PLUGIN_SHORTNAME... ".phrases"
#define PLUGIN_CONVAR_PREFIX "sm_" ... PLUGIN_SHORTNAME... "_"
#define PLUGIN_AUTHOR        "Enova"
#define PLUGIN_DESCRIPTION   "Discord Relay with a focus on clean compact output and performance."
#define PLUGIN_VERSION       "0.1.0"
#define PLUGIN_URL           "https://github.com/Enovale/of-" ... PLUGIN_SHORTNAME

#include <sourcemod>
#include <sdktools>
#include <chat-processor>
#include <discord>

#include "yadr/format_vars.sp"
#include "yadr/translation_phrases.sp"
#include "yadr/structs.sp"

#pragma newdecls required
#pragma semicolon 1

// clang-format off
// param 1 - client index variable
#define FormatServerBlock(%0)         g_CachedMapName,        \
                                      g_CachedNextMapName,    \
                                      g_ServerHostname,       \
                                      g_ServerIpStr,          \
                                      g_ServerPort,           \
                                      %0,                     \
                                      g_MaxPlayers,           \
                                      g_cvFragLimit.IntValue, \
                                      g_BotName,              \
                                      g_BotId

// param 1 - client index variable
#define FormatPlayerBlock(%0)         GetClientNameEx(%0, true),             \
                                      %0,                                    \
                                      GetClientUserId(%0),                   \
                                      GetClientFrags(%0),                    \
                                      team,                                  \
                                      teamName,                              \
                                      GetClientTeamNameIfSpectator(teamName),\
                                      GetClientIpEx(%0),                     \
                                      GetClientAuthId2(%0),                  \
                                      GetClientAuthId64(%0),                 \
                                      GetClientAuthId3(%0),                  \
                                      GetClientAuthIdEngine(%0),             \
                                      GetClientConnectionTime(%0),           \
                                      GetClientPing(%0),                     \
                                      g_SteamAvatars[%0]

// param 1 - client index variable
#define FormatPlayerMessageBlock(%0)  sMessage,             \
                                      sName,                \
                                      %0,                   \
                                      userId,               \
                                      frags,                \
                                      team,                 \
                                      teamName,             \
                                      teamNameIfSpectator,  \
                                      clientIp,             \
                                      authId2,              \
                                      authId64,             \
                                      authId3,              \
                                      authIdEngine,         \
                                      clientConnectionTime, \
                                      clientPing,           \
                                      g_SteamAvatars[%0]

// param 1 - channel index
#define FormatDiscordMessageBlock(%0) username,               \
                                      displayName,            \
                                      nickname,               \
                                      content,                \
                                      g_ChannelList[%0].name, \
                                      authorId,               \
                                      authorDescriminator,    \
                                      channelId

// clang-format on
public Plugin myinfo =
{
    name        = PLUGIN_NAME,
    author      = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version     = PLUGIN_VERSION,
    url         = PLUGIN_URL
};

ConVar      g_cvBotToken;
ConVar      g_cvSteamApiKey;
ConVar      g_cvChannelIds;
ConVar      g_cvWebhookModeEnable;
ConVar      g_cvWebhookName;
ConVar      g_cvWebhookUrlOverrides;
ConVar      g_cvDiscordSendEnable;
ConVar      g_cvServerSendEnable;
ConVar      g_cvDiscordColorCodesEnable;
ConVar      g_cvPresenceUpdateInterval;
ConVar      g_cvMapChangeGracePeriod;

ConVar      g_cvVerboseEnable;

// Cached internal convars
ConVar      g_cvFragLimit;

// 255 channel list limit is arbitrary
// TODO This should really be a map of some kind but currently cannot iterate StringMaps
ChannelInfo g_ChannelList[255];
int         g_ChannelListCount;

ArrayList   g_BannedWords;

Discord     g_Discord;
bool        g_BotReady;
char        g_BotName[MAX_DISCORD_NAME_LENGTH];
char        g_BotId[SNOWFLAKE_SIZE];
char        g_WebhookName[MAX_DISCORD_NAME_LENGTH];

bool        g_ServerIdle;
bool        g_AllowConnectEvents;
Handle      t_Timer;

public void OnPluginStart()
{
    LoadTranslations(PLUGIN_TRANS_FILE);

    g_cvBotToken                = CreateConVar(PLUGIN_CONVAR_PREFIX... "bot_token", "", "Token for the discord bot to connect to.", FCVAR_PROTECTED);
    g_cvSteamApiKey             = CreateConVar(PLUGIN_CONVAR_PREFIX... "steam_api_key", "", "Steam Web API key for fetching player avatars.", FCVAR_PROTECTED);
    g_cvChannelIds              = CreateConVar(PLUGIN_CONVAR_PREFIX... "channel_ids", "", "List of channel IDs, separated by semicolons, to relay between.", FCVAR_PROTECTED);
    g_cvWebhookModeEnable       = CreateConVar(PLUGIN_CONVAR_PREFIX... "webhook_mode_enable", "1", "Enable pretty output with a webhook rather than the more limited bot output.");
    g_cvWebhookName             = CreateConVar(PLUGIN_CONVAR_PREFIX... "webhook_name", "Yadr Relay", "The name of the webhook to use for webhook output.");
    g_cvWebhookUrlOverrides     = CreateConVar(PLUGIN_CONVAR_PREFIX... "webhook_urls", "", "List of webhook URLs, separated by semicolons, in the same order as `" ... PLUGIN_CONVAR_PREFIX... "channel_ids`, to use. If the webhook for a channel is left blank, it will be created if the bot has permission to do so.", FCVAR_PROTECTED);
    g_cvDiscordSendEnable       = CreateConVar(PLUGIN_CONVAR_PREFIX... "dc_send_enable", "1", "Enable discord messages to be sent to the server.");
    g_cvServerSendEnable        = CreateConVar(PLUGIN_CONVAR_PREFIX... "server_send_enable", "1", "Enable player messages to be sent to discord.");
    g_cvDiscordColorCodesEnable = CreateConVar(PLUGIN_CONVAR_PREFIX... "dc_color_codes_enable", "0", "Allows discord->server messages to contain color codes like {grey} or {green}.");
    g_cvPresenceUpdateInterval  = CreateConVar(PLUGIN_CONVAR_PREFIX... "presence_interval", "5.0", "How often to update the bot's status (in seconds).");
    g_cvMapChangeGracePeriod    = CreateConVar(PLUGIN_CONVAR_PREFIX... "map_change_grace", "20.0", "How much time (in seconds) before connect events will be fired after a map starts.");

    g_cvVerboseEnable           = CreateConVar(PLUGIN_CONVAR_PREFIX... "verbose", "0", "Enable verbose logging for the discord backend.");

    g_cvFragLimit               = FindConVar("mp_fraglimit");

    // TODO This seems bad but also I don't know why translations don't reload anyway
    ServerCommand("sm_reload_translations");

    AutoExecConfig(true, PLUGIN_SHORTNAME);
    InitializeLogging(PLUGIN_SHORTNAME, g_cvVerboseEnable.BoolValue ? LogLevel_Debug : LogLevel_Info);

    if (!TranslationPhraseExists(TRANSLATION_DISCORD_SERVER_MESSAGE) && !TranslationPhraseExists(TRANSLATION_SERVER_DISCORD_MESSAGE) && !TranslationPhraseExists(TRANSLATION_WEBHOOK_MESSAGE) && !TranslationPhraseExists(TRANSLATION_STATUS) && !TranslationPhraseExists(TRANSLATION_STATUS_PLURAL))
    {
        logger.Error("!!!! No translations are specified, bot won't do anything! Please copy and edit `translations/" ... PLUGIN_TRANS_FILE... ".txt`");
    }

    if (g_HttpClient != null)
        delete g_HttpClient;

    g_HttpClient = new HTTPClient("https://api.steampowered.com");

    HookEvent("player_changename", OnPlayerChangeName);
    HookEvent("player_disconnect", OnPlayerDisconnect, EventHookMode_Pre);

    logger.Info("Plugin Started!");
}

public void OnConfigsExecuted()
{
    g_cvBotToken.AddChangeHook(OnBotTokenChange);
    g_cvChannelIds.AddChangeHook(OnCvarChange);
    g_cvSteamApiKey.AddChangeHook(OnCvarChange);
    FindConVar("sm_nextmap").AddChangeHook(OnNextMapChanged);

    UpdateCvars();

    CacheFormatVars();

    InitializeBannedWords();

    OnMapOrPluginStart();

    if (SteamApiAvailable())
    {
        // Get steam avatars for existing players in case of plugin reload
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidClient(i))
            {
                GetProfilePic(i);
            }
        }
    }
}

void InitializeBannedWords(bool force = false)
{
    if (g_BannedWords && !force)
    {
        return;
    }

    g_BannedWords = new ArrayList(ByteCountToCells(MAX_MESSAGE_LENGTH));
    char filePath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/" ... PLUGIN_SHORTNAME... "_banned_prefixes.txt");
    GetBannedWords(filePath);
}

void GetBannedWords(const char[] path)
{
    if (!FileExists(path))
    {
        Handle fileHandle = OpenFile(path, "w");
        WriteFileString(fileHandle, "/\n!\nrtv\nnominate", false);
        CloseHandle(fileHandle);
    }

    char   line[MAX_MESSAGE_LENGTH];

    Handle fileHandle = OpenFile(path, "r");
    while (!IsEndOfFile(fileHandle) && ReadFileLine(fileHandle, line, sizeof(line)))
    {
        if (g_BannedWords.FindString(line) == -1)
        {
            ReplaceStringEx(line, sizeof(line), "\n", "");
            g_BannedWords.PushString(line);
        }
    }

    CloseHandle(fileHandle);
}

public void OnCvarChange(ConVar convar, char[] oldValue, char[] newValue)
{
    UpdateCvars();
}

public void OnBotTokenChange(ConVar convar, char[] oldValue, char[] newValue)
{
    if (!StrEqual(oldValue, newValue))
    {
        SetupDiscordBot();
    }
}

public void OnMapStart()
{
    g_ServerIdle = false;

    if (t_Timer)
    {
        TriggerTimer(t_Timer);
    }

    g_AllowConnectEvents = false;
    CreateTimer(g_cvMapChangeGracePeriod.FloatValue, OnMapStartGracePeriod);
}

void OnMapOrPluginStart()
{
    if (!BotRunning(g_Discord))
    {
        SetupDiscordBot();
    }

    if (g_BotReady && TranslationPhraseExists(TRANSLATION_MAP_CHANGE_EVENT))
    {
        SendToDiscordEx(TRANSLATION_MAP_CHANGE_EVENT, FormatServerBlock(GetPlayers(false)));
    }
}

public void OnMapInit(const char[] mapName)
{
    CacheExplicitMapName(mapName);
}

public void OnMapEnd()
{
    g_ServerIdle         = true;
    g_AllowConnectEvents = false;
    if (t_Timer)
    {
        TriggerTimer(t_Timer);
    }
}

// Make sure to update presence immediately when entering hibernation
public void OnServerEnterHibernation()
{
    g_ServerIdle = true;
    if (t_Timer)
    {
        TriggerTimer(t_Timer);
    }
}

public void OnServerExitHibernation()
{
    g_ServerIdle = false;
    if (t_Timer)
    {
        TriggerTimer(t_Timer);
    }
}

public void OnClientPostAdminCheck(int client)
{
    GetProfilePic(client);

    if (!g_ServerIdle && g_AllowConnectEvents && TranslationPhraseExists(TRANSLATION_PLAYER_CONNECT_EVENT))
    {
        int  team = GetClientTeam(client);
        char teamName[MAX_TEAM_NAME];
        teamName = GetTeamNameEx(team);
        SendToDiscordEx(TRANSLATION_PLAYER_CONNECT_EVENT,
                        FormatPlayerBlock(client),
                        FormatServerBlock(GetPlayers(false)));
    }
}

Action OnPlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_ServerIdle && g_AllowConnectEvents && TranslationPhraseExists(TRANSLATION_PLAYER_DISCONNECT_EVENT))
    {
        int  client = GetClientOfUserId(GetEventInt(event, "userid"));
        char reason[MAX_MESSAGE_LENGTH];
        GetEventString(event, "reason", reason, sizeof(reason));
        ReplaceString(reason, sizeof(reason), "\n", " ");

        int  team = GetClientTeam(client);
        char teamName[MAX_TEAM_NAME];
        teamName = GetTeamNameEx(team);
        SendToDiscordEx(TRANSLATION_PLAYER_DISCONNECT_EVENT,
                        reason,
                        FormatPlayerBlock(client),
                        FormatServerBlock(GetPlayers(false)));
    }

    return Plugin_Continue;
}

public Action OnBanClient(int client, int time, int flags, const char[] reason, const char[] kick_message, const char[] command, any source)
{
    if (TranslationPhraseExists(TRANSLATION_PLAYER_BAN_EVENT))
    {
        int  team = GetClientTeam(client);
        char teamName[MAX_TEAM_NAME];
        teamName = GetTeamNameEx(team);
        SendToDiscordEx(TRANSLATION_PLAYER_BAN_EVENT,
                        time,
                        reason,
                        FormatPlayerBlock(client),
                        FormatServerBlock(GetPlayers(false)));
    }
    return Plugin_Continue;
}

public Action OnBanIdentity(const char[] identity, int time, int flags, const char[] reason, const char[] command, any source)
{
    logger.Debug("OnBanIdentity!");
    return Plugin_Continue;
}

Action OnPlayerChangeName(Event event, const char[] name, bool dontBroadcast)
{
    if (TranslationPhraseExists(TRANSLATION_PLAYER_NAME_CHANGE_EVENT))
    {
        int  client = GetClientOfUserId(GetEventInt(event, "userid"));
        char newName[MAX_NAME_LENGTH];
        GetEventString(event, "newname", newName, sizeof(newName));

        int  team = GetClientTeam(client);
        char teamName[MAX_TEAM_NAME];
        teamName = GetTeamNameEx(team);
        SendToDiscordEx(TRANSLATION_PLAYER_NAME_CHANGE_EVENT,
                        newName,
                        FormatPlayerBlock(client),
                        FormatServerBlock(GetPlayers(false)));
    }

    return Plugin_Continue;
}

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
    if (!g_cvServerSendEnable.BoolValue || !BotRunning(g_Discord) || !TranslationPhraseExists(TRANSLATION_SERVER_DISCORD_MESSAGE))
    {
        return Plugin_Continue;
    }

    for (int i = 0; i < g_BannedWords.Length; i++)
    {
        char bannedWord[MAX_MESSAGE_LENGTH];
        g_BannedWords.GetString(i, bannedWord, sizeof(bannedWord));
        // if the message starts with the banned word
        if (StrContains(message, bannedWord) == 0)
        {
            return Plugin_Continue;
        }
    }

    int  team = GetClientTeam(author);
    char teamName[MAX_TEAM_NAME];
    teamName = GetTeamNameEx(team);
    char tempBuffer[MAX_DISCORD_MESSAGE_LENGTH];

    // name
    Format(tempBuffer, sizeof(tempBuffer), "%s", name);
    SanitiseText(tempBuffer, sizeof(tempBuffer));
    int tempLength = strlen(tempBuffer) + 1;
    char[] sName   = new char[tempLength];
    Format(sName, tempLength, "%s", tempBuffer);

    // message
    Format(tempBuffer, sizeof(tempBuffer), "%s", message);
    SanitiseText(tempBuffer, sizeof(tempBuffer));
    tempLength      = strlen(tempBuffer) + 1;
    char[] sMessage = new char[tempLength];
    Format(sMessage, tempLength, "%s", tempBuffer);

    // Cached variables for webhook output
    int  userId = GetClientUserId(author);
    char teamNameIfSpectator[MAX_TEAM_NAME];
    teamNameIfSpectator = GetClientTeamNameIfSpectator(teamName);
    char clientIp[MAX_IP_LENGTH];
    clientIp = GetClientIpEx(author);
    char authId2[MAX_AUTHID_LENGTH];
    authId2 = GetClientAuthId2(author);
    char authId64[MAX_AUTHID_LENGTH];
    authId64 = GetClientAuthId64(author);
    char authId3[MAX_AUTHID_LENGTH];
    authId3 = GetClientAuthId3(author);
    char authIdEngine[MAX_AUTHID_LENGTH];
    authIdEngine = GetClientAuthIdEngine(author);
    char clientConnectionTime[SHORT_TIME_LENGTH];
    clientConnectionTime = GetClientConnectionTime(author);
    int  clientPing      = GetClientPing(author);
    int  playerCount     = GetPlayers(false);

    char botContent[MAX_DISCORD_MESSAGE_LENGTH];
    char webhookContent[MAX_DISCORD_MESSAGE_LENGTH];
    char playerInfoEventContent[MAX_DISCORD_MESSAGE_LENGTH];

    int  frags = GetClientFrags(author);
    if (TranslationPhraseExists(TRANSLATION_SERVER_DISCORD_MESSAGE))
    {
        FormatEx(botContent, sizeof(botContent), "%t", TRANSLATION_SERVER_DISCORD_MESSAGE,
                 FormatPlayerMessageBlock(author),
                 FormatServerBlock(playerCount));
    }

    if (TranslationPhraseExists(TRANSLATION_WEBHOOK_MESSAGE))
    {
        FormatEx(webhookContent, sizeof(webhookContent), "%t", TRANSLATION_WEBHOOK_MESSAGE,
                 FormatPlayerMessageBlock(author),
                 FormatServerBlock(playerCount));
    }

    if (TranslationPhraseExists(TRANSLATION_PLAYER_INFO_EVENT))
    {
        FormatEx(playerInfoEventContent, sizeof(playerInfoEventContent), "%t", TRANSLATION_PLAYER_INFO_EVENT,
                 FormatPlayerMessageBlock(author),
                 FormatServerBlock(playerCount));
    }

    for (int i = 0; i < g_ChannelListCount; i++)
    {
        bool webhookAvailable = g_ChannelList[i].WebhookAvailable();
        char webhookName[MAX_DISCORD_NAME_LENGTH];
        FormatEx(webhookName, sizeof(webhookName), "%s", sName);

        if (webhookAvailable)
        {
            FormatEx(webhookName, sizeof(webhookName), "%t", TRANSLATION_WEBHOOK_NAME,
                     FormatPlayerMessageBlock(author),
                     FormatServerBlock(playerCount));
        }

        char finalContent[MAX_DISCORD_MESSAGE_LENGTH];
        finalContent = webhookAvailable ? webhookContent : botContent;

        if (StrEqual(finalContent, ""))
        {
            return Plugin_Continue;
        }

        if (TranslationPhraseExists(TRANSLATION_PLAYER_INFO_EVENT) && !StrEqual(g_ChannelList[i].lastAuthor, authIdEngine))
        {
            if (strlen(finalContent) + strlen(playerInfoEventContent) < MAX_DISCORD_MESSAGE_LENGTH)
            {
                Format(finalContent, sizeof(finalContent), "%s\n%s", playerInfoEventContent, finalContent);
            }
            else
            {
                SendToDiscordChannel(g_ChannelList[i], playerInfoEventContent, webhookName, author);
            }
        }

        SendToDiscordChannel(g_ChannelList[i], finalContent, webhookName, author);
        g_ChannelList[i].lastAuthor = authIdEngine;
    }

    return Plugin_Continue;
}

void UpdateCvars()
{
    char channelIdsString[MAX_BUFFER_LENGTH];
    GetConVarString(g_cvChannelIds, channelIdsString, sizeof(channelIdsString));

    if (!StrContains(channelIdsString, ";"))
    {
        FormatEx(g_ChannelList[0].id, sizeof(channelIdsString), channelIdsString);
        g_ChannelListCount = 1;
    }
    else
    {
        char g_ChannelIdList[sizeof(g_ChannelList)][SNOWFLAKE_SIZE];
        g_ChannelListCount = ExplodeString(channelIdsString, ";", g_ChannelIdList, sizeof(g_ChannelIdList), sizeof(g_ChannelIdList[]));

        for (int i = 0; i < g_ChannelListCount; i++)
        {
            g_ChannelList[i].id = g_ChannelIdList[i];
        }
    }

    if (g_ChannelListCount <= 0)
    {
        logger.ThrowError(LogLevel_Fatal, "No output channels specified! Please add them in your cvar config.");
        return;
    }

    char webhookUrlsString[MAX_BUFFER_LENGTH];
    GetConVarString(g_cvWebhookUrlOverrides, webhookUrlsString, sizeof(webhookUrlsString));

    if (g_cvWebhookModeEnable.BoolValue && !StrEqual(webhookUrlsString, ""))
    {
        if (StrContains(webhookUrlsString, ";") < 0)
        {
            g_ChannelList[0].webhook = new DiscordWebhook(webhookUrlsString);
        }
        else
        {
            char g_WebhookUrlsList[sizeof(g_ChannelList)][MAX_AVATAR_URL_LENGTH];
            ExplodeString(webhookUrlsString, ";", g_WebhookUrlsList, sizeof(g_WebhookUrlsList), sizeof(g_WebhookUrlsList[]));

            for (int i = 0; i < g_ChannelListCount; i++)
            {
                if (!g_ChannelList[i].WebhookAvailable())
                {
                    g_ChannelList[i].webhook = new DiscordWebhook(g_WebhookUrlsList[i]);
                    g_ChannelList[i].webhook.SetAvatarData("");
                }
            }
        }
    }

    GetConVarString(g_cvSteamApiKey, g_SteamApiKey, sizeof(g_SteamApiKey));

    GetConVarString(g_cvWebhookName, g_WebhookName, sizeof(g_WebhookName));
}

void SetupDiscordBot()
{
    TeardownDiscordBot();

    char tokenString[80];
    GetConVarString(g_cvBotToken, tokenString, sizeof(tokenString));

    if (StrEqual(tokenString, ""))
    {
        logger.ThrowError(LogLevel_Fatal, "Discord token needs to be filled in, you can set it in cfg/sourcemod/" ... PLUGIN_SHORTNAME... ".cfg");
        return;
    }

    g_Discord           = new Discord(tokenString);

    bool startedSuccess = g_Discord.Start();

    if (g_Discord == INVALID_HANDLE || !startedSuccess)
    {
        logger.ThrowError(LogLevel_Fatal, "Could not create Discord object, try checking your token, you can set it in cfg/sourcemod/" ... PLUGIN_SHORTNAME... ".cfg");
        return;
    }
}

void TeardownDiscordBot()
{
    g_BotReady = false;

    if (g_Discord != INVALID_HANDLE)
    {
        if (TranslationPhraseExists(TRANSLATION_BOT_STOP_EVENT))
        {
            SendToDiscordEx(TRANSLATION_BOT_STOP_EVENT, FormatServerBlock(GetPlayers(false)));
        }

        g_Discord.Stop();
    }

    delete t_Timer;
    delete g_Discord;
}

public void Discord_OnReady(Discord discord)
{
    g_BotReady = true;

    discord.GetBotName(g_BotName, sizeof(g_BotName));
    discord.GetBotId(g_BotId, sizeof(g_BotId));

    logger.InfoEx("Bot %s (ID: %s) is ready!", g_BotName, g_BotId);

    g_Discord.RegisterGlobalSlashCommand("ping", "Check bot latency");
    if (TranslationPhraseExists(TRANSLATION_STATUS_COMMAND_LINE) && TranslationPhraseExists(TRANSLATION_STATUS_COMMAND_FOOTER))
    {
        g_Discord.RegisterGlobalSlashCommand("status", "Fetch various information about the server.");
    }

    logger.DebugEx("Getting output channel names...");
    for (int i = 0; i < g_ChannelListCount; i++)
    {
        g_Discord.GetChannel(g_ChannelList[i].id, OnGetChannelCallback, i);
        if (g_cvWebhookModeEnable.BoolValue)
        {
            g_Discord.GetChannelWebhooks(g_ChannelList[i].id, OnGetChannelWebhooks, i);
        }
    }

    t_Timer = CreateTimer(g_cvPresenceUpdateInterval.FloatValue, UpdatePresenceTimer, 0, TIMER_REPEAT);
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
        if (!TranslationPhraseExists(TRANSLATION_STATUS_COMMAND_TITLE) || !TranslationPhraseExists(TRANSLATION_STATUS_COMMAND_LINE))
        {
            return;
        }

        int  playerCount = GetPlayers(true);

        // TODO This should not be hardcoded
        char playersString[(3 * 2 + 1) + 10];
        FormatEx(playersString, sizeof(playersString), "Players (%d/%d)", playerCount, MaxClients);

        DiscordEmbed embed = new DiscordEmbed();
        if (TranslationPhraseExists(TRANSLATION_STATUS_COMMAND_TITLE))
        {
            char title[DISCORD_FIELD_LENGTH];
            FormatEx(title, sizeof(title), "%t", TRANSLATION_STATUS_COMMAND_TITLE, FormatServerBlock(GetPlayers(false)));

            embed.SetTitle(title);
        }

        if (TranslationPhraseExists(TRANSLATION_STATUS_COMMAND_DESC))
        {
            char description[DISCORD_FIELD_LENGTH];
            FormatEx(description, sizeof(description), "%t", TRANSLATION_STATUS_COMMAND_DESC, FormatServerBlock(GetPlayers(false)));

            embed.SetDescription(description);
        }

        if (TranslationPhraseExists(TRANSLATION_STATUS_COMMAND_LINE))
        {
            char playerLines[DISCORD_FIELD_LENGTH];
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsValidClient(i))
                {
                    int  team = GetClientTeam(i);
                    char teamName[MAX_TEAM_NAME];
                    teamName = GetTeamNameEx(team);
                    FormatEx(playerLines, sizeof(playerLines), i == 0 ? "%s%t" : "%s\n%t", i == 0 ? "" : playerLines, TRANSLATION_STATUS_COMMAND_LINE,
                             FormatPlayerBlock(i),
                             FormatServerBlock(playerCount));
                }
            }
            embed.AddField(playersString, playerLines, false);
        }

        if (TranslationPhraseExists(TRANSLATION_STATUS_COMMAND_FOOTER))
        {
            char footerStr[DISCORD_FOOTER_LENGTH];
            FormatEx(footerStr, sizeof(footerStr), "%t", TRANSLATION_STATUS_COMMAND_FOOTER, FormatServerBlock(playerCount));

            embed.SetFooter(footerStr);
        }

        interaction.CreateEphemeralResponseEmbed("", embed);
        delete embed;
    }
}

public void Discord_OnMessage(Discord discord, DiscordMessage message)
{
    DiscordUser author = message.GetAuthor();
    char        authorId[SNOWFLAKE_SIZE];
    author.GetId(authorId, sizeof(authorId));

    char channelId[SNOWFLAKE_SIZE];
    message.GetChannelId(channelId, sizeof(channelId));

    bool messageFromSelf = StrEqual(authorId, g_BotId);
    if (!messageFromSelf || message.IsBot())
    {
        for (int i = 0; i < g_ChannelListCount; i++)
        {
            if (g_ChannelList[i].WebhookAvailable())
            {
                char webhookId[SNOWFLAKE_SIZE];
                g_ChannelList[i].webhook.GetId(webhookId, sizeof(webhookId));
                if (g_ChannelList[i].IsEqual(channelId) && !StrEqual(webhookId, authorId))
                {
                    g_ChannelList[i].lastAuthor = authorId;
                }
            }
        }
    }

    bool inListedChannel;
    for (int i = 0; i < g_ChannelListCount; i++)
    {
        if (g_ChannelList[i].IsEqual(channelId))
        {
            inListedChannel = true;
        }
    }

    if (!inListedChannel || messageFromSelf || message.IsBot() || !g_cvDiscordSendEnable.BoolValue || !TranslationPhraseExists(TRANSLATION_DISCORD_SERVER_MESSAGE))
    {
        return;
    }

    char content[MAX_MESSAGE_LENGTH];
    message.GetContent(content, sizeof(content));

    char username[MAX_DISCORD_NAME_LENGTH];
    author.GetUsername(username, sizeof(username));

    char displayName[MAX_DISCORD_NAME_LENGTH];
    author.GetGlobalName(displayName, sizeof(displayName));

    char nickname[MAX_DISCORD_NAME_LENGTH];
    message.GetAuthorNickname(nickname, sizeof(nickname));

    int authorDescriminator = author.GetDiscriminator();
    int playerCount         = GetPlayers(false);

    if (StrEqual(nickname, ""))
    {
        nickname = displayName;
    }

    if (!g_cvDiscordColorCodesEnable.BoolValue)
    {
        CRemoveTags(username, sizeof(username));
        CRemoveTags(content, sizeof(content));
        CRemoveTags(displayName, sizeof(displayName));
        CRemoveTags(nickname, sizeof(nickname));
    }

    int originalChannel;
    for (int i = 0; i < g_ChannelListCount; i++)
    {
        if (g_ChannelList[i].IsEqual(channelId))
        {
            originalChannel = i;
            CPrintToChatAll("%t", TRANSLATION_DISCORD_SERVER_MESSAGE,
                            FormatDiscordMessageBlock(i),
                            FormatServerBlock(playerCount));
        }
    }

    for (int i = 0; i < g_ChannelListCount; i++)
    {
        if (i != originalChannel)
        {
            if (TranslationPhraseExists(TRANSLATION_DISCORD_DISCORD_MESSAGE))
            {
                char webhookName[MAX_DISCORD_NAME_LENGTH];
                webhookName = nickname;
                if (TranslationPhraseExists(TRANSLATION_DISCORD_DISCORD_NAME))
                {
                    FormatEx(webhookName, sizeof(webhookName), "%t", TRANSLATION_DISCORD_DISCORD_NAME,
                             FormatDiscordMessageBlock(originalChannel),
                             FormatServerBlock(playerCount));
                }

                char finalContent[MAX_DISCORD_MESSAGE_LENGTH];
                FormatEx(finalContent, sizeof(finalContent), "%t", TRANSLATION_DISCORD_DISCORD_MESSAGE,
                         FormatDiscordMessageBlock(originalChannel),
                         FormatServerBlock(playerCount));

                char avatarUrl[MAX_AVATAR_URL_LENGTH];
                author.GetAvatarUrl(false, avatarUrl, sizeof(avatarUrl));
                SendToDiscordChannel(g_ChannelList[i], finalContent, webhookName, -1, avatarUrl);
            }
        }
    }

    delete author;
}

public void Discord_OnError(Discord discord, const char[] error)
{
    logger.Debug(error);
}

void OnGetChannelCallback(Discord discord, DiscordChannel channel, int index)
{
    channel.GetName(g_ChannelList[index].name, sizeof(g_ChannelList[].name));
    CRemoveTags(g_ChannelList[index].name, sizeof(g_ChannelList[].name));

    logger.DebugEx("Outputting to: #%s", g_ChannelList[index].name);

    if (index == g_ChannelListCount - 1 && TranslationPhraseExists(TRANSLATION_BOT_START_EVENT))
    {
        SendToDiscordEx(TRANSLATION_BOT_START_EVENT, FormatServerBlock(GetPlayers(false)));
    }
}

public void OnGetChannelWebhooks(Discord discord, DiscordWebhook[] webhookMap, float count, any data)
{
    logger.Debug("Channel Webhooks:");
    for (int i = 0; i < count; i++)
    {
        char webhookName[MAX_DISCORD_NAME_LENGTH];
        webhookMap[i].GetName(webhookName, sizeof(webhookName));
        DiscordUser user = webhookMap[i].GetUser();
        char        userId[MAX_DISCORD_NAME_LENGTH];
        user.GetId(userId, sizeof(userId));
        logger.DebugEx("Webhook %s: %s", webhookName, userId);

        if (!g_ChannelList[data].WebhookAvailable() && WebhookIsMine(webhookMap[i]))
        {
            g_ChannelList[data].webhook = view_as<DiscordWebhook>(CloneHandle(webhookMap[i]));
            g_ChannelList[data].webhook.SetAvatarData("");
        }
    }

    if (!g_ChannelList[data].WebhookAvailable())
    {
        g_Discord.CreateWebhook(g_ChannelList[data].id, g_WebhookName, OnCreateWebhook, data);
    }
}

void OnCreateWebhook(Discord discord, DiscordWebhook wh, any data)
{
    g_ChannelList[data].webhook = view_as<DiscordWebhook>(CloneHandle(wh));
}

bool WebhookIsMine(DiscordWebhook wh)
{
    DiscordUser user = wh.GetUser();

    char        webhookName[MAX_DISCORD_NAME_LENGTH];
    char        userId[MAX_DISCORD_NAME_LENGTH];

    wh.GetName(webhookName, sizeof(webhookName));
    user.GetId(userId, sizeof(userId));

    delete user;
    return StrEqual(g_WebhookName, webhookName) && StrEqual(userId, g_BotId);
}

void SendToDiscordChannel(const ChannelInfo channel, char[] content, char[] username, int client, char avatarUrlOverride[MAX_AVATAR_URL_LENGTH] = "")
{
    if (!BotRunning(g_Discord))
    {
        logger.ErrorEx("Bot not running! Can't send message: %s", content);
        return;
    }

    if (g_cvWebhookModeEnable.BoolValue && channel.WebhookAvailable())
    {
        DiscordWebhook webhook = channel.webhook;
        webhook.SetName(username);
        char avatarUrl[MAX_AVATAR_URL_LENGTH];
        if (StrEqual(avatarUrlOverride, ""))
        {
            avatarUrl = client > 0 ? g_SteamAvatars[client] : "";
        }
        else
        {
            avatarUrl = avatarUrlOverride;
        }
        webhook.SetAvatarUrl(avatarUrl);
        g_Discord.ExecuteWebhook(webhook, content);
    }
    else
    {
        g_Discord.SendMessage(channel.id, content);
    }
}

void SendToDiscord(char[] content, char[] username, int client, char avatarUrlOverride[MAX_AVATAR_URL_LENGTH] = "")
{
    if (!BotRunning(g_Discord))
    {
        logger.ErrorEx("Bot not running! Can't send message: %s", content);
        return;
    }

    for (int i = 0; i < g_ChannelListCount; i++)
    {
        SendToDiscordChannel(g_ChannelList[i], content, username, client, avatarUrlOverride);
    }
}

/**
 * Assumed to be an event. First parameter must be a translation phrase.
 */
void SendToDiscordEx(any...)
{
    if (!BotRunning(g_Discord))
    {
        logger.Error("Bot not running! Can't send event.");
        return;
    }

    char name[MAX_DISCORD_NAME_LENGTH];
    FormatEx(name, sizeof(name), "%t", TRANSLATION_WEBHOOK_EVENTS, FormatServerBlock(GetPlayers(false)));

    char content[MAX_DISCORD_MESSAGE_LENGTH];
    VFormat(content, sizeof(content), "%t", 1);

    SendToDiscord(content, name, -1);

    // Clear LastAuthorList because we are sending an event
    for (int i = 0; i < g_ChannelListCount; i++)
    {
        g_ChannelList[i].lastAuthor = "";
    }
}

public Action UpdatePresenceTimer(Handle timer, any data)
{
    UpdatePresence();

    return Plugin_Continue;
}

public Action OnMapStartGracePeriod(Handle timer, any data)
{
    g_AllowConnectEvents = true;
    return Plugin_Handled;
}

void OnNextMapChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    CacheNextMapName();
}

void UpdatePresence()
{
    if (!TranslationPhraseExists(TRANSLATION_STATUS) || !TranslationPhraseExists(TRANSLATION_STATUS_PLURAL))
    {
        return;
    }

    char playerCountStr[MAX_DISCORD_PRESENCE_LENGTH];
    int  playerCount = GetPlayers(false);
    FormatEx(playerCountStr, sizeof(playerCountStr), "%t",
             playerCount == 1 ? TRANSLATION_STATUS : TRANSLATION_STATUS_PLURAL,
             FormatServerBlock(playerCount));
    g_Discord.SetPresence(g_ServerIdle ? Presence_Idle : Presence_Online, Activity_Custom, playerCountStr);
}

bool BotRunning(Discord bot)
{
    return bot != INVALID_HANDLE && bot.IsRunning();
}

public void OnPluginEnd()
{
    TeardownDiscordBot();

    for (int i = 0; i < g_ChannelListCount; i++)
    {
        delete g_ChannelList[i].webhook;
    }

    delete g_BannedWords;

    DestroyLogging();
}
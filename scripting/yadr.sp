#define PLUGIN_NAME        "Yet Another Discord Relay"
#define PLUGIN_SHORTNAME   "yadr"
#define PLUGIN_TRANS_FILE  "yadr.phrases"
#define PLUGIN_AUTHOR      "Enova"
#define PLUGIN_DESCRIPTION "Discord Relay with a focus on clean compact output and performance."
#define PLUGIN_VERSION     "1.0"
#define PLUGIN_URL         "https://github.com/Enovale/of-yadr"

#include <sourcemod>
#include <sdktools>
#include <chat-processor>
#include <discord>

#include "yadr/format_vars.sp"
#include "yadr/translation_phrases.sp"

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name        = PLUGIN_NAME,
    author      = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version     = PLUGIN_VERSION,
    url         = PLUGIN_URL
};

ConVar         g_cvBotToken;
ConVar         g_cvSteamApiKey;
ConVar         g_cvChannelIds;
ConVar         g_cvWebhookModeEnable;
ConVar         g_cvWebhookName;
ConVar         g_cvWebhookUrlOverrides;
ConVar         g_cvDiscordSendEnable;
ConVar         g_cvServerSendEnable;
ConVar         g_cvDiscordColorCodesEnable;

ConVar         g_cvVerboseEnable;

// 255 channel list limit is arbitrary
char           g_ChannelList[255][SNOWFLAKE_SIZE];
char           g_ChannelNameList[sizeof(g_ChannelList)][MAX_DISCORD_CHANNEL_NAME_LENGTH];
char           g_ChannelLastAuthorList[sizeof(g_ChannelList)][MAX_AUTHID_LENGTH];
int            g_ChannelListCount;

// Use g_ChannelListCount to iterate
DiscordWebhook g_WebhookList[sizeof(g_ChannelList)];

ArrayList      g_BannedWords;

Discord        g_Discord;
bool           g_BotReady;
char           g_BotName[MAX_DISCORD_NAME_LENGTH];
char           g_BotId[SNOWFLAKE_SIZE];

bool           g_ServerIdle;
Handle         t_Timer;

public void OnPluginStart()
{
    LoadTranslations(PLUGIN_TRANS_FILE);

    g_cvBotToken                = CreateConVar("sm_discord_bot_token", "", "Token for the discord bot to connect to.", FCVAR_PROTECTED);
    g_cvSteamApiKey             = CreateConVar("sm_discord_steam_api_key", "", "Steam Web API key for fetching player avatars.", FCVAR_PROTECTED);
    g_cvChannelIds              = CreateConVar("sm_discord_channel_ids", "", "List of channel IDs, separated by semicolons, to relay between.");
    g_cvWebhookModeEnable       = CreateConVar("sm_discord_webhook_mode_enable", "1", "Enable pretty output with a webhook rather than the more limited bot output.");
    g_cvWebhookName             = CreateConVar("sm_discord_webhook_name", "Yadr Relay", "The name of the webhook to use for webhook output.");
    g_cvWebhookUrlOverrides     = CreateConVar("sm_discord_webhook_urls", "", "List of webhook URLs, separated by semicolons, in the same order as `sm_discord_channel_ids`, to use. If the webhook for a channel is left blank, it will be created if the bot has permission to do so.", FCVAR_PROTECTED);
    g_cvDiscordSendEnable       = CreateConVar("sm_discord_dc_send_enable", "1", "Enable discord messages to be sent to the server.");
    g_cvServerSendEnable        = CreateConVar("sm_discord_server_send_enable", "1", "Enable player messages to be sent to discord.");
    g_cvDiscordColorCodesEnable = CreateConVar("sm_discord_dc_color_codes_enable", "0", "Allows discord->server messages to contain color codes like {grey} or {green}.");

    g_cvVerboseEnable           = CreateConVar("sm_discord_verbose", "0", "Enable verbose logging for the discord backend.");

    if (g_cvVerboseEnable.BoolValue)
    {
        // TODO This seems bad but also I don't know why translations don't reload anyway
        ServerCommand("sm_reload_translations");
    }

    AutoExecConfig(true, PLUGIN_SHORTNAME);
    InitializeLogging(PLUGIN_SHORTNAME, g_cvVerboseEnable.BoolValue ? LogLevel_Debug : LogLevel_Info);

    if (!TranslationPhraseExists(TRANSLATION_DISCORD_SERVER_MESSAGE) && !TranslationPhraseExists(TRANSLATION_SERVER_DISCORD_MESSAGE) && !TranslationPhraseExists(TRANSLATION_WEBHOOK_MESSAGE) && !TranslationPhraseExists(TRANSLATION_STATUS) && !TranslationPhraseExists(TRANSLATION_STATUS_PLURAL))
    {
        logger.ErrorEx("!!!! No translations are specified, bot won't do anything! Please copy and edit `translations/%s.txt`", PLUGIN_TRANS_FILE);
    }

    if (g_HttpClient != null)
        delete g_HttpClient;

    g_HttpClient = new HTTPClient("https://api.steampowered.com");

    logger.Info("Plugin Started!");
}

public void OnConfigsExecuted()
{
    g_cvBotToken.AddChangeHook(OnBotTokenChange);
    g_cvChannelIds.AddChangeHook(OnCvarChange);
    g_cvSteamApiKey.AddChangeHook(OnCvarChange);

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
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/%s_banned_prefixes.txt", PLUGIN_SHORTNAME);
    GetBannedWords(filePath);
}

void GetBannedWords(const char[] path)
{
    if (!FileExists(path))
    {
        Handle fileHandle = OpenFile(path, "w");
        WriteFileString(fileHandle, "!\nrtv\nnominate", false);
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
}

void OnMapOrPluginStart()
{
    if (g_Discord == INVALID_HANDLE)
    {
        SetupDiscordBot();
    }

    if (g_BotReady && TranslationPhraseExists(TRANSLATION_MAP_CHANGE_EVENT))
    {
        SendToDiscordEx(TRANSLATION_MAP_CHANGE_EVENT,
                        g_CachedMapName,
                        g_ServerHostname);
    }
}

public void OnMapInit(const char[] mapName)
{
    CacheExplicitMapName(mapName);
}

public void OnMapEnd()
{
    g_ServerIdle = true;
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

    // TODO These two events should probably at least have the ability to include the player's avatar?
    SendToDiscordEx(TRANSLATION_PLAYER_CONNECT_EVENT,
                    GetClientNameEx(client),
                    g_CachedMapName,
                    g_ServerHostname);
}

public void OnClientDisconnect(int client)
{
    SendToDiscordEx(TRANSLATION_PLAYER_DISCONNECT_EVENT,
                    GetClientNameEx(client),
                    g_CachedMapName,
                    g_ServerHostname);
}

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
    if (!g_cvServerSendEnable.BoolValue || !g_Discord.IsRunning() || !TranslationPhraseExists(TRANSLATION_SERVER_DISCORD_MESSAGE))
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
    teamNameIfSpectator = StrContains(teamName, "Spec", false) == -1 ? "" : teamName;    // TODO This seems not adaptable to other games
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
    char nextMap[MAX_MAP_NAME];
    nextMap          = GetNextMapEx();
    int  playerCount = GetPlayers(false);

    char finalBotContent[MAX_DISCORD_MESSAGE_LENGTH];
    char finalWebhookContent[MAX_DISCORD_MESSAGE_LENGTH];
    char finalPlayerInfoEventContent[MAX_DISCORD_MESSAGE_LENGTH];

    if (TranslationPhraseExists(TRANSLATION_SERVER_DISCORD_MESSAGE))
    {
        FormatEx(finalBotContent, sizeof(finalBotContent), "%t", TRANSLATION_SERVER_DISCORD_MESSAGE,
                 sName,
                 sMessage,
                 author,
                 userId,
                 team,
                 teamName,
                 teamNameIfSpectator,
                 clientIp,
                 authId2,
                 authId64,
                 authId3,
                 authIdEngine,
                 clientConnectionTime,
                 g_SteamAvatars[author],
                 g_CachedMapName,
                 nextMap,
                 g_ServerHostname,
                 g_ServerIpStr,
                 g_ServerPort,
                 playerCount,
                 g_MaxPlayers);
    }

    if (TranslationPhraseExists(TRANSLATION_WEBHOOK_MESSAGE))
    {
        FormatEx(finalWebhookContent, sizeof(finalWebhookContent), "%t", TRANSLATION_WEBHOOK_MESSAGE,
                 sName,
                 sMessage,
                 author,
                 userId,
                 team,
                 teamName,
                 teamNameIfSpectator,
                 clientIp,
                 authId2,
                 authId64,
                 authId3,
                 authIdEngine,
                 clientConnectionTime,
                 g_SteamAvatars[author],
                 g_CachedMapName,
                 nextMap,
                 g_ServerHostname,
                 g_ServerIpStr,
                 g_ServerPort,
                 playerCount,
                 g_MaxPlayers);
    }

    if (TranslationPhraseExists(TRANSLATION_PLAYER_INFO_EVENT))
    {
        FormatEx(finalPlayerInfoEventContent, sizeof(finalPlayerInfoEventContent), "%t", TRANSLATION_PLAYER_INFO_EVENT,
                 sName,
                 sMessage,
                 author,
                 userId,
                 team,
                 teamName,
                 teamNameIfSpectator,
                 clientIp,
                 authId2,
                 authId64,
                 authId3,
                 authIdEngine,
                 clientConnectionTime,
                 g_SteamAvatars[author],
                 g_CachedMapName,
                 nextMap,
                 g_ServerHostname,
                 g_ServerIpStr,
                 g_ServerPort,
                 playerCount,
                 g_MaxPlayers);
    }

    for (int i = 0; i < g_ChannelListCount; i++)
    {
        bool webhookAvailable = WebhookAvailable(g_WebhookList[i]);
        char webhookName[MAX_DISCORD_NAME_LENGTH];
        FormatEx(webhookName, sizeof(webhookName), "%s", sName);

        if (webhookAvailable)
        {
            FormatEx(webhookName, sizeof(webhookName), "%t", TRANSLATION_WEBHOOK_NAME,
                     sName,
                     sMessage,
                     author,
                     userId,
                     team,
                     teamName,
                     teamNameIfSpectator,
                     clientIp,
                     authId2,
                     authId64,
                     authId3,
                     authIdEngine,
                     clientConnectionTime,
                     g_SteamAvatars[author],
                     g_CachedMapName,
                     nextMap,
                     g_ServerHostname,
                     g_ServerIpStr,
                     g_ServerPort,
                     playerCount,
                     g_MaxPlayers);
        }

        logger.InfoEx("Old: %s, New: %s", g_ChannelLastAuthorList[i], authIdEngine);
        if (TranslationPhraseExists(TRANSLATION_PLAYER_INFO_EVENT) && !StrEqual(g_ChannelLastAuthorList[i], authIdEngine))
        {
            char eventName[MAX_DISCORD_NAME_LENGTH];
            FormatEx(eventName, sizeof(eventName), "%t", TRANSLATION_WEBHOOK_EVENTS);
            
            if ((webhookAvailable ? strlen(finalWebhookContent) + strlen(finalPlayerInfoEventContent) : strlen(finalBotContent) + strlen(finalPlayerInfoEventContent)) < MAX_DISCORD_MESSAGE_LENGTH)
            {
                Format(webhookAvailable ? finalWebhookContent : finalBotContent, sizeof(finalWebhookContent), "%s\n%s", finalPlayerInfoEventContent, webhookAvailable ? finalWebhookContent : finalBotContent);
            }
            else
            {
                SendToDiscordChannel(g_ChannelList[i], g_WebhookList[i], finalPlayerInfoEventContent, webhookName, -1);
            }
        }

        SendToDiscordChannel(g_ChannelList[i], g_WebhookList[i], webhookAvailable ? finalWebhookContent : finalBotContent, webhookName, author);
        g_ChannelLastAuthorList[i] = authIdEngine;
    }

    return Plugin_Continue;
}

void UpdateCvars()
{
    char channelIdsString[sizeof(g_ChannelList) * sizeof(g_ChannelList[])];
    GetConVarString(g_cvChannelIds, channelIdsString, sizeof(channelIdsString));

    if (!StrContains(channelIdsString, ";"))
    {
        FormatEx(g_ChannelList[0], sizeof(g_ChannelList[]), channelIdsString);
        g_ChannelListCount = 1;
    }
    else
    {
        g_ChannelListCount = ExplodeString(channelIdsString, ";", g_ChannelList, sizeof(g_ChannelList), sizeof(g_ChannelList[]));
    }

    if (g_ChannelListCount <= 0)
    {
        logger.ThrowErrorEx(LogLevel_Fatal, "No output channels specified! Please add them in your cvar config.");
        return;
    }

    char webhookUrlsString[MAX_BUFFER_LENGTH];
    GetConVarString(g_cvWebhookUrlOverrides, webhookUrlsString, sizeof(webhookUrlsString));

    if (!StrContains(webhookUrlsString, ";"))
    {
        g_WebhookList[0] = new DiscordWebhook(webhookUrlsString);
    }
    else
    {
        // TODO Double check that this is sane, I'm tired
        // 256 Is arbitrary, but webhook URLs should definitely never be bigger than that
        char g_WebhookUrlsList[sizeof(g_ChannelList)][256];
        ExplodeString(webhookUrlsString, ";", g_WebhookUrlsList, sizeof(g_WebhookUrlsList), sizeof(g_WebhookUrlsList[]));

        for (int i = 0; i < g_ChannelListCount; i++)
        {
            g_WebhookList[i] = new DiscordWebhook(g_WebhookUrlsList[i]);
        }
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
        logger.ThrowErrorEx(LogLevel_Fatal, "Discord token needs to be filled in, you can set it in cfg/sourcemod/%s.cfg", PLUGIN_SHORTNAME);
        return;
    }

    g_Discord           = new Discord(tokenString);

    bool startedSuccess = g_Discord.Start();

    if (g_Discord == INVALID_HANDLE || !startedSuccess)
    {
        logger.ThrowErrorEx(LogLevel_Fatal, "Could not create Discord object, try checking your token, you can set it in cfg/sourcemod/%s.cfg", PLUGIN_SHORTNAME);
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
            SendToDiscordEx(TRANSLATION_BOT_STOP_EVENT, g_BotName);
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
    g_Discord.RegisterGlobalSlashCommand("status", "Fetch various information about the server.");
    // g_Discord.RegisterGlobalSlashCommand("ban", "Ban a player from the server.");
    // g_Discord.RegisterGlobalSlashCommand("kick", "Kick a player from the server.");

    logger.DebugEx("Getting output channel names...");
    for (int i = 0; i < g_ChannelListCount; i++)
    {
        g_Discord.GetChannel(g_ChannelList[i], OnGetChannelCallback, i);
        g_Discord.GetChannelWebhooks(g_ChannelList[i], OnGetChannelWebhooks, i);
    }

    t_Timer = CreateTimer(5.0, UpdatePresenceTimer, 0, TIMER_REPEAT);
}

public void OnGetChannelWebhooks(Discord discord, DiscordWebhook[] webhookMap, float count, any data)
{
    logger.Info("Channel Webhooks:");
    for (int i = 0; i < count; i++)
    {
        char tempBuffer[MAX_DISCORD_NAME_LENGTH];
        webhookMap[i].GetName(tempBuffer, sizeof(tempBuffer));
        logger.Info(tempBuffer);
    }
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

    char channelId[SNOWFLAKE_SIZE];
    message.GetChannelId(channelId, sizeof(channelId));

    bool messageFromSelf = StrEqual(authorId, g_BotId);
    if (!messageFromSelf || message.IsBot())
    {
        for (int i = 0; i < g_ChannelListCount; i++)
        {
            char webhookId[SNOWFLAKE_SIZE];
            g_WebhookList[i].GetId(webhookId, sizeof(webhookId));
            if (StrEqual(channelId, g_ChannelList[i]) && !StrEqual(webhookId, authorId))
            {
                g_ChannelLastAuthorList[i] = authorId;
            }
        }
    }

    if (messageFromSelf || message.IsBot() || !g_cvDiscordSendEnable.BoolValue || !TranslationPhraseExists(TRANSLATION_DISCORD_SERVER_MESSAGE))
    {
        return;
    }

    char content[MAX_MESSAGE_LENGTH];
    message.GetContent(content, sizeof(content));

    char authorName[MAX_DISCORD_NAME_LENGTH];
    message.GetAuthorName(authorName, sizeof(authorName));

    if (!g_cvDiscordColorCodesEnable.BoolValue)
    {
        CRemoveTags(authorName, sizeof(authorName));
        CRemoveTags(content, sizeof(content));
    }

    for (int i = 0; i < g_ChannelListCount; i++)
    {
        if (StrEqual(channelId, g_ChannelList[i]))
        {
            logger.Debug(content);

            int authorDescriminator = message.GetAuthorDiscriminator();

            CPrintToChatAll("%t", TRANSLATION_DISCORD_SERVER_MESSAGE, authorName,
                            content,
                            g_ChannelNameList[i],
                            authorId,
                            authorDescriminator,
                            channelId);
            break;
        }
    }
}

public void Discord_OnError(Discord discord, const char[] error)
{
    logger.Debug(error);
}

void OnGetChannelCallback(Discord discord, DiscordChannel channel, int index)
{
    channel.GetName(g_ChannelNameList[index], sizeof(g_ChannelNameList[]));
    CRemoveTags(g_ChannelNameList[index], sizeof(g_ChannelNameList[]));

    logger.InfoEx("Outputting to: #%s", g_ChannelNameList[index]);

    if (index == g_ChannelListCount - 1 && TranslationPhraseExists(TRANSLATION_BOT_START_EVENT))
    {
        SendToDiscordEx(TRANSLATION_BOT_START_EVENT, g_BotName);
    }
}

void SendToDiscordChannel(char[] channelId, DiscordWebhook webhook, char[] content, char[] username, int client)
{
    if (!g_Discord.IsRunning())
    {
        logger.ErrorEx("Bot not running! Can't send message: %s", content);
        return;
    }

    logger.Debug(content);

    if (g_cvWebhookModeEnable.BoolValue && WebhookAvailable(webhook))
    {
        webhook.SetName(username);
        g_Discord.ExecuteWebhook(webhook, content);
    }
    else
    {
        g_Discord.SendMessage(channelId, content);
    }
}

void SendToDiscord(char[] content, char[] username, int client)
{
    if (!g_Discord.IsRunning())
    {
        logger.ErrorEx("Bot not running! Can't send message: %s", content);
        return;
    }

    for (int i = 0; i < g_ChannelListCount; i++)
    {
        SendToDiscordChannel(g_ChannelList[i], g_WebhookList[i], content, username, client);
    }
}

/**
 * Assumed to be an event. First parameter must be a translation phrase.
 */
void SendToDiscordEx(any...)
{
    if (!g_Discord.IsRunning())
    {
        logger.Error("Bot not running! Can't send event.");
        return;
    }

    char name[MAX_DISCORD_NAME_LENGTH];
    FormatEx(name, sizeof(name), "%t", TRANSLATION_WEBHOOK_EVENTS);

    char content[MAX_DISCORD_MESSAGE_LENGTH];
    VFormat(content, sizeof(content), "%t", 1);

    SendToDiscord(content, name, -1);

    // Clear LastAuthorList because we are sending an event
    for (int i = 0; i < g_ChannelListCount; i++)
    {
        g_ChannelLastAuthorList[i] = "";
    }
}

public Action UpdatePresenceTimer(Handle timer, any data)
{
    UpdatePresence();

    return Plugin_Continue;
}

void UpdatePresence()
{
    if (!TranslationPhraseExists(TRANSLATION_STATUS) || !TranslationPhraseExists(TRANSLATION_STATUS_PLURAL))
    {
        return;
    }

    char playerCountStr[MAX_DISCORD_PRESENCE_LENGTH];
    int  clientCount = GetPlayers(false);
    FormatEx(playerCountStr, sizeof(playerCountStr), "%t",
             clientCount == 1 ? TRANSLATION_STATUS : TRANSLATION_STATUS_PLURAL,
             clientCount,
             g_MaxPlayers,
             g_CachedMapName,
             GetNextMapEx(),
             g_ServerHostname,
             g_ServerIpStr,
             g_ServerPort);
    g_Discord.SetPresence(g_ServerIdle ? Presence_Idle : Presence_Online, Activity_Custom, playerCountStr);
}

public void OnPluginEnd()
{
    TeardownDiscordBot();

    for(int i = 0; i < g_ChannelListCount; i++)
    {
        delete g_WebhookList[i];
    }

    delete g_BannedWords;

    DestroyLogging();
}
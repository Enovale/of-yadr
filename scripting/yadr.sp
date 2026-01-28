#define PLUGIN_NAME        "Yet Another Discord Relay"
#define PLUGIN_AUTHOR      "Enova"
#define PLUGIN_DESCRIPTION "Discord Relay with a focus on clean compact output and performance."
#define PLUGIN_VERSION     "1.0.0"
#define PLUGIN_URL         "https://github.com/Enovale/of-" ... PLUGIN_SHORTNAME

#include <sourcemod>
#include <sdktools>
#include <chat-processor>
#include <discord>
#undef REQUIRE_PLUGIN
#include <sourcebanspp>
#include <updater>
#define REQUIRE_PLUGIN

#include "yadr/format_vars.sp"
#include "yadr/translation_phrases.sp"
#include "yadr/structs.sp"
#include "yadr/cvars.sp"
#include "yadr/natives.sp"
#include <yadr>

#pragma newdecls required
#pragma semicolon 1
#pragma tabsize 2

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
                                      g_ServerTagsStr,        \
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

#define IsCommandEnabled(%0) g_cvCommandEnableBits.IntValue & %0 == %0
#define IsEventEnabled(%0,%1) g_ChannelList[%0].enabledEvents & %1 == %1

#define dType DiscordCommandOptionType

// clang-format on
public Plugin myinfo =
{
  name        = PLUGIN_NAME,
  author      = PLUGIN_AUTHOR,
  description = PLUGIN_DESCRIPTION,
  version     = PLUGIN_VERSION,
  url         = PLUGIN_URL
};

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
  LoadTranslations("common.phrases");
  LoadTranslations(PLUGIN_TRANS_PHRASES_FILE);
  LoadTranslations(PLUGIN_TRANS_INFO_FILE);

  RegisterCmds();

  CreateCvars();

  RegServerCmd(PLUGIN_CONVAR_PREFIX... "delete_commands", DeleteCommandsCmd, "Deletes all slash commands associated with this bot, in case you've changed the enabled commands bits.");

  // TODO This seems bad but also I don't know why translations don't reload anyway
  ServerCommand("sm_reload_translations");

  AutoExecConfig(true, PLUGIN_SHORTNAME);
  InitializeLogging(PLUGIN_SHORTNAME, g_cvVerboseEnable.BoolValue ? LogLevel_Debug : LogLevel_Info);

  if (!TranslationExistsAndNotEmpty(TRANSLATION_DISCORD_SERVER_MESSAGE) && !TranslationExistsAndNotEmpty(TRANSLATION_SERVER_DISCORD_MESSAGE) && !TranslationExistsAndNotEmpty(TRANSLATION_WEBHOOK_MESSAGE) && !TranslationExistsAndNotEmpty(TRANSLATION_STATUS) && !TranslationExistsAndNotEmpty(TRANSLATION_STATUS_PLURAL))
  {
    logger.Error("!!!! No translations are specified, bot won't do anything! Please copy and edit `translations/" ... PLUGIN_TRANS_INFO_FILE... ".txt`");
  }

  HookEvent("player_changename", OnPlayerChangeName);
  HookEvent("player_disconnect", OnPlayerDisconnect, EventHookMode_Pre);

  logger.Info("Plugin Started!");
}

public void OnConfigsExecuted()
{
  g_cvBotToken.AddChangeHook(OnBotTokenChange);
  AddCvarHooks();
  FindConVar("sm_nextmap").AddChangeHook(OnNextMapChanged);

  if (LibraryExists("updater"))
  {
    char url[MAX_BUFFER_LENGTH];
    g_cvUpdateUrl.GetString(url, sizeof(url));
    Updater_AddPlugin(url);
  }

  UpdateCvars();

  CacheFormatVars();

  CacheMapList();

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

  logger.DebugEx("RCON: %i, PSAY: %i, BAN: %i, KICK: %i, CHANGELEVEL: i", IsCommandEnabled(COMMAND_RCON), IsCommandEnabled(COMMAND_PSAY), IsCommandEnabled(COMMAND_BAN), IsCommandEnabled(COMMAND_KICK), IsCommandEnabled(COMMAND_CHANGELEVEL));
}

public int Updater_OnPluginUpdated()
{
  ReloadPlugin();
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

  g_AllowConnectEvents = GetPlayers(false) > 0 ? false : true;

  CreateTimer(g_cvMapChangeGracePeriod.FloatValue, OnMapStartGracePeriod);
}

void OnMapOrPluginStart()
{
  if (!BotRunning(g_Discord))
  {
    SetupDiscordBot();
  }

  if (g_BotReady && TranslationExistsAndNotEmpty(TRANSLATION_MAP_CHANGE_EVENT))
  {
    SendEventToDiscord(TRANSLATION_MAP_CHANGE_EVENT, FormatServerBlock(GetPlayers(false)));
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
  g_ServerIdle         = false;
  g_AllowConnectEvents = true;
  if (t_Timer)
  {
    TriggerTimer(t_Timer);
  }
}

public void OnClientPostAdminCheck(int client)
{
  if (!IsRealClient(client)) {
    return Plugin_Continue;
  }

  GetProfilePic(client);

  if (!g_ServerIdle && g_AllowConnectEvents && TranslationExistsAndNotEmpty(TRANSLATION_PLAYER_CONNECT_EVENT))
  {
    int  team = GetClientTeamEx(client);
    char teamName[MAX_TEAM_NAME];
    teamName = GetTeamNameEx(team);
    SendEventToDiscord(TRANSLATION_PLAYER_CONNECT_EVENT,
                       FormatPlayerBlock(client),
                       FormatServerBlock(GetPlayers(false)));
  }
}

Action OnPlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
  if (!g_ServerIdle && g_AllowConnectEvents && TranslationExistsAndNotEmpty(TRANSLATION_PLAYER_DISCONNECT_EVENT))
  {
    int  client = GetClientOfUserId(GetEventInt(event, "userid"));
    char reason[MAX_MESSAGE_LENGTH];
    GetEventString(event, "reason", reason, sizeof(reason));
    ReplaceString(reason, sizeof(reason), "\n", " ");

    if (!IsRealClient(client)) {
      return Plugin_Continue;
    }

    if ((1 <= client <= MaxClients) && !IsClientInGame(client))
    {
      logger.DebugEx("Client disconnected without being in-game: %i", client);
      return Plugin_Continue;
    }

    int  team = GetClientTeamEx(client);
    char teamName[MAX_TEAM_NAME];
    teamName = GetTeamNameEx(team);
    SendEventToDiscord(TRANSLATION_PLAYER_DISCONNECT_EVENT,
                       reason,
                       FormatPlayerBlock(client),
                       FormatServerBlock(GetPlayers(false)));
  }

  return Plugin_Continue;
}

void OnPlayerBanned(int client, int time, const char[] reason)
{
  if (TranslationExistsAndNotEmpty(TRANSLATION_PLAYER_BAN_EVENT))
  {
    int  team = GetClientTeamEx(client);
    char teamName[MAX_TEAM_NAME];
    teamName = GetTeamNameEx(team);
    SendEventToDiscordEx(EVENT_BAN, TRANSLATION_PLAYER_BAN_EVENT,
                         time,
                         reason,
                         FormatPlayerBlock(client),
                         FormatServerBlock(GetPlayers(false)));
  }
}

public Action OnBanClient(int client, int time, int flags, const char[] reason, const char[] kick_message, const char[] command, any source)
{
  if (!IsValidClient(client) || LibraryExists("sourcebans++"))
    return Plugin_Continue;

  OnPlayerBanned(client, time, reason);
  return Plugin_Continue;
}

public void SBPP_OnBanPlayer(int iAdmin, int iTarget, int iTime, const char[] sReason)
{
  if (!IsValidClient(iTarget))
    return;

  OnPlayerBanned(iTarget, iTime, sReason);
}

public void SBPP_OnReportPlayer(int iReporter, int iTarget, const char[] sReason)
{
  if (!IsValidClient(iReporter) || !IsValidClient(iTarget) || !TranslationExistsAndNotEmpty(TRANSLATION_PLAYER_REPORT_EVENT))
    return;

  int  team = GetClientTeamEx(iTarget);
  char teamName[MAX_TEAM_NAME];
  teamName = GetTeamNameEx(team);
  SendEventToDiscordEx(EVENT_REPORT, TRANSLATION_PLAYER_REPORT_EVENT,
                       sReason,
                       FormatPlayerBlock(iTarget),
                       FormatServerBlock(GetPlayers(false)));
}

// TODO Not used very often and it would be a giant pain to get all the player info from just an identity... We stub this for now
public Action OnBanIdentity(const char[] identity, int time, int flags, const char[] reason, const char[] command, any source)
{
  logger.Debug("OnBanIdentity!");
  return Plugin_Continue;
}

Action OnPlayerChangeName(Event event, const char[] name, bool dontBroadcast)
{
  if (TranslationExistsAndNotEmpty(TRANSLATION_PLAYER_NAME_CHANGE_EVENT))
  {
    int  client = GetClientOfUserId(GetEventInt(event, "userid"));
    char newName[MAX_NAME_LENGTH];
    GetEventString(event, "newname", newName, sizeof(newName));

    int  team = GetClientTeamEx(client);
    char teamName[MAX_TEAM_NAME];
    teamName = GetTeamNameEx(team);
    SendEventToDiscord(TRANSLATION_PLAYER_NAME_CHANGE_EVENT,
                       newName,
                       FormatPlayerBlock(client),
                       FormatServerBlock(GetPlayers(false)));
  }

  return Plugin_Continue;
}

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
  if (!g_cvServerSendEnable.BoolValue || !BotRunning(g_Discord) || !TranslationExistsAndNotEmpty(TRANSLATION_SERVER_DISCORD_MESSAGE))
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

  int  team = GetClientTeamEx(author);
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
  if (TranslationExistsAndNotEmpty(TRANSLATION_SERVER_DISCORD_MESSAGE))
  {
    FormatEx(botContent, sizeof(botContent), "%t", TRANSLATION_SERVER_DISCORD_MESSAGE,
             FormatPlayerMessageBlock(author),
             FormatServerBlock(playerCount));
  }

  if (TranslationExistsAndNotEmpty(TRANSLATION_WEBHOOK_MESSAGE))
  {
    FormatEx(webhookContent, sizeof(webhookContent), "%t", TRANSLATION_WEBHOOK_MESSAGE,
             FormatPlayerMessageBlock(author),
             FormatServerBlock(playerCount));
  }

  if (TranslationExistsAndNotEmpty(TRANSLATION_PLAYER_INFO_EVENT))
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

    if (TranslationExistsAndNotEmpty(TRANSLATION_PLAYER_INFO_EVENT) && !StrEqual(g_ChannelList[i].lastAuthor, authIdEngine))
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

  if (StrContains(channelIdsString, ";") < 0)
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

  char channelEventsString[MAX_BUFFER_LENGTH];
  GetConVarString(g_cvChannelEventEnableBits, channelEventsString, sizeof(channelEventsString));

  if (StrContains(channelEventsString, ";") < 0)
  {
    g_ChannelList[0].enabledEvents = StringToInt(channelEventsString);
  }
  else
  {
    char g_ChannelEventList[sizeof(g_ChannelList)][4];
    ExplodeString(channelEventsString, ";", g_ChannelEventList, sizeof(g_ChannelEventList), sizeof(g_ChannelEventList[]));

    for (int i = 0; i < g_ChannelListCount; i++)
    {
      g_ChannelList[i].enabledEvents = StringToInt(g_ChannelEventList[i]);
    }
  }

  char webhookUrlsString[MAX_BUFFER_LENGTH];
  GetConVarString(g_cvWebhookUrlOverrides, webhookUrlsString, sizeof(webhookUrlsString));

  if (g_cvWebhookModeEnable.BoolValue && !StrEqual(webhookUrlsString, ""))
  {
    if (StrContains(webhookUrlsString, ";") < 0)
    {
      g_ChannelList[0].SetWebhook(new DiscordWebhook(webhookUrlsString));
      g_ChannelList[0].finishedLoading = true;
      CheckForBotFullyReady();
    }
    else
    {
      char g_WebhookUrlsList[sizeof(g_ChannelList)][MAX_AVATAR_URL_LENGTH];
      ExplodeString(webhookUrlsString, ";", g_WebhookUrlsList, sizeof(g_WebhookUrlsList), sizeof(g_WebhookUrlsList[]));

      for (int i = 0; i < g_ChannelListCount; i++)
      {
        if (!g_ChannelList[i].WebhookAvailable() && !StrEqual(g_WebhookUrlsList[i], ""))
        {
          g_ChannelList[i].SetWebhook(new DiscordWebhook(g_WebhookUrlsList[i]));
          g_ChannelList[i].finishedLoading = true;
          CheckForBotFullyReady();
        }
      }
    }
  }

  GetConVarString(g_cvSteamApiKey, g_SteamApiKey, sizeof(g_SteamApiKey));
  GetConVarString(g_cvWebhookName, g_WebhookName, sizeof(g_WebhookName));
  GetConVarString(g_cvServerTags, g_ServerTagsStr, sizeof(g_ServerTagsStr));
}

void SetupDiscordBot()
{
  TeardownDiscordBot();
  logger.Info("Setting up bot...");

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
    logger.Info("Tearing down bot...");
    if (!g_ServerIdle && TranslationExistsAndNotEmpty(TRANSLATION_BOT_STOP_EVENT))
    {
      SendEventToDiscord(TRANSLATION_BOT_STOP_EVENT, FormatServerBlock(GetPlayers(false)));
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

  if (TranslationExistsAndNotEmpty(TRANSLATION_STATUS_COMMAND_LINE) && TranslationExistsAndNotEmpty(TRANSLATION_STATUS_COMMAND_FOOTER))
  {
    g_Discord.RegisterGlobalSlashCommand("status", "Fetch various information about the server.");
  }

  logger.DebugEx("Commands enabled: %i", g_cvCommandEnableBits.IntValue);
  if (IsCommandEnabled(COMMAND_RCON))
  {
    char  option_names[][]        = { "command" };
    char  option_descriptions[][] = { "The command string to send." };
    dType option_types[]          = { Option_String };
    bool  option_required[]       = { true };
    bool  option_autocomplete[]   = { false };
    g_Discord.RegisterGlobalSlashCommandWithOptions("rcon", "Send an arbitrary command to the server as if it was typed in the console or RCON.", "0", option_names, option_descriptions, option_types, option_required, option_autocomplete, sizeof(option_names));
  }

  if (IsCommandEnabled(COMMAND_PSAY))
  {
    char  option_names[][]        = { "player", "message", "ephemeral" };
    char  option_descriptions[][] = { "The player to target.",
                                     "The message to send to the target user.",
                                     "Whether or not to only show this message to you." };
    dType option_types[]          = { Option_String, Option_String, Option_Boolean };
    bool  option_required[]       = { true, true, false };
    bool  option_autocomplete[]   = { true, false, false };
    g_Discord.RegisterGlobalSlashCommandWithOptions("psay", "Private message a player on the server.", "0", option_names, option_descriptions, option_types, option_required, option_autocomplete, sizeof(option_names));
  }

  if (IsCommandEnabled(COMMAND_KICK))
  {
    char  option_names[][]        = { "player", "reason" };
    char  option_descriptions[][] = { "The player to target.",
                                     "The reason to kick the player." };
    dType option_types[]          = { Option_String, Option_String };
    bool  option_required[]       = { true, false };
    bool  option_autocomplete[]   = { true, true };
    g_Discord.RegisterGlobalSlashCommandWithOptions("kick", "Kicks a player from the server.", "0", option_names, option_descriptions, option_types, option_required, option_autocomplete, sizeof(option_names));
  }

  if (IsCommandEnabled(COMMAND_BAN))
  {
    char  option_names[][]        = { "player", "time", "reason" };
    char  option_descriptions[][] = { "The player to target.",
                                     "How long the ban should last in minutes. (0 means permanent)",
                                     "The reason to kick the player." };
    dType option_types[]          = { Option_String, Option_Integer, Option_String };
    bool  option_required[]       = { true, true, false };
    bool  option_autocomplete[]   = { true, false, true };
    g_Discord.RegisterGlobalSlashCommandWithOptions("ban", "Bans a player from the server.", "0", option_names, option_descriptions, option_types, option_required, option_autocomplete, sizeof(option_names));
  }

  if (IsCommandEnabled(COMMAND_CHANGELEVEL))
  {
    char  option_names[][]        = { "map" };
    char  option_descriptions[][] = { "The map to switch to." };
    dType option_types[]          = { Option_String };
    bool  option_required[]       = { true };
    bool  option_autocomplete[]   = { true };
    g_Discord.RegisterGlobalSlashCommandWithOptions("changelevel", "Loads a new map by the specified name instantly.", "0", option_names, option_descriptions, option_types, option_required, option_autocomplete, sizeof(option_names));
  }

  logger.DebugEx("Getting output channel names...");
  for (int i = 0; i < g_ChannelListCount; i++)
  {
    g_Discord.GetChannel(g_ChannelList[i].id, OnGetChannelCallback, i);
    if (g_cvWebhookModeEnable.BoolValue && !g_ChannelList[i].finishedLoading)
    {
      g_Discord.GetChannelWebhooks(g_ChannelList[i].id, OnGetChannelWebhooks, i);
    }
  }

  t_Timer = CreateTimer(g_cvPresenceUpdateInterval.FloatValue, UpdatePresenceTimer, 0, TIMER_REPEAT);
}

public void Discord_OnSlashCommand(Discord discord, DiscordInteraction interaction)
{
  char commandName[MAX_COMMAND_NAME];
  interaction.GetCommandName(commandName, sizeof(commandName));

  DiscordInteractionEx interactionEx = view_as<DiscordInteractionEx>(interaction);
  if (IsCommandEnabled(COMMAND_RCON) && strcmp(commandName, "rcon") == 0)
  {
    char output[MAX_BUFFER_LENGTH], input[MAX_BUFFER_LENGTH];
    interactionEx.GetOptionValue("command", input, sizeof(input));

    DiscordUser user = interactionEx.GetUser();
    char        username[MAX_DISCORD_NAME_LENGTH], userId[SNOWFLAKE_SIZE];
    user.GetUsername(username, sizeof(username));
    user.GetId(userId, sizeof(userId));

    logger.WarnEx("RCON Command from %s (%s): %s", username, userId, input);
    ServerCommandEx(output, sizeof(output), input);

    interactionEx.CreateEphemeralResponseEx("```\n%s```", output);
  }
  if (IsCommandEnabled(COMMAND_PSAY) && strcmp(commandName, "psay") == 0)
  {
    char player[MAX_NAME_LENGTH], content[MAX_MESSAGE_LENGTH];
    interactionEx.GetOptionValue("player", player, sizeof(player));
    interactionEx.GetOptionValue("message", content, sizeof(content));

    int client = FindTarget(0, player, true, false);

    if (client < 0)
    {
      interactionEx.CreateEphemeralResponseEx("%t", TRANSLATION_COMMAND_ERROR, "Target was invalid, couldn't find player.");
      return;
    }

    int  team = GetClientTeamEx(client);
    char teamName[MAX_TEAM_NAME];
    teamName         = GetTeamNameEx(team);

    DiscordUser user = interactionEx.GetUser();
    char        username[MAX_DISCORD_NAME_LENGTH], displayName[MAX_DISCORD_NAME_LENGTH];
    char        nickname[MAX_DISCORD_NAME_LENGTH], authorId[SNOWFLAKE_SIZE], channelId[SNOWFLAKE_SIZE];
    int         authorDescriminator = user.GetDiscriminator();
    user.GetUsername(username, sizeof(username));
    user.GetGlobalName(displayName, sizeof(displayName));
    interactionEx.GetUserNickname(nickname, sizeof(nickname));
    interactionEx.GetChannelId(channelId, sizeof(channelId));
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

    // TODO This iteration is silly the macro should just let you pass a channel name, and will not work if command is used outside of usual channels
    int channelIndex;
    for (int i = 0; i < g_ChannelListCount; i++)
    {
      if (StrEqual(g_ChannelList[i].id, channelId))
      {
        channelIndex = i;
      }
    }

    CPrintToChat(client, "%t", TRANSLATION_PSAY_COMMAND_CONTENT,
                 FormatPlayerBlock(client),
                 FormatDiscordMessageBlock(channelIndex)
                 // ,FormatServerBlock(GetPlayers(false))
    );

    if (interactionEx.GetOptionValueBool("ephemeral"))
    {
      interactionEx.CreateEphemeralResponseEx("%t", TRANSLATION_COMMAND_MESSAGE_SENT);
    }
    else
    {
      interactionEx.CreateResponseEx("%t", TRANSLATION_COMMAND_MESSAGE_SENT);
    }
  }
  if (IsCommandEnabled(COMMAND_KICK) && strcmp(commandName, "kick") == 0)
  {
    char player[MAX_NAME_LENGTH], reason[MAX_MESSAGE_LENGTH];
    interaction.GetOptionValue("player", player, sizeof(player));
    interaction.GetOptionValue("reason", reason, sizeof(reason));

    int client = FindTarget(0, player, true, false);

    if (client < 0)
    {
      interactionEx.CreateEphemeralResponseEx("%t", TRANSLATION_COMMAND_ERROR, "Target was invalid, couldn't find player.");
      return;
    }

    KickClient(client, reason);

    interactionEx.CreateEphemeralResponseEx("%t", TRANSLATION_COMMAND_PLAYER_KICKED);
  }
  if (IsCommandEnabled(COMMAND_BAN) && strcmp(commandName, "ban") == 0)
  {
    char player[MAX_NAME_LENGTH], reason[MAX_MESSAGE_LENGTH];
    interaction.GetOptionValue("player", player, sizeof(player));
    int time = interaction.GetOptionValueInt("time");
    interaction.GetOptionValue("reason", reason, sizeof(reason));

    int client = FindTarget(0, player, true, false);

    if (client < 0)
    {
      logger.WarnEx("Couldn't find client %d: %s", client, player);
      interactionEx.CreateEphemeralResponseEx("%t", TRANSLATION_COMMAND_ERROR, "Target was invalid, couldn't find player.");
      return;
    }

    bool success;
    if (LibraryExists("sourcebans++"))
    {
      SBPP_BanPlayer(0, client, time, reason);
      success = true;
    }
    else
    {
      success = BanClient(client, time, BANFLAG_AUTO, reason, reason, "sm_ban", client);
    }

    interactionEx.CreateEphemeralResponseEx("%t", success ? TRANSLATION_COMMAND_PLAYER_BANNED : TRANSLATION_COMMAND_ERROR);
  }
  if (IsCommandEnabled(COMMAND_CHANGELEVEL) && strcmp(commandName, "changelevel") == 0)
  {
    char map[MAX_MAP_NAME];
    interactionEx.GetOptionValue("map", map, sizeof(map));

    if (!StrEqual(map, ""))
    {
      char foundMap[PLATFORM_MAX_PATH];
      if (FindMap(map, foundMap, sizeof(foundMap)) != FindMap_NotFound)
      {
        interactionEx.CreateEphemeralResponseEx("%t", TRANSLATION_COMMAND_SUCCESS);
        ForceChangeLevel(foundMap, "Forced changelevel by discord command");
        return;
      }
    }

    interactionEx.CreateEphemeralResponseEx("%t", TRANSLATION_COMMAND_ERROR, "Map name is invalid!");
  }
  if (strcmp(commandName, "status") == 0)
  {
    if (!TranslationExistsAndNotEmpty(TRANSLATION_STATUS_COMMAND_TITLE) || !TranslationExistsAndNotEmpty(TRANSLATION_STATUS_COMMAND_LINE))
    {
      return;
    }

    int  playerCount = GetPlayers(false);

    char playersString[DISCORD_TITLE_LENGTH];
    FormatEx(playersString, sizeof(playersString), "%t", TRANSLATION_COMMAND_STATUS_PLAYERS, playerCount, MaxClients);

    DiscordEmbed embed = new DiscordEmbed();
    if (TranslationExistsAndNotEmpty(TRANSLATION_STATUS_COMMAND_TITLE))
    {
      char title[DISCORD_FIELD_LENGTH];
      FormatEx(title, sizeof(title), "%t", TRANSLATION_STATUS_COMMAND_TITLE, FormatServerBlock(GetPlayers(false)));

      embed.SetTitle(title);
    }

    if (TranslationExistsAndNotEmpty(TRANSLATION_STATUS_COMMAND_DESC))
    {
      char description[DISCORD_FIELD_LENGTH];
      FormatEx(description, sizeof(description), "%t", TRANSLATION_STATUS_COMMAND_DESC, FormatServerBlock(GetPlayers(false)));

      embed.SetDescription(description);
    }

    if (TranslationExistsAndNotEmpty(TRANSLATION_STATUS_COMMAND_LINE))
    {
      char playerLines[DISCORD_FIELD_LENGTH];
      int  total;
      bool addedField;
      for (int i = 1; i <= MaxClients; i++)
      {
#if defined DEBUG
        if (IsClientInGame(i))
#else
        if (IsValidClient(i))
#endif
        {
          int  team = GetClientTeamEx(i);
          char teamName[MAX_TEAM_NAME];
          teamName = GetTeamNameEx(team);
          total    = FormatEx(playerLines, sizeof(playerLines), i == 0 ? "%s%t" : "%s\n%t", i == 0 ? "" : playerLines, TRANSLATION_STATUS_COMMAND_LINE,
                              FormatPlayerBlock(i),
                              FormatServerBlock(playerCount));

          // Get the average of the past player lines and if the next one will put us over the limit, end here
          // This uses vague heuristics and will have errors sometimes! Sorry!
          if (total + (total / i) > DISCORD_FIELD_LENGTH)
          {
            embed.AddField(playersString, playerLines, false);
            addedField  = true;
            total       = 0;
            playerLines = "";
          }
        }
      }

      if (!addedField && total < DISCORD_FIELD_LENGTH)
      {
        embed.AddField(playersString, playerLines, false);
      }
    }

    if (TranslationExistsAndNotEmpty(TRANSLATION_STATUS_COMMAND_FOOTER))
    {
      char footerStr[DISCORD_FOOTER_LENGTH];
      FormatEx(footerStr, sizeof(footerStr), "%t", TRANSLATION_STATUS_COMMAND_FOOTER, FormatServerBlock(playerCount));

      embed.SetFooter(footerStr);
    }

    interactionEx.CreateEphemeralResponseEmbed("", embed);
    delete embed;
  }
}

public void Discord_OnAutocomplete(Discord discord, DiscordAutocompleteInteraction interaction, bool focused, DiscordCommandOptionType type, char[] optionName)
{
  DiscordAutocompleteInteractionEx interactionEx = view_as<DiscordAutocompleteInteractionEx>(interaction);

  if (focused && g_cvCommandEnableBits.IntValue > 0)
  {
    if (StrEqual(optionName, "player"))
    {
      char value[MAX_NAME_LENGTH];
      interaction.GetOptionValue("player", value, sizeof(value));
      logger.DebugEx("%s (%i): %s", optionName, type, value);
      for (int i = 1; i <= MaxClients; i++)
      {
        if (IsValidClient(i))
        {
          char playerEntry[MAX_DISCORD_NITRO_MESSAGE_LENGTH];
          int  userId = GetClientUserId(i);
          int  team   = GetClientTeamEx(i);
          char teamName[MAX_TEAM_NAME];
          teamName = GetTeamNameEx(team);
          FormatEx(playerEntry, sizeof(playerEntry), "%t", TRANSLATION_PLAYER_AUTOCOMPLETE,
                   FormatPlayerBlock(i),
                   FormatServerBlock(GetPlayers(false)));

          interactionEx.AddAutocompleteChoiceEx(playerEntry, "#%i", userId);
        }
      }

      interaction.CreateAutocompleteResponse(discord);
    }
    if (StrEqual(optionName, "map"))
    {
      char value[PLATFORM_MAX_PATH];
      interaction.GetOptionValue("map", value, sizeof(value));
      bool empty = StrEqual(value, "");
      for (int i = 0; i < g_CachedMapList.Length; i++)
      {
        char map[MAX_MAP_NAME];
        g_CachedMapList.GetString(i, map, sizeof(map));

        if (empty || StrContains(map, value, false) >= 0)
        {
          interaction.AddAutocompleteChoiceString(map, map);
        }
      }

      interaction.CreateAutocompleteResponse(discord);
    }
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

  if (!inListedChannel || messageFromSelf || message.IsBot() || !g_cvDiscordSendEnable.BoolValue || !TranslationExistsAndNotEmpty(TRANSLATION_DISCORD_SERVER_MESSAGE))
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

  if (IsEventEnabled(originalChannel, EVENT_BRIDGE))
  {
    for (int i = 0; i < g_ChannelListCount; i++)
    {
      if (i != originalChannel)
      {
        if (TranslationExistsAndNotEmpty(TRANSLATION_DISCORD_DISCORD_MESSAGE))
        {
          char webhookName[MAX_DISCORD_NAME_LENGTH];
          webhookName = nickname;
          if (TranslationExistsAndNotEmpty(TRANSLATION_DISCORD_DISCORD_NAME))
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
  }

  delete author;
}

public void Discord_OnError(Discord discord, const char[] error)
{
  logger.DebugEx("[discord] %s", error);
}

void OnGetChannelCallback(Discord discord, DiscordChannel channel, int index)
{
  channel.GetName(g_ChannelList[index].name, sizeof(g_ChannelList[].name));
  CRemoveTags(g_ChannelList[index].name, sizeof(g_ChannelList[].name));

  logger.DebugEx("Outputting to: #%s", g_ChannelList[index].name);
}

public void OnGetChannelWebhooks(Discord discord, DiscordWebhook[] webhookMap, int count, any data)
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
      g_ChannelList[data].SetWebhook(view_as<DiscordWebhook>(CloneHandle(webhookMap[i])));
      g_ChannelList[data].finishedLoading = true;
      CheckForBotFullyReady();
    }
  }

  if (!g_ChannelList[data].WebhookAvailable())
  {
    logger.DebugEx("Creating webhook for channel %s", g_ChannelList[data].id);
    if (!g_Discord.CreateWebhook(g_ChannelList[data].id, g_WebhookName, OnCreateWebhook, data))
    {
      g_ChannelList[data].finishedLoading = true;
      CheckForBotFullyReady();
    }
  }
}

void OnCreateWebhook(Discord discord, DiscordWebhook wh, any data)
{
  g_ChannelList[data].SetWebhook(view_as<DiscordWebhook>(CloneHandle(wh)));
  g_ChannelList[data].finishedLoading = true;
  CheckForBotFullyReady();
}

void CheckForBotFullyReady()
{
  for (int i = 0; i < g_ChannelListCount; i++)
  {
    if (!g_ChannelList[i].finishedLoading)
    {
      return;
    }
  }

  // Bot Start Event
  if (TranslationExistsAndNotEmpty(TRANSLATION_BOT_START_EVENT))
  {
    SendEventToDiscord(TRANSLATION_BOT_START_EVENT, FormatServerBlock(GetPlayers(false)));
  }

  Call_StartForward(g_BotReadyForward);
  Call_PushCell(g_Discord);
  Call_Finish();
}

bool WebhookIsMine(DiscordWebhook wh)
{
  if (wh == INVALID_HANDLE)
  {
    return false;
  }

  DiscordUser user = wh.GetUser();

  char        webhookName[MAX_DISCORD_NAME_LENGTH];
  char        userId[MAX_DISCORD_NAME_LENGTH];

  wh.GetName(webhookName, sizeof(webhookName));
  user.GetId(userId, sizeof(userId));

  delete user;
  return StrEqual(g_WebhookName, webhookName) && StrEqual(userId, g_BotId);
}

void SendToDiscordChannel(ChannelInfo channel, char[] content, char[] username, int client, char avatarUrlOverride[MAX_AVATAR_URL_LENGTH] = "")
{
  if (StrEqual(content, ""))
  {
    logger.Error("Can't send empty string!");
    return;
  }

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
    g_Discord.ExecuteWebhook(webhook, content, 255);
  }
  else
  {
    // TODO Allowed mentions should probably be configurable for security
    g_Discord.SendMessage(channel.id, content, 255);
  }
}

void SendToDiscord(char[] content, char[] username, int client, int enabledMask = 0, char avatarUrlOverride[MAX_AVATAR_URL_LENGTH] = "")
{
  if (StrEqual(content, ""))
  {
    logger.Error("Can't send empty string!");
    return;
  }

  if (!BotRunning(g_Discord))
  {
    logger.ErrorEx("Bot not running! Can't send message: %s", content);
    return;
  }

  for (int i = 0; i < g_ChannelListCount; i++)
  {
    if (IsEventEnabled(i, enabledMask))
    {
      SendToDiscordChannel(g_ChannelList[i], content, username, client, avatarUrlOverride);
    }
  }
}

void SendEventToDiscordImpl(char[] content, int enabledMask = 0)
{
  if (StrEqual(content, ""))
  {
    logger.Error("Can't send empty string!");
    return;
  }

  char name[MAX_DISCORD_NAME_LENGTH];
  FormatEx(name, sizeof(name), "%t", TRANSLATION_WEBHOOK_EVENTS, FormatServerBlock(GetPlayers(false)));

  SendToDiscord(content, name, -1, enabledMask);

  // Clear LastAuthorList because we are sending an event
  for (int i = 0; i < g_ChannelListCount; i++)
  {
    if (IsEventEnabled(i, enabledMask))
    {
      g_ChannelList[i].lastAuthor = "";
    }
  }
}

/**
 * Second parameter must be a translation phrase.
 */
void SendEventToDiscordEx(int enabledMask, any...)
{
  if (!BotRunning(g_Discord))
  {
    logger.Error("Bot not running! Can't send event.");
    return;
  }

  char content[MAX_DISCORD_MESSAGE_LENGTH];
  VFormat(content, sizeof(content), "%t", 2);

  SendEventToDiscordImpl(content, enabledMask);
}

/**
 * First parameter must be a translation phrase.
 */
void SendEventToDiscord(any...)
{
  if (!BotRunning(g_Discord))
  {
    logger.Error("Bot not running! Can't send event.");
    return;
  }

  char content[MAX_DISCORD_MESSAGE_LENGTH];
  VFormat(content, sizeof(content), "%t", 1);

  SendEventToDiscordImpl(content);
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
  if (!TranslationExistsAndNotEmpty(TRANSLATION_STATUS) || !TranslationExistsAndNotEmpty(TRANSLATION_STATUS_PLURAL))
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

Action DeleteCommandsCmd(int args)
{
  if (BotRunning(g_Discord))
  {
    if (g_Discord.BulkDeleteGlobalCommands())
    {
      ReplyToCommand(0, "%t", TRANSLATION_COMMAND_CMD_DELETE);
      return Plugin_Continue;
    }
    ReplyToCommand(0, "%t", TRANSLATION_COMMAND_CMD_DELETE_FAIL, "Unknown error.");
    return Plugin_Continue;
  }

  ReplyToCommand(0, "%t", TRANSLATION_COMMAND_CMD_DELETE_FAIL, "Bot is not running");
  return Plugin_Continue;
}

int GetChannelListCount()
{
  return g_ChannelListCount;
}

ChannelInfo GetChannel(int index)
{
  return g_ChannelList[index];
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
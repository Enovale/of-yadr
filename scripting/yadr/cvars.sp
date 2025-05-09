#pragma newdecls required
#pragma semicolon 1
#pragma tabsize 2

#define PLUGIN_SHORTNAME          "yadr"
#define PLUGIN_TRANS_PHRASES_FILE PLUGIN_SHORTNAME... ".phrases"
#define PLUGIN_TRANS_INFO_FILE    PLUGIN_SHORTNAME... ".info.phrases"
#define PLUGIN_CONVAR_PREFIX      "sm_" ... PLUGIN_SHORTNAME... "_"

ConVar g_cvBotToken;
ConVar g_cvSteamApiKey;
ConVar g_cvChannelIds;
ConVar g_cvWebhookModeEnable;
ConVar g_cvWebhookName;
ConVar g_cvWebhookUrlOverrides;
ConVar g_cvDiscordSendEnable;
ConVar g_cvServerSendEnable;
ConVar g_cvDiscordColorCodesEnable;
ConVar g_cvPresenceUpdateInterval;
ConVar g_cvMapChangeGracePeriod;
ConVar g_cvChannelEventEnableBits;
ConVar g_cvCommandEnableBits;

ConVar g_cvUpdateUrl;
ConVar g_cvVerboseEnable;

// Cached internal convars
ConVar g_cvFragLimit;
ConVar g_cvServerTags;

void   CreateCvars()
{
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
  g_cvChannelEventEnableBits  = CreateConVar(PLUGIN_CONVAR_PREFIX... "channel_event_bits", "255", "Semicolon separated list of bitmasks to enable events in individual channels. 1: Bridge this channel to other channels linked by the bot\n2: BAN\n4: REPORT");
  g_cvCommandEnableBits       = CreateConVar(PLUGIN_CONVAR_PREFIX... "command_enable_bits", "0", "Bitmask that enable various admin-only commands. 1: RCON\n2: PSAY\n4: KICK\n8: BAN\n16: REPORT\n32: CHANGELEVEL");

  g_cvUpdateUrl               = CreateConVar(PLUGIN_CONVAR_PREFIX... "update_url", "https://enovale.github.io/of-yadr/updatefile.txt", "URL to use for Updater integration.");
  g_cvVerboseEnable           = CreateConVar(PLUGIN_CONVAR_PREFIX... "verbose", "0", "Enable verbose logging for the discord backend.");

  g_cvFragLimit               = FindConVar("mp_fraglimit");
  g_cvServerTags              = FindConVar("sv_tags");
}

void AddCvarHooks()
{
  g_cvChannelIds.AddChangeHook(OnCvarChange);
  g_cvSteamApiKey.AddChangeHook(OnCvarChange);
  g_cvServerTags.AddChangeHook(OnCvarChange);
}
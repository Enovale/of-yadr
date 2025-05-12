#pragma newdecls required
#pragma semicolon 1
#pragma tabsize 2

#define NATIVE_PREFIX "YADR_"

#define CMD_SEND_CHANNEL PLUGIN_CONVAR_PREFIX... "send_channel"
#define CMD_SEND PLUGIN_CONVAR_PREFIX... "send"
#define CMD_SEND_EVENT PLUGIN_CONVAR_PREFIX... "send_event"

GlobalForward g_BotReadyForward;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
  RegPluginLibrary(PLUGIN_SHORTNAME);

  CreateNative(NATIVE_PREFIX..."SendToChannel", Native_SendToChannel);
  CreateNative(NATIVE_PREFIX..."Send", Native_Send);
  CreateNative(NATIVE_PREFIX..."SendEvent", Native_SendEvent);
  CreateNative(NATIVE_PREFIX..."GetRegisteredChannelCount", Native_GetRegisteredChannelCount);
  CreateNative(NATIVE_PREFIX..."GetRegisteredChannel", Native_GetRegisteredChannel);
  return APLRes_Success;
}

void RegisterCmds()
{
  g_BotReadyForward = new GlobalForward(NATIVE_PREFIX..."BotReady", ET_Ignore, Param_Cell);

  RegAdminCmd(CMD_SEND_CHANNEL, SendToChannelCmd, Admin_RCON, "Sends a message to a discord channel using the internal channel and webhook list.");
  RegAdminCmd(CMD_SEND, SendCmd, Admin_RCON, "Sends a message to all the registered discord channels.");
  RegAdminCmd(CMD_SEND_EVENT, SendEventCmd, Admin_RCON, "Sends an event message to all the registered discord channels.");
}

// TODO Complete cmds
Action SendToChannelCmd(int client, int args)
{
  if (args < 4)
  {
    PrintToConsole(client, "Usage: "...CMD_SEND_CHANNEL..." <channel_id> <message> <username> <client> [avatar_url]");
    return Plugin_Handled;
  }

  return Plugin_Continue;
}

Action SendCmd(int client, int args)
{
  if (args < 3)
  {
    PrintToConsole(client, "Usage: "...CMD_SEND..." <message> <username> <client> [enabled_mask] [avatar_url]");
    return Plugin_Handled;
  }

  char content[MAX_DISCORD_MESSAGE_LENGTH];
  GetCmdArg(1, content, sizeof(content));
  char username[MAX_DISCORD_NAME_LENGTH];
  GetCmdArg(2, username, sizeof(username));
  int target = GetCmdArgInt(3);
  int enabledMask = GetCmdArgInt(4);
  char avatarUrl[MAX_AVATAR_URL_LENGTH];
  if (args >= 5)
  {
    GetCmdArg(5, avatarUrl, sizeof(avatarUrl));
  }

  SendToDiscord(content, username, target, enabledMask, avatarUrl);
  PrintToConsole(client, "Message sent!");
  return Plugin_Continue;
}

Action SendEventCmd(int client, int args)
{
  if (args < 1)
  {
    PrintToConsole(client, "Usage: "...CMD_SEND_EVENT..." <message> [enabled_mask]");
    return Plugin_Handled;
  }

  char content[MAX_DISCORD_MESSAGE_LENGTH];
  GetCmdArg(1, content, sizeof(content));
  int enabledMask = GetCmdArgInt(2);

  SendEventToDiscordImpl(content, enabledMask);
  PrintToConsole(client, "Event sent!");
  return Plugin_Continue;
}

int Native_SendToChannel(Handle plugin, int numParams)
{
  ChannelInfo channel;
  GetNativeArray(1, channel, sizeof(channel));
  char content[MAX_MESSAGE_LENGTH];
  GetNativeString(2, content, sizeof(content));
  char username[MAX_DISCORD_NAME_LENGTH];
  GetNativeString(3, username, sizeof(username));
  int  client = GetNativeCell(4);
  char avatarUrlOverride[MAX_AVATAR_URL_LENGTH];
  GetNativeString(5, avatarUrlOverride, sizeof(avatarUrlOverride));
  SendToDiscordChannel(channel, content, username, client, avatarUrlOverride);

  return Plugin_Continue;
}

int Native_Send(Handle plugin, int numParams)
{
  char content[MAX_MESSAGE_LENGTH];
  GetNativeString(1, content, sizeof(content));
  char username[MAX_DISCORD_NAME_LENGTH];
  GetNativeString(2, username, sizeof(username));
  int  client      = GetNativeCell(3);
  int  enabledMask = GetNativeCell(4);
  char avatarUrlOverride[MAX_AVATAR_URL_LENGTH];
  GetNativeString(5, avatarUrlOverride, sizeof(avatarUrlOverride));
  SendToDiscord(content, username, client, enabledMask, avatarUrlOverride);

  return Plugin_Continue;
}

int Native_SendEvent(Handle plugin, int numParams)
{
  char content[MAX_MESSAGE_LENGTH];
  GetNativeString(1, content, sizeof(content));
  int enabledMask = GetNativeCell(2);
  SendEventToDiscordImpl(content, enabledMask);

  return Plugin_Continue;
}

int Native_GetRegisteredChannelCount(Handle plugin, int numParams)
{
  return GetChannelListCount();
}

any Native_GetRegisteredChannel(Handle plugin, int numParams)
{
  return GetChannel(GetNativeCell(1));
}
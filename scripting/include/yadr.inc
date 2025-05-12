#if defined _yadr_included_
  #endinput
#endif
#define _yadr_included_

#include <discord>

#pragma newdecls required
#pragma semicolon 1
#pragma tabsize 2

// clang-format off
enum struct ChannelInfo
{
  char           id[SNOWFLAKE_SIZE];
  char           name[MAX_DISCORD_CHANNEL_NAME_LENGTH];
  char           lastAuthor[MAX_AUTHID_LENGTH];
  int            enabledEvents;
  DiscordWebhook webhook;
  bool           finishedLoading;

  void SetWebhook(DiscordWebhook webhook)
  {
    if (webhook != INVALID_HANDLE)
    {
      this.webhook = webhook;
      this.webhook.SetAvatarData("");
    }
  }

  bool WebhookAvailable()
  {
    return this.finishedLoading && this.webhook != INVALID_HANDLE;
  }

  bool IsEqual(const char[] channelId)
  {
    return StrEqual(this.id, channelId);
  }
}
// clang-format on

forward void YADR_BotReady(Discord discord);

native void YADR_SendToChannel(ChannelInfo channel, char[] content, char[] username, int client, char avatarUrlOverride[MAX_AVATAR_URL_LENGTH] = "");

native void YADR_Send(char[] content, char[] username, int client, int enabledMask = 0, char avatarUrlOverride[MAX_AVATAR_URL_LENGTH] = "");

native void YADR_SendEvent(char[] content, int enabledMask = 0);

native int YADR_GetRegisteredChannelCount();

#if SOURCEMOD_V_MINOR > 11
native ChannelInfo YADR_GetRegisteredChannel(int index);
#endif

public SharedPlugin __pl_yadr = {
  name = "yadr",
  file = "yadr.smx",
#if defined REQUIRE_PLUGIN
  required = 1,
#else
  required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_yadr_SetNTVOptional()
{
  MarkNativeAsOptional("YADR_SendToChannel");
  MarkNativeAsOptional("YADR_Send");
  MarkNativeAsOptional("YADR_SendEvent");
  MarkNativeAsOptional("YADR_GetRegisteredChannelCount");
#if SOURCEMOD_V_MINOR > 11
  MarkNativeAsOptional("YADR_GetRegisteredChannel");
#endif
}
#endif
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

  bool WebhookAvailable()
  {
    return this.webhook != INVALID_HANDLE;
  }

  bool IsEqual(const char[] channelId)
  {
    return StrEqual(this.id, channelId);
  }
}
// clang-format on

public SharedPlugin __pl_yadr = 
{
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
}
#endif
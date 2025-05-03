#if defined _yadr_included_
  #endinput
#endif
#define _yadr_included_

#include <discord>

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
#include "utils.sp"
#include <discord>

#define COMMAND_CONSOLECOMMAND (1<<0)
#define COMMAND_PSAY           (1<<1)
#define COMMAND_BAN            (1<<2)
#define COMMAND_KICK           (1<<3)

enum struct ChannelInfo
{
  char id[SNOWFLAKE_SIZE];
  char name[MAX_DISCORD_CHANNEL_NAME_LENGTH];
  char lastAuthor[MAX_AUTHID_LENGTH];
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
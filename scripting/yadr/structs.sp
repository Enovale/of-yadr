#include "utils.sp"
#include <discord>

#pragma newdecls required
#pragma semicolon 1

#define COMMAND_RCON        (1 << 0)
#define COMMAND_PSAY        (1 << 1)
#define COMMAND_KICK        (1 << 2)
#define COMMAND_BAN         (1 << 3)
#define COMMAND_CHANGELEVEL (1 << 4)

/**
 * Helper methods for various methodmaps in sm-ext-discord because they do not allow inline formatting.
 */
// clang-format off
methodmap DiscordInteractionEx < DiscordInteraction
{
  public void CreateResponseEx(const char[] format, any ...)
  {
    char buffer[MAX_BUFFER_LENGTH];
    VFormat(buffer, sizeof(buffer), format, 3);
    this.CreateResponse(buffer);
  }

  public void CreateEphemeralResponseEx(const char[] format, any ...)
  {
    char buffer[MAX_BUFFER_LENGTH];
    VFormat(buffer, sizeof(buffer), format, 3);
    this.CreateEphemeralResponse(buffer);
  }
}

methodmap DiscordAutocompleteInteractionEx < DiscordAutocompleteInteraction
{
  public void AddAutocompleteChoiceEx(const char[] name, char[] format, any ...)
  {
    char buffer[MAX_BUFFER_LENGTH];
    VFormat(buffer, sizeof(buffer), format, 3);
    this.AddAutocompleteChoiceString(name, buffer);
  }
}
// clang-format on

#define DEBUG

#define PLUGIN_NAME           "Yet Another Discord Relay"
#define PLUGIN_AUTHOR         "Enova"
#define PLUGIN_DESCRIPTION    ""
#define PLUGIN_VERSION        "1.0"
#define PLUGIN_URL            "https://github.com/Enovale/of-yodr"

#include <sourcemod>
#include <sdktools>
#include <chat-processor>

#pragma semicolon 1


public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	
}

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
	Format(name, MAXLENGTH_NAME, "{red}%s", name);
	Format(message, MAXLENGTH_MESSAGE, "{blue}%s", message);
	return Plugin_Changed;
}
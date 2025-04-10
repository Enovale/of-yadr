#include "utils.sp"

char g_ServerIpStr[16];
char g_ServerHostname[64];
char g_CachedMapName[MAX_MAP_NAME_WITH_TERMINATOR];
int g_MaxPlayers;

void CacheFormatVars()
{
    g_ServerIpStr = GetServerIP();
	GetConVarString(FindConVar("hostname"), g_ServerHostname, sizeof(g_ServerHostname));
    CacheMapName();

    g_MaxPlayers = GetConVarInt(FindConVar("sv_visiblemaxplayers"));
	if(g_MaxPlayers < 1)
		g_MaxPlayers = GetMaxHumanPlayers();
}

void CacheMapName()
{
    GetCurrentMap(g_CachedMapName, sizeof(g_CachedMapName));
}

void CacheExplicitMapName(const char[] mapName)
{
    FormatEx(g_CachedMapName, sizeof(g_CachedMapName), "%s", mapName);
}
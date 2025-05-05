#include "utils.sp"

#pragma newdecls required
#pragma semicolon 1

char      g_ServerIpStr[MAX_IP_LENGTH];
char      g_ServerTagsStr[128];
int       g_ServerPort;
char      g_ServerHostname[64];
char      g_CachedMapName[MAX_MAP_NAME];
char      g_CachedNextMapName[MAX_MAP_NAME];
ArrayList g_CachedMapList;
int       g_MaxPlayers;

public void CacheFormatVars()
{
    g_ServerIpStr = GetServerIP();
    g_ServerPort  = GetConVarInt(FindConVar("hostport"));
    GetConVarString(FindConVar("hostname"), g_ServerHostname, sizeof(g_ServerHostname));
    SanitiseText(g_ServerHostname, sizeof(g_ServerHostname));
    CacheMapName();

    g_MaxPlayers = GetConVarInt(FindConVar("sv_visiblemaxplayers"));
    if (g_MaxPlayers < 1)
        g_MaxPlayers = GetMaxHumanPlayers();
}

void CacheMapList()
{
    g_CachedMapList = view_as<ArrayList>(ReadMapList(_, _, _, MAPLIST_FLAG_MAPSFOLDER));
}

void CacheMapName()
{
    GetCurrentMap(g_CachedMapName, sizeof(g_CachedMapName));
    SanitiseText(g_CachedMapName, sizeof(g_CachedMapName));
}

void CacheNextMapName()
{
    if (GetNextMap(g_CachedNextMapName, sizeof(g_CachedNextMapName)))
    {
        SanitiseText(g_CachedNextMapName, sizeof(g_CachedNextMapName));
    }
}

void CacheExplicitMapName(const char[] mapName)
{
    FormatEx(g_CachedMapName, sizeof(g_CachedMapName), "%s", mapName);
    SanitiseText(g_CachedMapName, sizeof(g_CachedMapName));
}
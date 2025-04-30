#if defined _utils_included_
  #endinput
#endif
#define _utils_included_

#include <SteamWorks>
#include <ripext>
#include <morecolors>
#include <log4sp>

#pragma newdecls required
#pragma semicolon 1

#define MAX_MAP_NAME          64
#define MAX_TEAM_NAME         32
#define MAX_IP_LENGTH         16
#define MAX_PORT_LENGTH       6
#define SHORT_TIME_LENGTH     12

// Limits found here: https://discordjs.guide/popular-topics/embeds.html#notes
#define DISCORD_TITLE_LENGTH  257
#define DISCORD_DESC_LENGTH   4097
#define DISCORD_FIELD_LENGTH  1025
#define DISCORD_FOOTER_LENGTH 2049

// 256 Is arbitrary, but webhook URLs should definitely never be bigger than that
#define MAX_AVATAR_URL_LENGTH 256

Logger     logger;

char       g_SteamApiKey[33];
HTTPClient g_HttpClient;
char       g_SteamAvatars[MAXPLAYERS][100];

stock void InitializeLogging(char[] name, LogLevel logLevel)
{
    if (logger)
    {
        return;
    }

    char dailyFileFormat[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, dailyFileFormat, sizeof(dailyFileFormat), "logs/%s.log", name);

    logger = ServerConsoleSink.CreateLogger(name);
    logger.AddSinkEx(new DailyFileSink(dailyFileFormat));
    logger.SetLevel(logLevel);
}

void DestroyLogging()
{
    delete logger;
}

char[] GetServerIP()
{
    char ipStr[MAX_IP_LENGTH];
    int  pieces[4];

    if (SteamWorks_GetPublicIP(pieces))
    {
        FormatEx(ipStr, sizeof(ipStr), "%d.%d.%d.%d", pieces[0], pieces[1], pieces[2], pieces[3]);
    }
    else {
        logger.ErrorEx("Appears like we had an error on getting the Public IP address.");
    }

    return ipStr;
}

bool IsValidClient(int client)
{
    if (!(1 <= client <= MaxClients) || !IsClientInGame(client) || !IsClientConnected(client) || IsFakeClient(client) || IsClientSourceTV(client))
        return false;

    return true;
}

int GetPlayers(bool connecting)
{
    int players;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (connecting && IsClientConnected(i) && !IsClientInGame(i)) players++;
        else if (!connecting && IsValidClient(i)) players++;
    }
    return players;
}

char[] FormatShortTime(int time)
{
    char Time[SHORT_TIME_LENGTH];
    int  g_iHours   = 0;
    int  g_iMinutes = 0;
    int  g_iSeconds = time;

    while (g_iSeconds > 3600)
    {
        g_iHours++;
        g_iSeconds -= 3600;
    }
    while (g_iSeconds > 60)
    {
        g_iMinutes++;
        g_iSeconds -= 60;
    }
    if (g_iHours >= 1) FormatEx(Time, sizeof(Time), "%d:%d:%d", g_iHours, g_iMinutes, g_iSeconds);
    else if (g_iMinutes >= 1) FormatEx(Time, sizeof(Time), "%d:%d", g_iMinutes, g_iSeconds);
    else FormatEx(Time, sizeof(Time), "%d", g_iSeconds);
    return Time;
}

int GetClientTeamEx(int client)
{
    if (!IsClientInGame(client))
    {
        return 0;
    }
    return GetClientTeam(client);
}

// TODO This seems not adaptable to other games
char[] GetClientTeamNameIfSpectator(char[] teamName)
{
    return StrContains(teamName, "Spec", false) == -1 ? "" : teamName;
}

char[] GetClientConnectionTime(int client)
{
    if (IsFakeClient(client))
    {
        return FormatShortTime(0);
    }
    return FormatShortTime(RoundToFloor(GetClientTime(client)));
}

int GetClientPing(int client)
{
    return GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iPing", _, client);
}

char[] GetClientNameEx(int client, bool sanitise = false)
{
    char nameBuffer[MAX_NAME_LENGTH];
    GetClientName(client, nameBuffer, sizeof(nameBuffer));
    if (sanitise)
    {
        SanitiseText(nameBuffer, sizeof(nameBuffer));
    }
    return nameBuffer;
}

char[] GetClientAuthId64(int client)
{
    return GetClientAuthIdEx(client, AuthId_SteamID64);
}

char[] GetClientAuthId2(int client)
{
    return GetClientAuthIdEx(client, AuthId_Steam2);
}

char[] GetClientAuthId3(int client)
{
    return GetClientAuthIdEx(client, AuthId_Steam3);
}

char[] GetClientAuthIdEngine(int client)
{
    return GetClientAuthIdEx(client, AuthId_Engine);
}

char[] GetClientIpEx(int client)
{
    char ipStr[16];
    bool success = GetClientIP(client, ipStr, sizeof(ipStr), true);
    return success ? ipStr : "N/A";
}

char[] GetClientAuthIdEx(int client, AuthIdType type)
{
    char steamId[MAX_AUTHID_LENGTH];

    bool success = GetClientAuthId(client, type, steamId, sizeof(steamId), true);
    return success ? steamId : "N/A";
}

char[] GetTeamNameEx(int team)
{
    char buffer[MAX_TEAM_NAME];

    GetTeamName(team, buffer, sizeof(buffer));
    return buffer;
}

bool SteamApiAvailable()
{
    return !StrEqual(g_SteamApiKey, "", false);
}

void GetProfilePic(int client)
{
    if (!SteamApiAvailable())
    {
        logger.ErrorEx("Steam API Key not configured.");
        return;
    }

    // TODO 1024 is arbitrary
    char requestBuffer[1024], steamId[MAX_AUTHID_LENGTH];

    if (!GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId), true))
    {
        logger.ErrorEx("Could not get users steam ID. Are they not authenticated yet?");
        return;
    }

    FormatEx(requestBuffer, sizeof requestBuffer, "ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamids=%s&format=json", g_SteamApiKey, steamId);
    g_HttpClient.Get(requestBuffer, GetProfilePicCallback, client);
}

public void GetProfilePicCallback(HTTPResponse response, any client)
{
    if (response.Status != HTTPStatus_OK)
    {
        FormatEx(g_SteamAvatars[client], sizeof(g_SteamAvatars[]), "NULL");
        logger.ErrorEx("Failed to reach SteamAPI. Status: %i", response.Status);
        return;
    }

    JSONObject objects   = view_as<JSONObject>(response.Data);
    JSONObject Response  = view_as<JSONObject>(objects.Get("response"));
    JSONArray  players   = view_as<JSONArray>(Response.Get("players"));
    int        playerlen = players.Length;
    logger.DebugEx("Client %i SteamAPI Response Length: %i", client, playerlen);

    JSONObject player;
    for (int i = 0; i < playerlen; i++)
    {
        player = view_as<JSONObject>(players.Get(i));
        player.GetString("avatarfull", g_SteamAvatars[client], sizeof(g_SteamAvatars[]));
        logger.DebugEx("Client %i has Avatar URL: %s", client, g_SteamAvatars[client]);
        delete player;
    }
}

/**
 * Removes source color codes, and discord strings that could obfuscate logs or annoy people
 */
void SanitiseText(char[] message, int maxLength, bool removeTags = true)
{
    // Make sure people can't mention others
    ReplaceString(message, maxLength, "<@", "");
    // Or insert channel references
    ReplaceString(message, maxLength, "<#", "");
    // Or create code blocks
    ReplaceString(message, maxLength, "`", "'");
    // Or spoiler images that would make logs hard to see at a glance
    ReplaceString(message, maxLength, "||", "");

    // We could also strip @everyone or @here but really you should be tuning this with discord permissions instead

    if (removeTags)
    {
        CRemoveTags(message, maxLength);
    }
}
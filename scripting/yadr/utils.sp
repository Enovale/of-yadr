#include <SteamWorks>
#include <ripext>
#include <morecolors>

#define MAX_MAP_NAME 64
#define MAX_TEAM_NAME 32

char g_SteamApiKey[33];
HTTPClient g_HttpClient;
char g_SteamAvatars[MAXPLAYERS][100];

char[] GetServerIP() {
	char NetIP[16];
	int pieces[4];

	if (SteamWorks_GetPublicIP(pieces)) {
        FormatEx(NetIP, sizeof(NetIP), "%d.%d.%d.%d:%d", pieces[0], pieces[1], pieces[2], pieces[3], GetConVarInt(FindConVar("hostport")));
    } else {
        LogError("Appears like we had an error on getting the Public IP address.");
    }

	return NetIP;
}

public bool IsValidClient(int client) {
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client) || !IsClientConnected(client) || IsFakeClient(client) || IsClientSourceTV(client))
		return false;

	return true;
}

public int GetPlayers(bool connecting) {
	int players;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (connecting && IsClientConnected(i) && !IsClientInGame(i))players++;
		else if (!connecting && IsValidClient(i))players++;
	}
	return players;
}

char[] FormatShortTime(int time) {
	char Time[12];
	int g_iHours = 0;
	int g_iMinutes = 0;
	int g_iSeconds = time;

	while (g_iSeconds > 3600) {
		g_iHours++;
		g_iSeconds -= 3600;
	}
	while (g_iSeconds > 60) {
		g_iMinutes++;
		g_iSeconds -= 60;
	}
	if (g_iHours >= 1)FormatEx(Time, sizeof(Time), "%d:%d:%d", g_iHours, g_iMinutes, g_iSeconds);
	else if (g_iMinutes >= 1)FormatEx(Time, sizeof(Time), "%d:%d", g_iMinutes, g_iSeconds);
	else FormatEx(Time, sizeof(Time), "%d", g_iSeconds);
	return Time;
}

char[] GetClientConnectionTime(int client)
{
    return FormatShortTime(RoundToFloor(GetClientTime(client)));
}

char[] GetNextMapEx()
{
    char buffer[MAX_MAP_NAME];
    bool success = GetNextMap(buffer, sizeof(buffer));
    return success ? buffer : "None";
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
        LogError("ERROR: Steam API Key not configured.");
        return;
    }

    // TODO 1024 is arbitrary
    char requestBuffer[1024], steamId[MAX_AUTHID_LENGTH];

    if (!GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId), true))
    {
        LogError("ERROR: Could not get users steam ID. Are they not authenticated yet?");
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
        LogError("ERROR: Failed to reach SteamAPI. Status: %i", response.Status);
        return;
    }

    JSONObject objects = view_as<JSONObject>(response.Data);
    JSONObject Response = view_as<JSONObject>(objects.Get("response"));
    JSONArray players = view_as<JSONArray>(Response.Get("players"));
    int playerlen = players.Length;
    PrintToConsole(0, "[yadr.smx] DEBUG: Client %i SteamAPI Response Length: %i", client, playerlen);

    JSONObject player;
    for (int i = 0; i < playerlen; i++)
    {
        player = view_as<JSONObject>(players.Get(i));
        player.GetString("avatarfull", g_SteamAvatars[client], sizeof(g_SteamAvatars[]));
        PrintToConsole(0, "[yadr.smx] DEBUG: Client %i has Avatar URL: %s", client, g_SteamAvatars[client]);
        delete player;
    }
}

void SanitiseText(String:message[], int maxLength, bool removeTags = true)
{
    ReplaceString(message, maxLength, "@", "");
    ReplaceString(message, maxLength, "`", "");
    ReplaceString(message, maxLength, "\\", "");
    ReplaceString(message, maxLength, "||", "");
    //ReplaceString(message, maxLength, "# ", "");
    //ReplaceString(message, maxLength, "## ", "");
    //ReplaceString(message, maxLength, "### ", "");

    if (removeTags)
    {
	    CRemoveTags(message, maxLength);
    }
}
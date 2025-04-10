#include <SteamWorks>

#define MAX_MAP_NAME_WITH_TERMINATOR 64
#define SNOWFLAKE_SIZE_WITH_TERMINATOR 20
#define MAX_DISCORD_NAME_LENGTH_WITH_TERMINATOR 33
#define MAX_DISCORD_PRESENCE_LENGTH_WITH_TERMINATOR 129

char[] GetServerIP() {
	char NetIP[16];
	int pieces[4];

	if (SteamWorks_GetPublicIP(pieces)) {
        Format(NetIP, sizeof(NetIP), "%d.%d.%d.%d:%d", pieces[0], pieces[1], pieces[2], pieces[3], GetConVarInt(FindConVar("hostport")));
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
	if (g_iHours >= 1)Format(Time, sizeof(Time), "%d:%d:%d", g_iHours, g_iMinutes, g_iSeconds);
	else if (g_iMinutes >= 1)Format(Time, sizeof(Time), "  %d:%d", g_iMinutes, g_iSeconds);
	else Format(Time, sizeof(Time), "   %d", g_iSeconds);
	return Time;
}

char[] GetClientConnectionTime(int client)
{
    return FormatShortTime(RoundToFloor(GetClientTime(client)));
}
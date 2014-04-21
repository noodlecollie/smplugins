#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>

new Handle:cv_Enabled = INVALID_HANDLE;
new Handle:kvDeaths = INVALID_HANDLE;
new deathNo = 1;

new const String:classnames[] =
{
	"none",
	"scout",
	"sniper",
	"soldier",
	"demoman",
	"medic",
	"heavy",
	"pyro",
	"spy",
	"engineer"
};

public Plugin:myinfo = 
{
	name = "DeathTracker",
	author = "[X6] Herbius",
	description = "Tracks deaths on a map and writes them to a log file.",
	version = "1.0",
	url = "http://x6herbius.com"
}

public OnPluginStart()
{
	LogMessage("===== Death tracker active =====");
	
	CreateConVar("deathtracker_version", "1.0", "Version", FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	cv_Enabled = CreateConVar("deathtracker_enabled", "1", "Enables or disables the tracker.", FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	
	HookEventEx("teamplay_round_start",		Event_RoundStart,		EventHookMode_Post);
	HookEventEx("teamplay_round_win",		Event_RoundWin,			EventHookMode_Post);
	HookEventEx("teamplay_round_stalemate",	Event_RoundStalemate,	EventHookMode_Post);
	HookEventEx("player_death",				Event_PlayerDeath,		EventHookMode_Pre);
}

public OnPluginEnd()
{
	CloseKv();
}

public OnMapStart()
{
	CloseKv();
	deathNo = 1;
}

public OnMapEnd()
{
	CloseKv();
	deathNo = 1;
}

public CvarChange( Handle:convar, const String:oldValue[], const String:newValue[])
{
	if ( convar == cv_Enabled )
	{
		if ( GetConVarBool(cv_Enabled) )
		{
			LogMessage("Death tracker enabled. Tracking will begin when the next round starts.");
		}
		else
		{
			CloseKv();
			deathNo = 1;
			LogMessage("Death tracker disabled.");
		}
	}
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( !GetConVarBool(cv_Enabled) ) return;
	
	kvDeaths = CreateKeyValues("deaths");
	deathNo = 1;
}

public Event_RoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	RoundEnd();	
}

public Event_RoundStalemate(Handle:event, const String:name[], bool:dontBroadcast)
{
	RoundEnd();
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( !GetConVarBool(cv_Enabled) ) return;
	
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	if ( !IsClientInGame(client) ) return;
	
	// Exclude events where the client "bid farewell, cruel world".
	// Victim ID is the same as attacker ID and victim index/inflictor index are the same as the client.
	if ( userid == GetEventInt(event, "attacker") && GetEventInt(event, "victim_entindex") == client && GetEventInt(event, "inflictor_entindex") == client ) return;
	
	decl String:clientName[MAX_NAME_LENGTH];
	Format(clientName, sizeof(clientName), "%N", client);
	
	decl String:clientTeam[64];
	new team = GetClientTeam(client);
	GetTeamName(team, clientTeam, sizeof(clientTeam));
	
	new Float:clientPos[3];
	GetClientAbsOrigin(client, clientPos);
	
	decl String:clientClass[64];
	Format(clientClass, sizeof(clientClass), "%s", classnames[TF2_GetPlayerClass(client)]);
	
	new attacker_id = GetEventInt(event, "attacker");
	new attacker = GetClientOfUserId(attacker_id);
	decl String:attackerTeam[64];
	decl String:attackerName[MAX_NAME_LENGTH];
	decl String:attackerClass[64];
	new Float:attackerPos[3];
	
	if ( IsClientInGame(attacker) )
	{
		Format(attackerName, sizeof(attackerName), "%N", attacker);
		GetTeamName(GetClientTeam(attacker), attackerTeam, sizeof(attackerTeam));
		Format(attackerClass, sizeof(attackerClass), "%s", classnames[TF2_GetPlayerClass(attacker)]);
		GetClientAbsOrigin(attacker, attackerPos);
	}
	else
	{
		Format(attackerName, sizeof(attackerName), "none");
		Format(attackerTeam, sizeof(attackerTeam), "none");
		Format(attackerClass, sizeof(attackerClass), "none");
	}
	
	decl String:keyname[64];
	Format(keyname, sizeof(keyname), "death_%d", deathNo);
	KvJumpToKey(kvDeaths, keyname, true);
	KvSetString(kvDeaths, "victim_name", clientName);
	KvSetString(kvDeaths, "victim_team", clientTeam);
	KvSetString(kvDeaths, "victim_class", clientClass);
	KvSetVector(kvDeaths, "victim_position", clientPos);
	KvSetString(kvDeaths, "attacker_name", attackerName);
	KvSetString(kvDeaths, "attacker_team", attackerTeam);
	KvSetString(kvDeaths, "attacker_class", attackerClass);
	KvSetVector(kvDeaths, "attacker_position", attackerPos);
	KvGoBack(kvDeaths);
	
	deathNo++;
}

stock RoundEnd()
{
	if ( kvDeaths != INVALID_HANDLE )
	{
		// Write death information to file.
		decl String:file[PLATFORM_MAX_PATH];
		decl String:mapname[128];
		GetCurrentMap(mapname, sizeof(mapname));
		Format(file, sizeof(file), "deaths_%s_%d.txt", mapname, GetTime());
		
		KvRewind(kvDeaths);
		KeyValuesToFile(kvDeaths, file);
		CloseKv();
	}
	
	deathNo = 1;
}

stock CloseKv()
{
	if ( kvDeaths != INVALID_HANDLE )
	{
		CloseHandle(kvDeaths);
		kvDeaths = INVALID_HANDLE;
	}
}
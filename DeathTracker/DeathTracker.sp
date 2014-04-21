#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#define MAX_POINTS 128

#define DP_CREATE	"ui/item_acquired.wav"
#define DP_REMOVE	"ui/trade_failure.wav"
#define DP_SAVE		"player/taunt_bell.wav"
#define DP_ERROR	"replay/cameracontrolerror.wav"

#define DP_NAME_LENGTH	128

new Float:g_DeathPoints[MAX_POINTS][3];
new g_DeathsNearPoint[MAX_POINTS];
new g_AvgDeathsNearPoint[MAX_POINTS];
new String:g_PointNames[MAX_POINTS][DP_NAME_LENGTH];
new g_TotalDeathPoints;					// Points to the next free array index (if < MAX_POINTS).
new g_TotalDeaths;
new b_InRound;
new String:g_LogName[128];
new g_RoundCount;

new Handle:cv_MonitorDistance = INVALID_HANDLE;
new Handle:cv_OutputDeaths = INVALID_HANDLE;
new Handle:cv_SortDescending = INVALID_HANDLE;
new Handle:cv_GetMapPoints = INVALID_HANDLE;

public Plugin:myinfo = 
{
	name = "DeathTracker",
	author = "[X6] Herbius",
	description = "Tracks deaths near to specified points.",
	version = "1.0",
	url = "http://x6herbius.com"
}

public OnPluginStart()
{
	LogMessage("=== Death Tracker activated ===");
	
	cv_MonitorDistance  = CreateConVar("dt_distance_from_point",
										"512",
										"Players must be within this distance from a death point when they die to be counted.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.1);
	
	cv_OutputDeaths  = CreateConVar("dt_output_deaths",
										"1",
										"Log each player death to the log file.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0,
										true,
										1.0);
	
	cv_SortDescending  = CreateConVar("dt_output_descending",
										"1",
										"Output death statistics at the end of the round in descending order, according to which point counted the most deaths.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0,
										true,
										1.0);
	
	cv_GetMapPoints  = CreateConVar("dt_get_map_points",
										"1",
										"Load any death points specified by the map (info_targets named 'deathtrackpoint_*') when it starts.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0,
										true,
										1.0);
	
	HookEventEx("teamplay_round_start",		Event_RoundStart,		EventHookMode_Post);
	HookEventEx("teamplay_round_win",		Event_RoundWin,			EventHookMode_Post);
	HookEventEx("teamplay_round_stalemate",	Event_RoundStalemate,	EventHookMode_Post);
	HookEventEx("player_death",				Event_PlayerDeath,		EventHookMode_Pre);
	
	RegConsoleCmd("dt_deathpoint_add",		AddDeathPoint,		"Adds a point to monitor at the current position.", FCVAR_PLUGIN);
	RegConsoleCmd("dt_deathpoint_remove",	RemoveDeathPoint,	"Removes the last death point added.", FCVAR_PLUGIN);
	RegConsoleCmd("dt_dump_deathpoints",	DumpDeathPoints,	"Dumps death points to the console.", FCVAR_PLUGIN);
	RegConsoleCmd("dp_save_deathpoints",	SaveDeathPoints,	"Saves death points to a file.", FCVAR_PLUGIN);
	
	AutoExecConfig(true, "deathtracker", "sourcemod/deathtracker");
}

public OnMapStart()
{
	decl String:mapname[128];
	GetCurrentMap(mapname, sizeof(mapname));
	Format(g_LogName, sizeof(g_LogName), "dmonitor_%s.txt", mapname);
	
	PrecacheSound(DP_CREATE, true);
	PrecacheSound(DP_REMOVE, true);
	PrecacheSound(DP_SAVE, true);
	PrecacheSound(DP_ERROR, true);
	
	ClearDeathPoints();
	if ( GetConVarBool(cv_GetMapPoints) )
	{
		if ( GetDeathPointsFromMap() )LogMessage("Embedded death points loaded.");
		else LogMessage("No embedded death points found.");
		
	}
	
	if ( !ReadDeathPointFile() ) LogMessage("Could not load death point file for map %s", mapname);
	else LogMessage("Loaded death points from file for map %s", mapname);
}

public OnMapEnd()
{
	ClearDeathPoints();
}

stock ClearDeathPoints()
{
	for ( new i = 0; i < MAX_POINTS; i++ )
	{
		g_DeathPoints[i][0] = 0.0;
		g_DeathPoints[i][1] = 0.0;
		g_DeathPoints[i][2] = 0.0;
		
		g_DeathsNearPoint[i] = 0;
		g_AvgDeathsNearPoint[i] = 0;
		g_PointNames[i][0] = '\0';
	}
	
	g_TotalDeathPoints = 0;
	g_TotalDeaths = 0;
	g_RoundCount = 0;
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	b_InRound = true;
	
	for ( new i = 0; i < MAX_POINTS; i++ )
	{
		g_DeathsNearPoint[i] = 0;
	}
	
	g_TotalDeaths = 0;
	
	decl String:mapname[128];
	GetCurrentMap(mapname, sizeof(mapname));
	
	LogToFile(g_LogName, "=== Round %d start on map %s, death counts reset. ===", g_RoundCount+1, mapname);
}

public Event_RoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	b_InRound = false;
	g_RoundCount++;
	
	LogToFile(g_LogName, "=== Round %d win, death statistics: ===", g_RoundCount);
	
	DeathStats();
}

public Event_RoundStalemate(Handle:event, const String:name[], bool:dontBroadcast)
{
	b_InRound = false;
	g_RoundCount++;
	
	LogToFile(g_LogName, "=== Round %d stalemate, death statistics: ===", g_RoundCount);
	
	DeathStats();
}

stock DeathStats()
{
	for ( new i = 0; i < g_TotalDeathPoints; i++ )
	{
		g_AvgDeathsNearPoint[i] += g_DeathsNearPoint[i];
	}
	
	new pointdeaths;
	
	if ( !GetConVarBool(cv_SortDescending) )
	{
		for ( new i = 0; i < g_TotalDeathPoints; i++ )
		{
			LogToFile(g_LogName, "[%d] %s (%f %f %f): %d (%f)", i+1, g_PointNames[i], g_DeathPoints[i][0], g_DeathPoints[i][1], g_DeathPoints[i][2], g_DeathsNearPoint[i], g_AvgDeathsNearPoint[i]/g_RoundCount);
			pointdeaths += g_DeathsNearPoint[i];
		}
	}
	else
	{
		new Points[g_TotalDeathPoints];
		
		for ( new i = 0; i < g_TotalDeathPoints; i++ )
		{
			Points[i] = i;
		}
		
		//SortCustom2D(Points, g_TotalDeathPoints, SortDeathPoints);
		SortCustom1D(Points, g_TotalDeathPoints, SortDeathPoints);
		
		for ( new i = 0; i < g_TotalDeathPoints; i++ )
		{
			LogToFile(g_LogName, "[%d] %s (%f %f %f): %d (%f)", Points[i]+1, g_PointNames[Points[i]], g_DeathPoints[Points[i]][0], g_DeathPoints[Points[i]][1], g_DeathPoints[Points[i]][2], g_DeathsNearPoint[Points[i]], g_AvgDeathsNearPoint[Points[i]/g_RoundCount]/g_RoundCount);
			pointdeaths += g_DeathsNearPoint[Points[i]];
		}
	}
	
	LogToFile(g_LogName, "=== Total counted deaths: %d. Total overall deaths: %d ===", pointdeaths, g_TotalDeaths);
}

public SortDeathPoints(elem1, elem2, const array[], Handle:hndl)
{
	if ( g_DeathsNearPoint[elem1] > g_DeathsNearPoint[elem2] )
	{
		//LogMessage("%d > %d (indices %d and %d)", g_DeathsNearPoint[elem1], g_DeathsNearPoint[elem2], elem1, elem2);
		return -1;	// If more points at 1, 1 should go before 2.
	}
	else if ( g_DeathsNearPoint[elem1] < g_DeathsNearPoint[elem2] )
	{
		//LogMessage("%d < %d (indices %d and %d)", g_DeathsNearPoint[elem1], g_DeathsNearPoint[elem2], elem1, elem2);
		return 1;	// If less points at 1, 1 should go after 2.
	}
	
	//LogMessage("%d == %d (indices %d and %d)", g_DeathsNearPoint[elem1], g_DeathsNearPoint[elem2], elem1, elem2);
	return 0;		// Otherwise 1 and 2 are equal.
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( !b_InRound ) return;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	g_TotalDeaths++;	// Add to the total deaths counter.
	
	new Float:dist = GetConVarFloat(cv_MonitorDistance);
	
	new Float:pos[3];
	GetClientAbsOrigin(client, pos);
	
	new Float:mindist = dist + 1.0;
	new closestpoint = -1;					// Array index
	
	// Cycle through points and check to see whether the player is close enough to be counted.
	// The closest point within the valid distance is the one to be counted towards.
	
	for ( new i = 0; i < g_TotalDeathPoints; i++ )
	{
		new Float:newdist = GetVectorDistance(pos, g_DeathPoints[i]);
		
		if ( newdist <= dist && newdist < mindist )	// Death was near enough to the specified point and was less than any other distance so far.
		{
			mindist = newdist;
			closestpoint = i;
		}
	}
	
	// Check to see if we were near enough to any points.
	if ( closestpoint < 0 ) return;
	
	g_DeathsNearPoint[closestpoint]++;
	
	if ( GetConVarBool(cv_OutputDeaths) ) LogToFile(g_LogName, "Client %N died nearest to point %d (%s). Total deaths near this point: %d.", client, closestpoint+1, g_PointNames[closestpoint], g_DeathsNearPoint[closestpoint]);
}

public Action:AddDeathPoint(client, args)
{
	if ( client < 1 || client > MaxClients || !IsClientInGame(client) ) return Plugin_Handled;
	
	if ( g_TotalDeathPoints >= MAX_POINTS )
	{
		EmitSoundToClient(client, DP_REMOVE);
		ReplyToCommand(client, "Maximum number of death points reached.");
		return Plugin_Handled;
	}
	
	decl String:name[DP_NAME_LENGTH];
	if ( GetCmdArgs() > 0 )
	{
		GetCmdArg(1, name, sizeof(name));
	}
	else
	{
		Format(name, sizeof(name), "DEATHPOINT_%d", g_TotalDeathPoints+1);
	}
	
	g_PointNames[g_TotalDeathPoints] = name;
	
	GetClientAbsOrigin(client, g_DeathPoints[g_TotalDeathPoints]);
	g_TotalDeathPoints++;
	
	EmitSoundToClient(client, DP_CREATE);
	
	ReplyToCommand(client, "Death point %d named %s, location %f %f %f", g_TotalDeathPoints, g_PointNames[g_TotalDeathPoints-1], g_DeathPoints[g_TotalDeathPoints-1][0], g_DeathPoints[g_TotalDeathPoints-1][1], g_DeathPoints[g_TotalDeathPoints-1][2]);
	return Plugin_Handled;
}

public Action:RemoveDeathPoint(client, args)
{
	if ( client < 1 || client > MaxClients || !IsClientInGame(client) ) return Plugin_Handled;
	
	if ( g_TotalDeathPoints <= 0 )
	{
		ReplyToCommand(client, "No death points to remove.");
		return Plugin_Handled;
	}
	
	if ( GetCmdArgs() > 0 )
	{
		decl String:s_pointnum[8];
		GetCmdArg(1, s_pointnum, sizeof(s_pointnum));
		new pointnum = StringToInt(s_pointnum);			// pointnum is one greater than the point index.
		
		if ( pointnum < 1 || pointnum > g_TotalDeathPoints )
		{
			ReplyToCommand(client, "Death point number %d does not exist.", pointnum);
			return Plugin_Handled;
		}
		
		decl String:pointname[DP_NAME_LENGTH];
		pointname = g_PointNames[pointnum-1];
		
		if ( RemoveGlobalArrayElement(pointnum-1) )
		{
			EmitSoundToClient(client, DP_REMOVE);
			ReplyToCommand(client, "Death point [%d] %s removed.", pointnum, pointname);
		}
		else
		{
			EmitSoundToClient(client, DP_ERROR);
			ReplyToCommand(client, "Error removing death point %d.", pointnum);
		}
		return Plugin_Handled;
	}
	
	g_DeathPoints[g_TotalDeathPoints-1][0] = 0.0;
	g_DeathPoints[g_TotalDeathPoints-1][1] = 0.0;
	g_DeathPoints[g_TotalDeathPoints-1][2] = 0.0;
	g_DeathsNearPoint[g_TotalDeathPoints-1] = 0;
	g_AvgDeathsNearPoint[g_TotalDeathPoints-1] = 0;
	
	decl String:pointname[DP_NAME_LENGTH];
	pointname = g_PointNames[g_TotalDeathPoints-1];
	g_PointNames[g_TotalDeathPoints-1][0] = '\0';
	
	g_TotalDeathPoints--;
	
	EmitSoundToClient(client, DP_REMOVE);
	
	ReplyToCommand(client, "Death point [%d] %s removed.", g_TotalDeathPoints+1, pointname);
	return Plugin_Handled;
}

public Action:DumpDeathPoints(client, args)
{
	if ( client < 1 || client > MaxClients || !IsClientInGame(client) ) return Plugin_Handled;
	
	for ( new i = 0; i < /*MAX_POINTS*/ g_TotalDeathPoints; i++ )
	{
		PrintToConsole(client, "Point index %d: %f %f %f", i, g_DeathPoints[i][0], g_DeathPoints[i][1], g_DeathPoints[i][2]);
	}
	
	return Plugin_Handled;
}

public Action:SaveDeathPoints(client, args)
{
	if ( client < 1 || client > MaxClients || !IsClientInGame(client) ) return Plugin_Handled;
	
	if ( !WriteDeathPointFile() )
	{
		EmitSoundToClient(client, DP_ERROR);
		ReplyToCommand(client, "Death point file unable to be written.");
	}
	else
	{
		EmitSoundToClient(client, DP_SAVE);
		ReplyToCommand(client, "Death point file written successfully.");
	}
	
	return Plugin_Handled;
}

/*	Gets death points from map and places them in the global arrays.
	Returns true if points were found.	*/
stock bool:GetDeathPointsFromMap()
{
	new bool:found = false;
	
	// Any info_targets with their name prefixed with "deathtrackpoint_" will be included.
	new i;
	while ( ( i = FindEntityByClassname(i, "info_target")) != -1 )
	{
		decl String:name[192];
		GetEntPropString(i, Prop_Data, "m_iName", name, sizeof(name));
		
		if ( StrContains(name, "deathtrackpoint_", true) == 0 )
		{
			// Remove the prefix.
			ReplaceString(name, sizeof(name), "deathtrackpoint_", "");
			
			if ( g_TotalDeathPoints >= MAX_POINTS )
			{
				LogError("Max death points reached, could not add %s", name);
				continue;
			}
			
			new Float:origin[3];
			GetEntPropVector(i, Prop_Send, "m_vecOrigin", origin);
			
			// Record the point.
			g_DeathPoints[g_TotalDeathPoints][0] = origin[0];
			g_DeathPoints[g_TotalDeathPoints][1] = origin[1];
			g_DeathPoints[g_TotalDeathPoints][2] = origin[2];
			
			decl String:buffer[DP_NAME_LENGTH];
			Format(buffer, sizeof(buffer), "%s", name);
			g_PointNames[g_TotalDeathPoints] = buffer;
			
			g_TotalDeathPoints++;
			found = true;
		}
	}
	
	return found;
}

/*	Returns true on success, false on failure.	*/
stock bool:ReadDeathPointFile()
{
	new Handle:kv = CreateKeyValues("DeathPoints");
	
	if ( kv == INVALID_HANDLE ) return false;
	
	decl String:buffer[128], String:mapname[64];
	GetCurrentMap(mapname, sizeof(mapname));
	Format(buffer, sizeof(buffer), "scripts/dmonitor/%s.txt", mapname);
	if ( !FileToKeyValues(kv, buffer) ) return false;
	
	/*for ( new i = 0; i < g_TotalDeathPoints; i++ )
	{
		g_DeathPoints[i][0] = 0.0;
		g_DeathPoints[i][1] = 0.0;
		g_DeathPoints[i][2] = 0.0;
		
		g_DeathsNearPoint[i] = 0;
		g_AvgDeathsNearPoint[i] = 0;
		g_PointNames[i][0] = '\0';
	}
	
	g_TotalDeathPoints = 0;
	g_TotalDeaths = 0;
	g_RoundCount = 0;*/
	
	if ( KvGotoFirstSubKey(kv) )
	{
		new Float:pos[3];
		decl String:name[DP_NAME_LENGTH];
		
		do
		{
			if ( g_TotalDeathPoints < MAX_POINTS )
			{
				KvGetString(kv, "name", name, sizeof(name), "NULL");
				KvGetVector(kv, "position", pos);
				
				if ( MatchGlobalVector(pos) > -1 )
				{
					LogMessage("Duplicate death point at %f,%f,%f found in death point file, ignoring...");
					continue;
				}
				
				g_DeathPoints[g_TotalDeathPoints][0] = pos[0];
				g_DeathPoints[g_TotalDeathPoints][1] = pos[1];
				g_DeathPoints[g_TotalDeathPoints][2] = pos[2];
				g_PointNames[g_TotalDeathPoints] = name;
				
				g_TotalDeathPoints++;
			}
			else
			{
				LogError("Error importing death points from file: max death points reached.");
			}
			
		} while ( KvGotoNextKey(kv) );
	}
	else
	{
		CloseHandle(kv);
		return false;
	}
	
	CloseHandle(kv);
	
	return true;
}

/*	Returns true on success, false on failure.	*/
stock bool:WriteDeathPointFile()
{
	new Handle:kv = CreateKeyValues("DeathPoints");
	
	if ( kv != INVALID_HANDLE )
	{
		for ( new i = 0; i < g_TotalDeathPoints; i++ )
		{
			decl String:Buffer[8];
			IntToString(i, Buffer, sizeof(Buffer));
			KvJumpToKey(kv, Buffer, true);
			
			KvSetString(kv, "name", g_PointNames[i]);
			
			new Float:pos[3];
			pos[0] = g_DeathPoints[i][0];
			pos[1] = g_DeathPoints[i][1];
			pos[2] = g_DeathPoints[i][2];
			KvSetVector(kv, "position", pos);
			
			KvGoBack(kv);
		}
		
		decl String:FilePath[128], String:mapname[64];
		GetCurrentMap(mapname, sizeof(mapname));
		Format(FilePath, sizeof(FilePath), "scripts/dmonitor/%s.txt", mapname);
		
		if ( !KeyValuesToFile(kv, FilePath) )
		{
			CloseHandle(kv);
			return false;
		}
		
		CloseHandle(kv);
		
		return true;
	}
	
	return false;
}

/*	Removes a death point entry from the arrays.	*/
stock bool:RemoveGlobalArrayElement(element)
{
	// If we're pointing to an element that's not a valid death point, return.
	if ( element >= g_TotalDeathPoints ) return false;
	
	// Shift each element down in the arrays.
	for ( new i = element; i < g_TotalDeathPoints-1; i++ )	// i must be less than the last valid element.
	{
		g_DeathPoints[i][0] = g_DeathPoints[i+1][0];
		g_DeathPoints[i][1] = g_DeathPoints[i+1][1];
		g_DeathPoints[i][2] = g_DeathPoints[i+1][2];
		
		g_DeathsNearPoint[i] = g_DeathsNearPoint[i+1];
		g_AvgDeathsNearPoint[i] = g_AvgDeathsNearPoint[i+1];
		
		//Format(g_PointNames[i], sizeof(g_PointNames[i]) "%s", g_PointNames[i+1]);
		g_PointNames[i] = g_PointNames[i+1];
	}
	
	// Zero out the last element.
	g_DeathPoints[g_TotalDeathPoints-1][0] = 0.0;
	g_DeathPoints[g_TotalDeathPoints-1][1] = 0.0;
	g_DeathPoints[g_TotalDeathPoints-1][2] = 0.0;
	
	g_DeathsNearPoint[g_TotalDeathPoints-1] = 0;
	g_AvgDeathsNearPoint[g_TotalDeathPoints-1] = 0;
		
	g_PointNames[g_TotalDeathPoints-1][0] = '\0';
	
	// Decrease our total number of death points.
	g_TotalDeathPoints--;
	
	return true;
}

/*	If return is > -1, a matching vector at this index has been found.	*/
stock MatchGlobalVector(Float:vector[3])
{
	if ( g_TotalDeathPoints < 1 ) return -1;
	
	for ( new i = 0; i < g_TotalDeathPoints; i++ )
	{
		if ( g_DeathPoints[i][0] == vector[0] &&
			 g_DeathPoints[i][1] == vector[1] &&
			 g_DeathPoints[i][2] == vector[2] ) return i;
	}
	
	return -1;
}
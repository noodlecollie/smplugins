#include <sourcemod>
//#include <tf2>
//#include <sdktools>
#include <sdkhooks>
//#include <tf2_stocks>

#define PLUGIN_NAME			"Damage Tracker"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Tracks damage."
#define PLUGIN_VERSION		"0.0.0.1"
#define PLUGIN_URL			"http://x6herbius.com/"

public Plugin:myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
}

public OnPluginStart()
{
	LogMessage("== %s v%s ==", PLUGIN_NAME, PLUGIN_VERSION);
	
	HookEventEx("player_hurt",		Event_PlayerHurt,		EventHookMode_Pre);
	HookEventEx("player_death",		Event_PlayerDeath,		EventHookMode_Pre);
	
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientConnected(i) && !IsClientReplay(i) && !IsClientSourceTV(i) )
		{
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
			SDKHook(i, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
		}
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage,		OnTakeDamage);
	SDKHook(client, SDKHook_OnTakeDamagePost,	OnTakeDamagePost);
}

public OnClientDisconnect(client)
{
	SDKUnhook(client, SDKHook_OnTakeDamage,		OnTakeDamage);
	SDKUnhook(client, SDKHook_OnTakeDamagePost,	OnTakeDamagePost);
}

public Action:OnTakeDamage(client, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3])
{
	LogMessage("Pre: client %N damaged by client %N Inflictor %d Damage %f Flags %d Weapon %d Health remaining %d", client, attacker, inflictor, damage, damagetype, weapon, GetEntProp(client, Prop_Send, "m_iHealth"));
}

public Action:OnTakeDamagePost(client, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3])
{
	LogMessage("Post: client %N damaged by client %d Inflictor %d Damage %f Flags %d Weapon %d Health remaining %d", client, attacker, inflictor, damage, damagetype, weapon, GetEntProp(client, Prop_Send, "m_iHealth"));
}

public Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new health = GetEventInt(event, "health");
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new damageamount = GetEventInt(event, "damageamount");
	new custom = GetEventInt(event, "custom");
	new bool:showdisguisedcrit = GetEventBool(event, "showdisguisedcrit");
	new bool:crit = GetEventBool(event, "crit");
	new bool:minicrit = GetEventBool(event, "minicrit");
	new bool:allseecrit = GetEventBool(event, "allseecrit");
	new weaponid = GetEventInt(event, "weaponid");
	
	LogMessage("Hurt: Client %N damaged by client %N Health %d Damageamount %d Custom %d Showdisguisedcrit %d Crit %d Minicrit %d Allseecrit %d Weaponid %d", client, attacker, health, damageamount, custom, showdisguisedcrit, crit, minicrit, allseecrit, weaponid);
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	LogMessage("%N died.", client);
}
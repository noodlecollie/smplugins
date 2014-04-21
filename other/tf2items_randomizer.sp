#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <tf2items>
#undef REQUIRE_EXTENSIONS
#include <sdkhooks>
#define REQUIRE_EXTENSIONS
#undef REQUIRE_PLUGIN
#tryinclude <tf2items_giveweapon>
#tryinclude <visweps>
#define REQUIRE_PLUGIN

#define PLUGIN_NAME		"[TF2Items] Randomizer"
#define PLUGIN_AUTHOR		"FlaminSarge"
#define PLUGIN_VERSION		"1.4" //as of Apr 15, 2011 or after
#define PLUGIN_CONTACT		"http://doacommunity.proboards.com or http://gaming.calculatedchaos.com"
#define PLUGIN_DESCRIPTION	"[TF2] Randomizer rebuilt around TF2Items extension"

public Plugin:myinfo = {
	name			= PLUGIN_NAME,
	author			= PLUGIN_AUTHOR,
	description	= PLUGIN_DESCRIPTION,
	version		= PLUGIN_VERSION,
	url				= PLUGIN_CONTACT
};

//new m_iAmmo;
// randomization
new TFClassType:setclass[MAXPLAYERS + 1];
new setwep[MAXPLAYERS + 1][3];
new cloakwep[MAXPLAYERS + 1];
new TFClassType:getclass[MAXPLAYERS + 1];
new bool:RoundStarted;
new pOldAmmo[MAXPLAYERS + 1];
new bool:g_bMapLoaded = false;
new bool:pUbered[MAXPLAYERS + 1] = false;
//new playerWeapon[MAXPLAYERS + 1][6][2] = -1;
new bool:visibleweapons = false;
new bool:medievalmode = false;
new bool:tf2items_giveweapon = false;
new Handle:g_hSdkEquipWearable;
new bool:g_bSdkStarted;
new isJarated[MAXPLAYERS + 1];

// cvars
new cvar_enabled;
new cvar_partial;
new cvar_destroy;
//new cvar_fixammo;
new cvar_fixpyro;
new cvar_fixspy;
new cvar_fixuber;
new cvar_betaweapons;
new cvar_customweapons;
new cvar_fixreload;
new cvar_goldenwrench;
new cvar_fixfood;
new cvar_gamedesc;
new cvar_manifix;
new cvar_spycloak;

// fixes
//new ammo_count[MAXPLAYERS + 1][2];
//new spy_status[MAXPLAYERS + 1];
new heal_beams[MAXPLAYERS + 1];
new healtarget[MAXPLAYERS + 1];
new infotarget[MAXPLAYERS + 1];

//weapons
static const weapon_primary[] = {-1, 13, 14, 15, 17, 18, 19, 21, 24, 36, 40, 41, 45, 56, 61, 127, 141, 161, 2041, 2141, 215, 228, 220, 224, 237, 230, 2228, 9, 298, 305, 308, 312, 412};
static const String:weapon_primary_name[][] = {"Normal", "Scattergun", "Sniper Rifle", "Minigun", "Syringe Gun", "Rocket Launcher", "Grenade Launcher", "Flamethrower", "Revolver", "Blutsauger", "Backburner", "Natascha", "Force-a-Nature", "Hunstman", "Ambassador", "Direct Hit", "Frontier Justice", "Big Kill", "Ludmila", "Texas Ten-Shot", "Degreaser", "Black Box", "Shortstop", "L'Etranger", "Rocket Jumper", "Sydney Sleeper", "The Army of One", "Shotgun", "Iron Curtain", "Crusader's Crossbow", "Loch-n-Load", "Brass Beast", "Beta Syringe Gun"};
static const weapon_secondary[] = {-1, 16, 20, 29, 35, 39, 42, 46, 58, 130, 140, 159, 163, 222, 226, 129, 265, 311, 22, 294, 231, 57, 131, 133, 2058, 354, 351, 186};
static const String:weapon_secondary_name[][] = {"Normal", "SMG", "Sticky Launcher", "Medigun", "Kritzkrieg", "Flare Gun", "Sandvich", "Bonk! Atomic Punch", "Jarate", "Scottish Resistance", "Wrangler", "Dalokohs Bar", "Crit-a-Cola", "Mad Milk", "Battalion's Backup", "Buff Banner", "Sticky Jumper", "Buffalo Steak Sandvich", "Pistol", "Lugermorph", "Darwin's Danger Shield", "Razorback", "Chargin' Targe", "Gunboats", "Jar of Ants", "The Concheror", "Detonator", "Quick-Fix"};
static const weapon_tertiary[] = {-1, 0, 2, 3, 4, 195, 7, 8, 37, 38, 43, 44, 132, 142, 153, 155, 171, 172, 239, 214, 221, 225, 232, 173, 169, 266, 2193, 2171, 304, 307, 310, 317, 325, 326, 327, 329, 331, 2197, 1, 6, 128, 154, 264, 348, 349, 355, 356, 357};
static const String:weapon_tertiary_name[][] = {"Normal", "Bat", "Fire Axe", "Kukri", "Knife", "Fists", "Wrench", "Bonesaw", "Ubersaw", "Axetinguisher", "Killing Gloves of Boxing", "Sandman", "Eyelander", "Gunslinger", "Homewrecker", "Southern Hospitality", "Tribalman's Shiv", "Scotsman's Skullcutter", "Gloves of Running Urgently", "Powerjack", "Holy Mackerel", "Your Eternal Reward", "Bushwacka", "Vita-Saw", "Golden Wrench", "Horseless Headless Horsemann's Headtaker", "Fighter's Falcata", "Khopesh Climber", "Amputator", "Ullapool Caber", "Warrior's Spirit", "Candy Cane", "Boston Basher", "Backscratcher", "Claidheamh Mor", "Jag", "Fists of Steel", "Rebel's Curse", "Bottle", "Shovel", "Equalizer", "Pain Train", "Frying Pan", "Sharpened Volcano Fragment", "Sun-on-a-Stick", "The Fan O'War", "Conniver's Kunai", "The Half-Zatoichi"};
static const weapon_cloakary[] = {-1, 30, 59, 60, 297};
static const String:weapon_cloakary_name[][] = {"Normal", "Invisibility Watch", "Dead Ringer", "Cloak and Dagger", "Enthusiast's Timepiece"};
// so clever at naming these things^
new Handle:g_hItemInfoTrie = INVALID_HANDLE;
new pReloadCooldown[MAXPLAYERS + 1];
new pEatCooldown[MAXPLAYERS + 1];
new pBonkCooldown[MAXPLAYERS + 1];
new pJarCooldown[MAXPLAYERS + 1];
new pBallCooldown[MAXPLAYERS + 1];
new Handle:BonkCooldownTimer[MAXPLAYERS + 1];
new Handle:BallCooldownTimer[MAXPLAYERS + 1];
new Handle:JarCooldownTimer[MAXPLAYERS + 1];
new Handle:EatCooldownTimer[MAXPLAYERS + 1];
new pLongEatCooldown[MAXPLAYERS + 1];
new pDalokohsBuff[MAXPLAYERS + 1];
new Handle:DalokohsBuffTimer[MAXPLAYERS + 1];
new Handle:hMaxHealth;

//new Handle:max_ammo;
public OnPluginStart()
{
	decl String:strModName[32]; GetGameFolderName(strModName, sizeof(strModName));
	if (!StrEqual(strModName, "tf")) SetFailState("[TF2Items] Randomizer is for TF2 only");
	//Freaking SDKCalls... T_T
	new Handle:GameConf = LoadGameConfigFile("tf2items.randomizer");
	if(GameConf == INVALID_HANDLE)
	{
		SetFailState("Could not locate tf2items.randomizer.txt in gamedata folder");
		return;
	}
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(GameConf, SDKConf_Virtual, "CTFPlayer_GetMaxHealth");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hMaxHealth = EndPrepSDKCall();
	if(hMaxHealth == INVALID_HANDLE)
	{
		SetFailState("Could not initialize call for CTFPlayer::GetMaxHealth");
		CloseHandle(GameConf);
		return;
	}
	CloseHandle(GameConf);
	
	/***********
	 * ConVars *
	 ***********/
	new Handle:cv_version = CreateConVar("tf2items_rnd_version", PLUGIN_VERSION, "[TF2Items]Randomizer Version", FCVAR_REPLICATED|FCVAR_NOTIFY | FCVAR_PLUGIN | FCVAR_SPONLY);
	new Handle:cv_enabled = CreateConVar("tf2items_rnd_enabled", "0", "Enables/disables forcing random class and giving random weapons.", FCVAR_NOTIFY | FCVAR_PLUGIN, true, 0.0, true, 1.0);
	new Handle:cv_partial = CreateConVar("tf2items_rnd_normals", "0", "If >0, increases chance of each weapon roll being set to normal.", FCVAR_NOTIFY | FCVAR_PLUGIN, true, 0.0, true, 100.0);
	new Handle:cv_destroy = CreateConVar("tf2items_rnd_destroy_buildings", "1", "Destroys Engineer buildings when a player respawns as a different class.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
//	new Handle:cv_fixammo = CreateConVar("tf2items_rnd_fix_ammo", "1", "Emulates proper ammo handling.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	new Handle:cv_fixpyro = CreateConVar("tf2items_rnd_fix_pyro", "1", "Properly limits the Pyro's speed when scoped or spun down.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	new Handle:cv_fixspy  = CreateConVar("tf2items_rnd_fix_spy", "1", "0 = don't check, 1 = force undisguise on all attacks", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	new Handle:cv_fixuber = CreateConVar("tf2items_rnd_fix_uber", "1", "Emulates Ubercharges for non-Medic classes with the Medigun.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	new Handle:cv_customweapons = CreateConVar("tf2items_rnd_customweapons", "1", "Includes Custom Weapons in the Randomizer.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	new Handle:cv_betaweapons = CreateConVar("tf2items_rnd_betaweapons", "1", "Includes Ludmila in the Randomizer.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	new Handle:cv_fixreload = CreateConVar("tf2items_rnd_fix_reload", "1", "Stops Revolver reload exploit for non-spies.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	new Handle:cv_goldenwrench = CreateConVar("tf2items_rnd_godweapons", "1", "Allows Randomizer to give the Golden Wrench and Headtaker.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	new Handle:cv_fixfood = CreateConVar("tf2items_rnd_fix_food", "1", "Emulates Food items for non-Heavies and non-Scouts", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	new Handle:cv_gamedesc = CreateConVar("tf2items_rnd_gamedesc", "1", "If SDKHooks is installed, set to 1 to change the gametype to [TF2Items]Randomizer vVERSION when Randomizer is enabled", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	new Handle:cv_gdmanifix = CreateConVar("tf2items_rnd_manifix_gd", "0", "If gamedesc is on, enable if 3rd party plugins have trouble detecting gametype", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	new Handle:cv_spycloak = CreateConVar("tf2items_rnd_cloaks", "1", "If enabled, randomize a Spy's cloak", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	
	HookConVarChange(cv_enabled, cvhook_enabled);
	HookConVarChange(cv_partial, cvhook_partial);
	HookConVarChange(cv_destroy, cvhook_destroy);
//	HookConVarChange(cv_fixammo, cvhook_fixammo);
	HookConVarChange(cv_fixpyro, cvhook_fixpyro);
	HookConVarChange(cv_fixspy,  cvhook_fixspy);
	HookConVarChange(cv_fixuber, cvhook_fixuber);
	HookConVarChange(cv_betaweapons, cvhook_betaweapons);
	HookConVarChange(cv_customweapons, cvhook_customweapons);
	HookConVarChange(cv_fixreload, cvhook_fixreload);
	HookConVarChange(cv_goldenwrench, cvhook_goldenwrench);
	HookConVarChange(cv_fixfood, cvhook_fixfood);
	HookConVarChange(cv_gamedesc, cvhook_gamedesc);
	HookConVarChange(cv_gdmanifix, cvhook_manifix);
	HookConVarChange(cv_spycloak, cvhook_spycloak);
	
	SetConVarString(cv_version, PLUGIN_VERSION);
	cvar_enabled = GetConVarBool(cv_enabled);
	cvar_partial = GetConVarInt(cv_partial);
	cvar_destroy = GetConVarBool(cv_destroy);
//	cvar_fixammo = GetConVarBool(cv_fixammo);
	cvar_fixpyro = GetConVarBool(cv_fixpyro);
	cvar_fixspy = GetConVarBool(cv_fixspy);
	cvar_fixuber = GetConVarBool(cv_fixuber);
	cvar_betaweapons = GetConVarBool(cv_betaweapons);
	cvar_customweapons = GetConVarBool(cv_customweapons);
	cvar_fixreload = GetConVarBool(cv_fixreload);
	cvar_goldenwrench = GetConVarBool(cv_goldenwrench);
	cvar_fixfood = GetConVarBool(cv_fixfood);
	cvar_gamedesc = GetConVarBool(cv_gamedesc);
	cvar_manifix = GetConVarBool(cv_gdmanifix);
	cvar_spycloak = GetConVarBool(cv_spycloak);
	
	/***********
	 * Commands *
	 ***********/
	RegAdminCmd("tf2items_rnd_enable", Command_EnableRnd, ADMFLAG_CONVARS, "Changes the tf2items_rnd_enabled cvar to 1");
	RegAdminCmd("tf2items_rnd_disable", Command_DisableRnd, ADMFLAG_CONVARS, "Changes the tf2items_rnd_enabled cvar to 0");
	RegAdminCmd("tf2items_rnd_reroll", Command_Reroll, ADMFLAG_CHEATS, "Rerolls a player: tf2items_rnd_reroll <target>");
	RegAdminCmd("sm_reroll", Command_Reroll, ADMFLAG_CHEATS, "Rerolls a player: sm_reroll <target>");
//	RegConsoleCmd("sm_rollme", Command_RollMe, 
	
	//Translations file...
	LoadTranslations("common.phrases");
	/************************
	 * Event & Entity Hooks *
	 ************************/
	HookEvent("player_spawn", player_spawn);
	HookEvent("player_death", player_death);
	HookEvent("player_death", Event_PlayerDeathPost, EventHookMode_Post);	//same as previous line, but I dun wanna mess with my killtimer stuff
	HookEvent("teamplay_round_win", round_win, EventHookMode_PostNoCopy);
	HookEvent("post_inventory_application", lockerwepreset,  EventHookMode_Post);
	HookEvent("teamplay_round_start", Roundstart, EventHookMode_PostNoCopy);
	HookEvent("teamplay_round_active", Roundactive, EventHookMode_PostNoCopy);
	HookUserMessage(GetUserMessageId("PlayerJarated"), Event_PlayerJarated);
	HookUserMessage(GetUserMessageId("PlayerJaratedFade"), Event_PlayerJaratedFade);
	HookEvent("player_hurt", Event_PlayerHurt);
	
	HookEntityOutput("item_ammopack_small", "OnPlayerTouch", touch_ammo_small);
	HookEntityOutput("item_ammopack_medium", "OnPlayerTouch", touch_ammo_medium);
	HookEntityOutput("item_ammopack_full", "OnPlayerTouch", touch_ammo_full);
	HookEntityOutput("tf_ammo_pack", "OnPlayerTouch", touch_ammo_medium);
//	MarkNativeAsOptional("VisWep_GiveWeapon");
	//Item Trie
	CreateItemInfoTrie();
	
	visibleweapons = LibraryExists("visweps");
	tf2items_giveweapon = LibraryExists("tf2items_giveweapon");
	
	TF2_SdkStartup();
}

//m_iAmmo = FindSendPropInfo("CTFPlayer", "m_iAmmo");

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, "visweps"))
	{
		visibleweapons = false;
	}
	LogMessage("Library %s removed from Randomizer", name);
//	PrintToChatAll("Library %s removed", name);
	if (StrEqual(name, "tf2items_giveweapon"))
	{
		tf2items_giveweapon = false;
	}
}
 
public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "visweps"))
	{
		visibleweapons = true;
	}
	LogMessage("Library %s added for Randomizer", name);
//	PrintToChatAll("Library %s added", name);
	if (StrEqual(name, "tf2items_giveweapon"))
	{
		tf2items_giveweapon = true;
	}
}
public OnClientPutInServer(client)
{
	SetRandomization(client);
	pReloadCooldown[client] = false;
	pBonkCooldown[client] = false;
	pEatCooldown[client] = false;
	pLongEatCooldown[client] = false;
	pDalokohsBuff[client] = false;
	pJarCooldown[client] = false;
	pBallCooldown[client] = false;
	isJarated[client] = false;
/*	BonkCooldownTimer[client] = INVALID_HANDLE;
	EatCooldownTimer[client] = INVALID_HANDLE;
	DalokohsBuffTimer[client] = INVALID_HANDLE;
	JarCooldownTimer[client] = INVALID_HANDLE;
	BallCooldownTimer[client] = INVALID_HANDLE;*/
}

public OnClientDisconnect_Post(client)
{
	pReloadCooldown[client] = false;
	pBonkCooldown[client] = false;
	pEatCooldown[client] = false;
	pLongEatCooldown[client] = false;
	pDalokohsBuff[client] = false;
	pJarCooldown[client] = false;
	pBallCooldown[client] = false;
	isJarated[client] = false;
	BonkCooldownTimer[client] = INVALID_HANDLE;
	EatCooldownTimer[client] = INVALID_HANDLE;
	DalokohsBuffTimer[client] = INVALID_HANDLE;
	JarCooldownTimer[client] = INVALID_HANDLE;
	BallCooldownTimer[client] = INVALID_HANDLE;
}

public Action:Event_PlayerDeathPost(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (tf2items_giveweapon) return Plugin_Continue;
//	if (!cvar_enabled) return Plugin_Continue;
//	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
//	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
//	new customkill = GetEventInt(event, "customkill");
	new weapon = GetEventInt(event, "weaponid");
	new inflictor = GetEventInt(event, "inflictor_entindex");
	if (!IsValidEdict(inflictor))
	{
		inflictor = 0;
	}
	if (weapon == TF_WEAPON_WRENCH)
	{
		if (IsValidClient(inflictor))
		{
			new weaponent = GetEntPropEnt(inflictor, Prop_Send, "m_hActiveWeapon");
			if (weaponent > -1 && GetEntProp(weaponent, Prop_Send, "m_iItemDefinitionIndex") == 197 && GetEntProp(weaponent, Prop_Send, "m_iEntityLevel") == -115) //Checking if it's a Rebel's Curse
			{
				CreateTimer(0.1, Timer_DissolveRagdoll, any:GetEventInt(event, "userid"));
/*				PrintToChatAll("weapon is 197 with -115, active");
				new ragdoll = GetEntPropEnt(victim, Prop_Send, "m_hRagdoll");
				PrintToChatAll("trying to dissolve %d", ragdoll);
				if (ragdoll != -1)
				{
					DissolveRagdoll(ragdoll);
					PrintToChatAll("dissolving");
				}*/
			}
		}
	}
	return Plugin_Continue;
}
public Action:Timer_DissolveRagdoll(Handle:timer, any:userid)
{
	new victim = GetClientOfUserId(userid);
	new ragdoll;
	if (IsValidClient(victim)) ragdoll = GetEntPropEnt(victim, Prop_Send, "m_hRagdoll");
	else ragdoll = -1;
	if (ragdoll != -1)
	{
		DissolveRagdoll(ragdoll);
//		PrintToChatAll("dissolving");
	}
}
DissolveRagdoll(ragdoll)
{
	new dissolver = CreateEntityByName("env_entity_dissolver");

	if (dissolver == -1)
	{
		return;
	}

	DispatchKeyValue(dissolver, "dissolvetype", "0");
	DispatchKeyValue(dissolver, "magnitude", "200");
	DispatchKeyValue(dissolver, "target", "!activator");

	AcceptEntityInput(dissolver, "Dissolve", ragdoll);
	AcceptEntityInput(dissolver, "Kill");
//	PrintToChatAll("dissolving2");

	return;
}
public Action:Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!tf2items_giveweapon)
	{
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		new weapon = GetEventInt(event, "weaponid");
		if (weapon == TF_WEAPON_SNIPERRIFLE && (TF2_GetPlayerConditionFlags(client) & TF_CONDFLAG_JARATED))
		{
			isJarated[client] = true;
		}
	}
}
public Action:Event_PlayerJaratedFade(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
	if (!tf2items_giveweapon)
	{
		BfReadByte(bf); //client
		new victim = BfReadByte(bf);
		isJarated[victim] = false;
	}
}
public Action:Event_PlayerJarated(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
	if (!tf2items_giveweapon)
	{
		new client = BfReadByte(bf);
		new victim = BfReadByte(bf);
		new jar = GetPlayerWeaponSlot(client, 1);
		if (jar != -1 && GetEntProp(jar, Prop_Send, "m_iItemDefinitionIndex") == 58 && GetEntProp(jar, Prop_Send, "m_iEntityLevel") == -122)
		{
			if (!isJarated[victim]) CreateTimer(0.0, Timer_NoPiss, any:GetClientUserId(victim));	//TF2_RemoveCondition(victim, TFCond_Jarated);
			TF2_MakeBleed(victim, client, 10.0);
		}
		else isJarated[victim] = true;
	}
}
public Action:Timer_NoPiss(Handle:timer, any:userid)
{
	new victim = GetClientOfUserId(userid);
	if (IsValidClient(victim)) TF2_RemoveCondition(victim, TFCond_Jarated);
}
public Roundstart(Handle:event, const String:name[], bool:dontBroadcast)
{
	RoundStarted = true;
}
public Roundactive(Handle:event, const String:name[], bool:dontBroadcast)
{
	RoundStarted = false;
}

public cvhook_enabled(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	cvar_enabled = GetConVarBool(cvar);
	if (cvar_enabled)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			SetRandomization(i);
			if (IsClientInGame(i) && IsPlayerAlive(i)) TF2_RespawnPlayer(i);
		}
		PrintToChatAll("[TF2Items]Randomizer Enabled!");
	}
	else
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i)) TF2_RespawnPlayer(i);
		}
		PrintToChatAll("[TF2Items]Randomizer Disabled!");
	}
}

public cvhook_partial(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_partial = GetConVarInt(cvar); }
public cvhook_destroy(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_destroy = GetConVarBool(cvar); }
//public cvhook_fixammo(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_fixammo = GetConVarBool(cvar); }
public cvhook_fixpyro(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_fixpyro = GetConVarBool(cvar); }
public cvhook_fixspy (Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_fixspy  = GetConVarBool(cvar); }
public cvhook_fixuber(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_fixuber = GetConVarBool(cvar); }
public cvhook_betaweapons(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_betaweapons = GetConVarBool(cvar); }
public cvhook_customweapons(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_customweapons = GetConVarBool(cvar); }
public cvhook_fixreload(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_fixreload = GetConVarBool(cvar); }
public cvhook_goldenwrench(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_goldenwrench = GetConVarBool(cvar); }
public cvhook_fixfood(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_fixfood = GetConVarBool(cvar); }
public cvhook_gamedesc(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_gamedesc = GetConVarBool(cvar); }
public cvhook_manifix(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_manifix = GetConVarBool(cvar); }
public cvhook_spycloak(Handle:cvar, const String:oldVal[], const String:newVal[]) { cvar_spycloak = GetConVarBool(cvar); }

public SetRandomization(client)
{
	setclass[client] = TFClassType:mt_rand(1, 9); //GetRandomInt(1, 9);
	setwep[client][0] = -2;
}

public OnClientDisconnect(client) {
	if (heal_beams[client])
	{
		if (IsValidEntity(heal_beams[client])) AcceptEntityInput(heal_beams[client], "Kill");
		if (IsValidEntity(infotarget[client])) AcceptEntityInput(infotarget[client], "Kill");
		heal_beams[client] = 0;
		infotarget[client] = 0;
	}
	if (BonkCooldownTimer[client] != INVALID_HANDLE)
	{
		KillTimer(BonkCooldownTimer[client]);
		BonkCooldownTimer[client] = INVALID_HANDLE;
	}
	if (EatCooldownTimer[client] != INVALID_HANDLE)
	{
		KillTimer(EatCooldownTimer[client]);
		EatCooldownTimer[client] = INVALID_HANDLE;
	}
	if (DalokohsBuffTimer[client] != INVALID_HANDLE)
	{
		KillTimer(DalokohsBuffTimer[client]);
		DalokohsBuffTimer[client] = INVALID_HANDLE;
	}
	if (JarCooldownTimer[client] != INVALID_HANDLE)
	{
		KillTimer(JarCooldownTimer[client]);
		JarCooldownTimer[client] = INVALID_HANDLE;
	}
	if (BallCooldownTimer[client] != INVALID_HANDLE)
	{
		KillTimer(BallCooldownTimer[client]);
		BallCooldownTimer[client] = INVALID_HANDLE;
	}
}

public OnMapStart()
{
	g_bMapLoaded = true;
	for (new i = 1; i <= MaxClients; i++) if (IsClientInGame(i)) OnClientPutInServer(i);
	CreateTimer(0.1, timer_checkammos, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	PrecacheSound("player/invulnerable_off.wav", true);
	PrecacheSound("player/invulnerable_on.wav", true);
	PrecacheSound("weapons/weapon_crit_charged_on.wav", true);
	PrecacheSound("weapons/weapon_crit_charged_off.wav", true);
	PrecacheSound("vo/SandwichEat09.wav", true);
	PrecacheSound("player/recharged.wav", true);
	PrecacheSound("player/pl_scout_dodge_can_drink.wav", true);
	PrepareAllModels();
	new String:mapname[64];
	GetCurrentMap(mapname, sizeof(mapname));
	cvar_enabled = GetConVarBool(FindConVar("tf2items_rnd_enabled"));
	if (strncmp(mapname, "zf_", 3, false) == 0) ServerCommand("tf2items_rnd_enabled 0");
	if (strcmp(mapname, "cp_degrootkeep", false) == 0) medievalmode = true;
}

public OnMapEnd()
{
	g_bMapLoaded = false;
	medievalmode = false;
}

public Action:Command_EnableRnd(client, args)
{
	new String:mapname[64];
	GetCurrentMap(mapname, sizeof(mapname));
	if (strncmp(mapname, "zf_", 3, false) == 0) ReplyToCommand(client, "[TF2Items] NEVER Enable Randomizer on Zombie Fortress!");
	else if (cvar_enabled) ReplyToCommand(client, "[TF2Items]Randomizer is already enabled!");
	else if (!cvar_enabled)
	{
		ServerCommand("tf2items_rnd_enabled 1");
		ReplyToCommand(client, "[TF2Items] Enabled Randomizer");
	}
	return Plugin_Handled;
}
public Action:Command_DisableRnd(client, args)
{
	if (!cvar_enabled) ReplyToCommand(client, "[TF2Items]Randomizer is already disabled!");
	else if (cvar_enabled)
	{
		ServerCommand("tf2items_rnd_enabled 0");
		ReplyToCommand(client, "[TF2Items] Disabled Randomizer");
	}
	return Plugin_Handled;
}

public player_spawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Error-checking
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!client) return;
	if (!IsPlayerAlive(client)) return;
	
	pBonkCooldown[client] = false;
	pEatCooldown[client] = false;
	pLongEatCooldown[client] = false;
	pDalokohsBuff[client] = false;
	pJarCooldown[client] = false;
	pBallCooldown[client] = false;

	new TFClassType:cur = TF2_GetPlayerClass(client);
	getclass[client] = TF2_GetPlayerClass(client);
	if (cur == TFClass_Unknown) return;
	// Randomize if necessary.
	if (setwep[client][0] == -2)
	{
		if (cvar_enabled)
		{
			if (cvar_partial != 0 && mt_rand(1, 100) <= cvar_partial) setwep[client][0] = 0;	//GetRandomInt now mt_rand
			else setwep[client][0] = mt_rand(0, sizeof(weapon_primary) - 1);
			
			if (cvar_partial != 0 && mt_rand(1, 100) <= cvar_partial) setwep[client][1] = 0;
			else setwep[client][1] = mt_rand(0, sizeof(weapon_secondary) - 1);
			
			if (cvar_partial != 0 && mt_rand(1, 100) <= cvar_partial) setwep[client][2] = 0;
			else setwep[client][2] = mt_rand(0, sizeof(weapon_tertiary) - 1);

			if (cvar_spycloak && setclass[client] == TFClass_Spy)
			{
				/*if (cvar_partial != 0 && mt_rand(1, 100) <= cvar_partial) cloakwep[client] = 0;
				else*/
				cloakwep[client] = mt_rand(0, sizeof(weapon_cloakary) - 2);
				if (cloakwep[client] == 1 && mt_rand(0, 1) == 1) cloakwep[client] = 4;
			} else cloakwep[client] = -1;

			if (!cvar_betaweapons)
			{
				if (setwep[client][0] == 18) setwep[client][0] = 11;
				if (setwep[client][0] == 32) setwep[client][0] = 4;
				if (setwep[client][1] == 26) setwep[client][1] = 5;
				if (setwep[client][1] == 27) setwep[client][1] = 3;
			}
			if (!cvar_customweapons)
			{
				if (setwep[client][0] == 19) setwep[client][0] = 16;
				if (setwep[client][0] == 26) setwep[client][0] = 21;
				if (setwep[client][2] == 26) setwep[client][2] = 3;
				if (setwep[client][2] == 27) setwep[client][2] = 16;
				if (setwep[client][2] == 37) setwep[client][2] = 6;
				if (setwep[client][1] == 24) setwep[client][1] = 8;
			}
			if (!cvar_goldenwrench)
			{
				if (setwep[client][2] == 24) setwep[client][2] = 6;
				if (setwep[client][2] == 25) setwep[client][2] = 12;
//				if (setwep[client][2] == 37) setwep[client][2] = 6;
			}
			if (medievalmode)
			{
				if (setwep[client][0] != 0 && setwep[client][0] != 13 && setwep[client][0] != 29) setwep[client][0] = 0; 
				if (setwep[client][1] != 0 && setwep[client][1] != 6 && setwep[client][1] != 7 && setwep[client][1] != 11 && setwep[client][1] != 12 && setwep[client][1] != 13 && setwep[client][1] != 14 && setwep[client][1] != 15 && setwep[client][1] != 17 && setwep[client][1] != 20 && setwep[client][1] != 21 && setwep[client][1] != 22 && setwep[client][1] != 23 && setwep[client][1] != 24) setwep[client][1] = 0;
			}
			if (setwep[client][0] == 24 && setwep[client][1] == 16) setwep[client][0] = 5;
			if (cur != TFClass_Heavy && setwep[client][1] == 17) setwep[client][1] = 6;
		} else
		{
			setclass[client] = TFClassType:cur;
			setwep[client] = {0, 0, 0};
		}
	}
	// Check class and weapons.
	if (cur != TFClassType:setclass[client])
	{
		if (cvar_enabled && cvar_destroy && cur == TFClass_Engineer)
		{
			decl String:classname[32];
			new MaxEntities = GetMaxEntities();
			for (new i = MaxClients + 1; i <= MaxEntities; i++)
			{
				if (IsValidEdict(i))
				{
					GetEdictClassname(i, classname, sizeof(classname));
					if (StrEqual(classname, "obj_dispenser")
					|| StrEqual(classname, "obj_sentrygun")
					|| StrEqual(classname, "obj_teleporter"))
//					|| StrEqual(classname, "obj_teleporter_exit"))
					{
						if (GetEntPropEnt(i, Prop_Send, "m_hBuilder") == client)
						{
							SetVariantInt(9001);
							AcceptEntityInput(i, "RemoveHealth");
						}
					}
				}
			}
		}
		if (cvar_enabled)
		{
			TF2_SetPlayerClass(client, TFClassType:setclass[client], false, true);
			TF2_RespawnPlayer(client);
		}
	} else {
//		spy_status[client] = (cur == TFClass_Spy);
//		givePlayerWeapons(client);	//already in the locker weapon reset
//		ammo_count[client][0] = 1000;
//		ammo_count[client][1] = 1000;
	}
}

public lockerwepreset(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	CreateTimer(0.05, Timer_LockerWeaponReset, any:GetEventInt(event, "userid"));
	if (BonkCooldownTimer[client] != INVALID_HANDLE)
	{
		TriggerTimer(BonkCooldownTimer[client]);
		BonkCooldownTimer[client] = INVALID_HANDLE;
	}
	if (EatCooldownTimer[client] != INVALID_HANDLE)
	{
		TriggerTimer(EatCooldownTimer[client]);
		EatCooldownTimer[client] = INVALID_HANDLE;
	}
	if (JarCooldownTimer[client] != INVALID_HANDLE)
	{
		TriggerTimer(JarCooldownTimer[client]);
		JarCooldownTimer[client] = INVALID_HANDLE;
	}
	if (BallCooldownTimer[client] != INVALID_HANDLE)
	{
		TriggerTimer(BallCooldownTimer[client]);
		BallCooldownTimer[client] = INVALID_HANDLE;
	}
}

public Action:Timer_LockerWeaponReset(Handle:timer, any:userid)
{
	if(cvar_enabled)
	{
		new client = GetClientOfUserId(userid);
		if (IsValidClient(client))
		{
			givePlayerWeapons(client);
			CreateTimer(0.1, Timer_CheckHealth, any:userid);
			/*if (IsFakeClient(client))
			{
				if (pLockerTouchCount[client] < 4) pLockerTouchCount[client]++;
				else
				{
					ServerCommand("sm_reroll #%d", GetClientUserId(client));
					pLockerTouchCount[client] = 0;
				}
			}*/
		}
	}
}

public Action:timer_checkammos(Handle:timer)
{
	if(cvar_enabled && cvar_fixreload)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i))
			{
				new weapon = GetPlayerWeaponSlot(i, 0);
				if (IsValidEntity(weapon))
				{
					new newammo;
					new idx = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
					new TFClassType:class = TF2_GetPlayerClass(i);
					if ((newammo = GetSpeshulAmmo(i, 0)) < pOldAmmo[i] && ((idx == 36 && class != TFClass_Medic) || (class != TFClass_Spy && (idx == 224 || idx == 61 || idx == 161)) || (class != TFClass_Scout && (idx == 45 || idx == 220))))
					{
						pOldAmmo[i] = newammo;
						pReloadCooldown[i] = true;
						CreateTimer(1.0, Reload_Cooldown, i);
					}
					else pOldAmmo[i] = GetSpeshulAmmo(i, 0);
				}
			}
		}
	}
}

public Action:Timer_CheckHealth(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (IsValidClient(client))
	{
		if (setwep[client][0] == 24 || setwep[client][1] == 16) TF2_SetHealth(client, 350);
		else
		{
			if (GetClientHealth(client) > RoundToFloor(1.5 * TF2_GetMaxHealth(client))) TF2_SetHealth(client, RoundToFloor(1.5 * TF2_GetMaxHealth(client)));
			else if (GetClientHealth(client) < TF2_GetMaxHealth(client)) TF2_SetHealth(client, TF2_GetMaxHealth(client));
		}
	//	TF2_SetMaxHealth(client, TF2_GetMaxHealth(client));
	}
}

public Action:player_death(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new killtype = GetEventInt(event, "customkill");
	new deathflags = GetEventInt(event, "death_flags");
	if (deathflags & TF_DEATHFLAG_DEADRINGER) return Plugin_Continue;
	if (((attacker && attacker != client) || (killtype == TF_CUSTOM_DECAPITATION_BOSS)) && cvar_enabled) SetRandomization(client);
	if (BonkCooldownTimer[client] != INVALID_HANDLE)
	{
		KillTimer(BonkCooldownTimer[client]);
		BonkCooldownTimer[client] = INVALID_HANDLE;
	}
	if (EatCooldownTimer[client] != INVALID_HANDLE)
	{
		KillTimer(EatCooldownTimer[client]);
		EatCooldownTimer[client] = INVALID_HANDLE;
	}
	if (DalokohsBuffTimer[client] != INVALID_HANDLE)
	{
		KillTimer(DalokohsBuffTimer[client]);
		DalokohsBuffTimer[client] = INVALID_HANDLE;
	}
	if (JarCooldownTimer[client] != INVALID_HANDLE)
	{
		KillTimer(JarCooldownTimer[client]);
		JarCooldownTimer[client] = INVALID_HANDLE;
	}
	if (BallCooldownTimer[client] != INVALID_HANDLE)
	{
		KillTimer(BallCooldownTimer[client]);
		BallCooldownTimer[client] = INVALID_HANDLE;
	}
	return Plugin_Continue;
}

public round_win(Handle:event, const String:name[], bool:dontBroadcast) {
	for (new i = 1; i <= MaxClients; i++) if (IsClientInGame(i)) SetRandomization(i); //Gives back normal weapons if you touch a locker. Mk.
}

/*public Action:timer_checkplayers(Handle:timer) {
	// Simply cap ammo if Randomizer isn't enabled.
	if (!cvar_enabled)
	{
		decl max, slot, String:name[64];
		for (new i = 1; i <= MaxClients; i++)
		{
			slot = GetPlayerWeaponSlot(i, 0);
			if (slot != -1)
			{
				GetEdictClassname(slot, name, sizeof(name));
				if (GetTrieValue(max_ammo, name, max))
				{
					if (GetEntData(i, m_iAmmo + 4) > max)
						SetEntData(i, m_iAmmo + 4, max);
				}
			}
			slot = GetPlayerWeaponSlot(i, 1);
			if (slot != -1)
			{
				GetEdictClassname(GetPlayerWeaponSlot(i, 1), name, sizeof(name));
				if (GetTrieValue(max_ammo, name, max))
				{
					if (GetEntData(i, m_iAmmo + 8) > max)
						SetEntData(i, m_iAmmo + 8, max);
				}
			}
		}
		return;
	}

	// Step 1: KILL ALL THE RAZORBACKS!
	decl String:name[64];
	for (new i = MaxClients + 1; i < GetMaxEntities(); i++) {
		if (IsValidEdict(i)) {
			GetEdictClassname(i, name, sizeof(name));
			if (StrEqual(name, "tf_wearable") && GetEntProp(i, Prop_Send, "m_iEntityLevel") == 10) RemoveEdict(i); // MUAHAHAHA.
		}
	}
	// Step 2: Calm down, then check all the players.
	for (new i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && IsPlayerAlive(i) && setwep[i][0] > -2) {
			// Check for unassigned (default) weapons.
			new bad = false, pri = setwep[i][0], sec = setwep[i][1], mel = setwep[i][2];
			if (pri > 0) bad = !isWeaponEquipped(i, 0, weapon_primary[pri]);
			if (sec > 0 && !bad) bad = !isWeaponEquipped(i, 1, weapon_secondary[sec]);
			if (mel > 0 && !bad) bad = !isWeaponEquipped(i, 2, weapon_tertiary[mel]);
			if (bad) {
				givePlayerWeapons(i);
			} else {
				// Cap ammo.
				new max = -1, slot;
				slot = GetPlayerWeaponSlot(i, 0);
				if (slot != -1) {
					GetEdictClassname(slot, name, sizeof(name));
					if (GetTrieValue(max_ammo, name, max)) {
						if (GetEntData(i, m_iAmmo + 4) > max)
							SetEntData(i, m_iAmmo + 4, max);
					}
				}
				slot = GetPlayerWeaponSlot(i, 1);
				if (slot != -1) {
					GetEdictClassname(GetPlayerWeaponSlot(i, 1), name, sizeof(name));
					if (GetTrieValue(max_ammo, name, max)) {
						if (GetEntData(i, m_iAmmo + 8) > max)
							SetEntData(i, m_iAmmo + 8, max);
					}
				}
			}
		}
	}
}*/

public givePlayerWeapons(client)
{
	if (cvar_enabled)
	{
		new pri = setwep[client][0], sec = setwep[client][1], mel = setwep[client][2];
		if (pri < 0) pri = 0;
		new TFClassType:class = TF2_GetPlayerClass(client);
		if (class == TFClass_Spy && cloakwep[client] > -1) PrintHintText(client, "[TF2Items]Randomizer: %s, %s, %s, %s", weapon_primary_name[pri], weapon_secondary_name[sec], weapon_tertiary_name[mel], weapon_cloakary_name[cloakwep[client]]);
		else PrintHintText(client, "[TF2Items]Randomizer: %s, %s, %s", weapon_primary_name[pri], weapon_secondary_name[sec], weapon_tertiary_name[mel]);
		// primary
		if (pri > 0)
		{
			Command_Weapon(client, weapon_primary[pri]);
		}
		// secondary
		if (sec > 0)
		{
			RemovePlayerTarge(client);
			RemovePlayerBack(client);
			if (pDalokohsBuff[client]) Command_Weapon(client, 2159);
			else Command_Weapon(client, weapon_secondary[sec]);
		}
		// melee
		if (mel > 0)
		{
			Command_Weapon(client, weapon_tertiary[mel]);
		}
		if (class == TFClass_Spy)
		{
			if (cloakwep[client] > 0)
			{
				Command_Weapon(client, weapon_cloakary[cloakwep[client]]);
			}
			new slot = GetPlayerWeaponSlot(client, 2);
			new idx = GetEntProp(slot, Prop_Send, "m_iItemDefinitionIndex");
			if (idx == 225) TF2_RemoveWeaponSlot(client, 3);
			else if (idx != 225) Command_Weapon(client, 27);
		}
/*		if (class == TFClass_Sniper || class == TFClass_Medic || class == TFClass_Engineer)
		{
			CreateTimer(0.01, Timer_InvisGlitchFix, any:client);
			new wepon = GetPlayerWeaponSlot(client, 1);
			if (IsValidEntity(wepon) && GetEntProp(wepon, Prop_Send, "m_iItemDefinitionIndex") == 35) SetEntityRenderMode(wepon, RENDER_TRANSCOLOR);
		}
		if (class == TFClass_Medic || class == TFClass_DemoMan)
		{
			new wepon = GetPlayerWeaponSlot(client, 0);
			if (IsValidEntity(wepon) && GetEntProp(wepon, Prop_Send, "m_iItemDefinitionIndex") == 215) SetEntityRenderMode(wepon, RENDER_TRANSCOLOR);
		}*/
		pOldAmmo[client] = GetSpeshulAmmo(client, 0);
	}
}
/*public Action:Timer_InvisGlitchFix(Handle:timer, any:client)
{
	new TFClassType:class = TF2_GetPlayerClass(client);
	if (class == TFClass_Medic)
	{
		new wepon2 = GetPlayerWeaponSlot(client, 0);
		if (IsValidEntity(wepon2) && GetEntProp(wepon2, Prop_Send, "m_iItemDefinitionIndex") == 215) 
		{
			SetEntityRenderMode(wepon2, RENDER_TRANSCOLOR);
			SetEntityRenderColor(wepon2, 255, 255, 255, 75);
		}
	}
	if (class == TFClass_Sniper || class == TFClass_Engineer)
	{
		new wepon = GetPlayerWeaponSlot(client, 1);
		if (IsValidEntity(wepon) && GetEntProp(wepon, Prop_Send, "m_iItemDefinitionIndex") == 35)
		{
			SetEntityRenderMode(wepon, RENDER_TRANSCOLOR);
			SetEntityRenderColor(wepon, 255, 255, 255, 75);
		}
	}
}*/
//ARGBLARGDHAUGHAUGH - This stuff is somewhere else now.
/*isDefault(client, slot) {
	new wepslot = GetPlayerWeaponSlot(client, slot);
	if (wepslot == -1) return true; // gets rid of Razorback
	//if (GetEntProp(wepslot, Prop_Send, "m_iEntityLevel") > 1) return false;
	decl String:weapon[27];
	GetEdictClassname(wepslot, weapon, sizeof(weapon));
	if (slot == 0) for (new i = 0; i < sizeof(weapon_primary); i++) if (StrEqual(weapon, weapon_primary[i])) return true;
	if (slot == 1) for (new i = 0; i < sizeof(weapon_secondary); i++) if (StrEqual(weapon, weapon_secondary[i])) return true;
	if (slot == 2) for (new i = 0; i < sizeof(weapon_tertiary); i++) if (StrEqual(weapon, weapon_tertiary[i])) return true;
	return false;
}*/

/*isWeaponEquipped(client, slot, const String:name[])
{
	new edict;
	new defIdx;
	if((edict = GetPlayerWeaponSlot(client, slot)) != -1)
	{
		defIdx = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
		if (defIdx == StringToInt(name))
		{
			return true;
		}
	}
	return false;
}*/

//
//I wonder what that line^ is for...

RefillAmmo(client, Float:amount)
{
	decl String:name[64];
	new prilol = setwep[client][0];
	if (prilol == -2) prilol = 0;
	new seclol = setwep[client][1];
	new pri, sec, weaponAmmo, currentAmmo;
	if (cvar_enabled)
	{
		pri = weapon_primary[prilol];
		sec = weapon_secondary[seclol];
		if (pri != -1)
		{
			Format(name, 32, "%d_ammo", pri);
			if (GetTrieValue(g_hItemInfoTrie, name, weaponAmmo) && weaponAmmo != 0 && weaponAmmo != -1)
			{
				currentAmmo = GetSpeshulAmmo(client, 0);
				if (currentAmmo + RoundToFloor(amount * weaponAmmo) >= weaponAmmo) SetSpeshulAmmo(client, 0, weaponAmmo);
				else if (currentAmmo + RoundToFloor(amount * weaponAmmo) < weaponAmmo) SetSpeshulAmmo(client, 0, currentAmmo + RoundToFloor(amount * weaponAmmo));
			}
		}
		if (sec != -1 && sec != 42 && sec != 46 && sec != 58 && sec != 159 && sec != 163 && sec != 222)
		{
			Format(name, 32, "%d_ammo", sec);
			if (GetTrieValue(g_hItemInfoTrie, name, weaponAmmo) && weaponAmmo != 0 && weaponAmmo != -1)
			{
				currentAmmo = GetSpeshulAmmo(client, 1);
				if (currentAmmo + RoundToFloor(amount * weaponAmmo) >= weaponAmmo) SetSpeshulAmmo(client, 1, weaponAmmo);
				else if (currentAmmo + RoundToFloor(amount * weaponAmmo) < weaponAmmo) SetSpeshulAmmo(client, 1, currentAmmo + RoundToFloor(amount * weaponAmmo));
			}
		}
	}
}

public touch_ammo_small(const String:output[], caller, activator, Float:delay) {
	if (cvar_enabled && activator && IsValidClient(activator)) RefillAmmo(activator, 0.205);
}

public touch_ammo_medium(const String:output[], caller, activator, Float:delay) {
	if (cvar_enabled && activator && IsValidClient(activator)) RefillAmmo(activator, 0.5);
}

public touch_ammo_full(const String:output[], caller, activator, Float:delay) {
	if (cvar_enabled && activator && IsValidClient(activator))
	{
		RefillAmmo(activator, 1.0);
		if (setwep[activator][0] >= 0 && weapon_primary[setwep[activator][0]] == 2228 && GetEntProp(GetPlayerWeaponSlot(activator, 0), Prop_Send, "m_iClip1") == 0) SetSpeshulAmmo(activator, 0, 1);
	}
}


/*****************
 * OnGameFrame() *
 *****************/
public OnGameFrame() { //asherkin is in here somewhere
	if (!(cvar_fixpyro || cvar_fixuber)) return; //cvar_fixammo removed cvar_fixspy
//	decl ammo0old, ammo0new, ammo1old, ammo1new, max;
	decl cond, String:weapon[64]; //status, bool:deadring, Spy stuff?
	decl Float:speed; // Pyro
	decl slot, target, oldtarget; // Medigun
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			cond = TF2_GetPlayerConditionFlags(i);
//			deadring = bool:GetEntProp(i, Prop_Send, "m_bFeignDeathReady");
			// Fix ammo
/*			if (cvar_fixammo) {
				ammo0old = ammo_count[i][0];
				ammo0new = GetEntData(i, m_iAmmo + 4);
				ammo1old = ammo_count[i][1];
				ammo1new = GetEntData(i, m_iAmmo + 8);
				// fix primary
				if (ammo0new > ammo0old) {
					slot = GetPlayerWeaponSlot(i, 0);
					if (slot != -1) {
						GetEdictClassname(slot, weapon, sizeof(weapon));
						if (GetTrieValue(max_ammo, weapon, max)) {
							ammo0new = ammo0old + RoundToFloor(max * float(ammo0new - ammo0old) / 1000);
							if (ammo0new > max) ammo0new = max;
							SetEntData(i, m_iAmmo + 4, ammo0new);
						}
					}
				}
				// fix secondary
				if (ammo1new > ammo1old) {
					slot = GetPlayerWeaponSlot(i, 1);
					if (slot != -1) {
						GetEdictClassname(slot, weapon, sizeof(weapon));
						if (GetTrieValue(max_ammo, weapon, max)) {
							ammo1new = ammo1old + RoundToFloor(max * float(ammo1new - ammo1old) / 1000);
							if (ammo1new > max) ammo1new = max;
							SetEntData(i, m_iAmmo + 8, ammo1new);
						}
					}
				}
				ammo_count[i][0] = ammo0new;
				ammo_count[i][1] = ammo1new;
			}*/
			// Fix Spy disguise
			/*if (cvar_fixspy && cvar_enabled) {
				if ((status = spy_status[i])) {
					if (spy_status[i] == 1 && (cond & (TF_CONDFLAG_DISGUISING | TF_CONDFLAG_DISGUISED)) && (GetClientButtons(i) & IN_ATTACK)) { // Attacking?
						if (cvar_fixspy == 1)
						{
							GetClientWeapon(i, weapon, sizeof(weapon));
							if (StrEqual(weapon, "tf_weapon_flamethrower")
								|| StrEqual(weapon, "tf_weapon_grenadelauncher")
								|| StrEqual(weapon, "tf_weapon_pipebomblauncher")) TF2_RemovePlayerDisguise(i);
						} else
						{
							GetClientWeapon(i, weapon, sizeof(weapon));
							if (StrEqual(weapon, "tf_weapon_flamethrower")
								|| StrEqual(weapon, "tf_weapon_grenadelauncher")
								|| StrEqual(weapon, "tf_weapon_pipebomblauncher")
								|| StrEqual(weapon, "tf_weapon_wrench")
								|| StrEqual(weapon, "tf_weapon_fists")
								|| StrEqual(weapon, "tf_weapon_bat")
								|| StrEqual(weapon, "tf_weapon_bonesaw")
								|| StrEqual(weapon, "tf_weapon_sword")
								|| StrEqual(weapon, "tf_weapon_fireaxe")
								|| StrEqual(weapon, "tf_weapon_robot_arm")
								|| StrEqual(weapon, "tf_weapon_bat_wood")
								|| StrEqual(weapon, "tf_weapon_club")
								|| StrEqual(weapon, "tf_weapon_bat_fish")) TF2_RemovePlayerDisguise(i);
						}
					}
					if (spy_status[i] == 1 && (cond & (TF_CONDFLAG_DISGUISING | TF_CONDFLAG_DISGUISED)) && (GetClientButtons(i) & IN_ATTACK2) && cvar_fixspy == 2)
					{
						GetClientWeapon(i, weapon, sizeof(weapon));
						if (StrEqual(weapon, "tf_weapon_fists")) TF2_RemovePlayerDisguise(i);
					}
					if (status == 1) {
						if ((cond & (TF_CONDFLAG_CLOAKED | TF_CONDFLAG_DEADRINGERED)) || deadring) spy_status[i] = 2;
					} else if (status == 2 && !((cond & (TF_CONDFLAG_CLOAKED | TF_CONDFLAG_DEADRINGERED)) || deadring)) {
						CreateTimer(2.0, timer_uncloak, i);
						spy_status[i] = 3;
					}
				}
			}*/

			// Fix Pyro minigun
			if (cvar_fixpyro && !RoundStarted) // && cvar_enabled
			{
				if (TF2_GetPlayerClass(i) == TFClass_Pyro)
				{
					speed = GetEntPropFloat(i, Prop_Send, "m_flMaxspeed");
					if ((cond & (TF_CONDFLAG_SLOWED | TF_CONDFLAG_ZOOMED)) && speed != 80.0)
					{
						if (IsValidEntity(GetPlayerWeaponSlot(i, 0)) && GetEntProp(GetPlayerWeaponSlot(i, 0), Prop_Send, "m_iItemDefinitionIndex") == 312) SetEntPropFloat(i, Prop_Send, "m_flMaxspeed", 32.0);
						else SetEntPropFloat(i, Prop_Send, "m_flMaxspeed", 80.0);
					} else if (!(cond & (TF_CONDFLAG_SLOWED | TF_CONDFLAG_ZOOMED)) && speed && speed != 300.0)
					{
						SetEntPropFloat(i, Prop_Send, "m_flMaxspeed", 300.0);
					}
				}
			}
			// Fix Ubercharge
			if (cvar_fixuber) {
				new TFClassType:cur2 = TF2_GetPlayerClass(i);
				if (getclass[i] != TFClass_Medic) { // Not set to Medic.
					slot = GetPlayerWeaponSlot(i, 1);
					if (slot != -1) { // Have a secondary weapon.
						GetEdictClassname(slot, weapon, sizeof(weapon));
						if (StrEqual(weapon, "tf_weapon_medigun"))	//its a medigun
						{
							// 1: Fix medigun beam.
							target = GetEntPropEnt(slot, Prop_Send, "m_hHealingTarget");
							oldtarget = healtarget[i];
							if (target != oldtarget)
							{
								if (heal_beams[i])
								{
									if (IsValidEntity(heal_beams[i])) AcceptEntityInput(heal_beams[i], "Kill");
									if (IsValidEntity(infotarget[i])) AcceptEntityInput(infotarget[i], "Kill");
									heal_beams[i] = 0;
									infotarget[i] = 0;
								}
								healtarget[i] = target;
								if (target != -1)
								{
									new particle = CreateEntityByName("info_particle_system");
									if (IsValidEdict(particle)) {
										heal_beams[i] = particle;
										// weapon targetname (start)
										decl String:targetname[9];
										FormatEx(targetname, sizeof(targetname), "wpn%i", slot);
										DispatchKeyValue(slot, "targetname", targetname);
										// player targetname
										decl String:playertarget[9];
										FormatEx(playertarget, sizeof(playertarget), "player%i", target);
										DispatchKeyValue(target, "targetname", playertarget);
										// info_target on player (end)
										new info_target = CreateEntityByName("info_particle_system");
										decl String:controlpoint[9], Float:pos[3];
										FormatEx(controlpoint, sizeof(controlpoint), "target%i", target);
										DispatchKeyValue(info_target, "targetname", controlpoint);
										GetClientAbsOrigin(target, pos);
										pos[2] += 48.0;
										TeleportEntity(info_target, pos, NULL_VECTOR, NULL_VECTOR);
										SetVariantString(playertarget);
										AcceptEntityInput(info_target, "SetParent");
										infotarget[i] = info_target;
										// set particle stuff
										decl String:effect_name[19];
										FormatEx(effect_name, sizeof(effect_name), "medicgun_beam_%s", (GetClientTeam(i) == 2) ? "red" : "blue");
										DispatchKeyValue(particle, "parentname", targetname);
										DispatchKeyValue(particle, "effect_name", effect_name);
										DispatchKeyValue(particle, "cpoint1", controlpoint);
										DispatchSpawn(particle);
										SetVariantString(targetname);
										AcceptEntityInput(particle, "SetParent");
										SetVariantString("muzzle");
										AcceptEntityInput(particle, "SetParentAttachment");
										ActivateEntity(particle);
										AcceptEntityInput(particle, "Start");
									}
									/*if (GetEntProp(slot, Prop_Send, "m_iItemDefinitionIndex") == 35)
									{
										new particle = CreateEntityByName("info_particle_system");
										if (IsValidEdict(particle)) {
											heal_beams[i] = particle;
											// weapon targetname (start)
											decl String:targetname[9];
											FormatEx(targetname, sizeof(targetname), "wpn%i", slot);
											DispatchKeyValue(slot, "targetname", targetname);
											// player targetname
											decl String:playertarget[9];
											FormatEx(playertarget, sizeof(playertarget), "player%i", target);
											DispatchKeyValue(target, "targetname", playertarget);
											// info_target on player (end)
											new info_target = CreateEntityByName("info_particle_system");
											decl String:controlpoint[9], Float:pos[3];
											FormatEx(controlpoint, sizeof(controlpoint), "target%i", target);
											DispatchKeyValue(info_target, "targetname", controlpoint);
											GetClientAbsOrigin(target, pos);
											pos[2] += 48.0;
											TeleportEntity(info_target, pos, NULL_VECTOR, NULL_VECTOR);
											SetVariantString(playertarget);
											AcceptEntityInput(info_target, "SetParent");
											infotarget[i] = info_target;
											// set particle stuff
											decl String:effect_name[36];
											FormatEx(effect_name, sizeof(effect_name), "medicgun_beam_attrib_overheal_%s", (GetClientTeam(i) == 2) ? "red" : "blue");
											DispatchKeyValue(particle, "parentname", targetname);
											DispatchKeyValue(particle, "effect_name", effect_name);
											DispatchKeyValue(particle, "cpoint1", controlpoint);
											DispatchSpawn(particle);
											SetVariantString(targetname);
											AcceptEntityInput(particle, "SetParent");
											SetVariantString("muzzle");
											AcceptEntityInput(particle, "SetParentAttachment");
											ActivateEntity(particle);
											AcceptEntityInput(particle, "Start");
										}
									}*/
								}
							}
							// 2: Fix ubercharges.
							if (GetEntProp(slot, Prop_Send, "m_bChargeRelease")) //Charge Activated
							{
								GetClientWeapon(i, weapon, sizeof(weapon));
								new idx = GetEntProp(slot, Prop_Send, "m_iItemDefinitionIndex");
								if (idx == 29 && StrEqual(weapon, "tf_weapon_medigun"))
								{
									// uber effect
									if (getclass[i] != TFClass_Medic && cur2 != TFClass_Medic)
									{
										TF2_SetPlayerClass(i, TFClass_Medic, _, false);
										if (GetEntProp(slot, Prop_Send, "m_iEntityQuality") == 4) TF2_MegaHealCharge(i, true);
										else TF2_Ubercharge(i, true);
									}
								}
								else if (idx == 35 && StrEqual(weapon, "tf_weapon_medigun"))
								{
									// kritz effect
									if (getclass[i] != TFClass_Medic && cur2 != TFClass_Medic)
									{
										TF2_SetPlayerClass(i, TFClass_Medic, _, false);
										TF2_Kritzcharge(i, true);
									}
								}
								pUbered[i] = true;
								// fix charge level
								new Float:charge = GetEntPropFloat(slot, Prop_Send, "m_flChargeLevel") - 0.001875;
								if (charge <= 0.0) {
									SetEntProp(slot, Prop_Send, "m_bChargeRelease", false);
									charge = 0.0;
								}
								SetEntPropFloat(slot, Prop_Send, "m_flChargeLevel", charge);
							} else if (TF2_GetPlayerClass(i) == TFClass_Medic && getclass[i] != TFClass_Medic && pUbered[i])
							{
								TF2_SetPlayerClass(i, getclass[i], _, false);
								TF2_Ubercharge(i, false);
								TF2_Kritzcharge(i, false);
								TF2_MegaHealCharge(i, false);
							}
						} else if (TF2_GetPlayerClass(i) == TFClass_Medic && getclass[i] != TFClass_Medic && pUbered[i])
						{
							TF2_SetPlayerClass(i, cur2, _, false);
							TF2_Ubercharge(i, false);
							TF2_Kritzcharge(i, false);
							TF2_MegaHealCharge(i, false);
						}
					}
				}
			}
		}
	}
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	decl String:weapon2[64];
	GetClientWeapon(client, weapon2, sizeof(weapon2));
	new TFClassType:class = TF2_GetPlayerClass(client);
	if (buttons & IN_ATTACK)
	{
		if (cvar_fixfood) CheckFood(client);
		CheckJars(client);
	}
	if (buttons & IN_ATTACK2) CheckBall(client);
	if (cvar_fixreload && (buttons & IN_RELOAD))
	{
		if (StrEqual(weapon2, "tf_weapon_revolver") && class != TFClass_Spy && !pReloadCooldown[client])
		{
			pReloadCooldown[client] = true;
			CreateTimer(1.0, Reload_Cooldown, any:client);
		}
		if (StrEqual(weapon2, "tf_weapon_syringegun_medic") && class != TFClass_Soldier && class != TFClass_Engineer && class != TFClass_Medic && class != TFClass_DemoMan && class != TFClass_Scout && !pReloadCooldown[client])
		{
			pReloadCooldown[client] = true;
			CreateTimer(1.0, Reload_Cooldown, any:client);
		}
	}
	if (pReloadCooldown[client]) buttons &= ~IN_ATTACK;
/*	if (!tf2items_giveweapon)
	{
		if (buttons & IN_ATTACK2 && FindPlayerTarge(client) && pChargeTiming[client] == INVALID_HANDLE)
		{
			new TFClassType:class = TF2_GetPlayerClass(client);
			new weponslot2 = GetPlayerWeaponSlot(client, 1);
			new idxslot2;
			if (weponslot2 != -1) idxslot2 = GetEntProp(weponslot2, Prop_Send, "m_iItemDefinitionIndex");
			else idxslot2 = -1;
			if (class != TFClass_DemoMan || (idxslot2 != -1 && (idxslot2 == 265 || idxslot2 == 20 || idxslot2 == 207 || idxslot2 == 130)))
			{
	//			g_bIsPlayerTarged[client] = true;
				new weponslot3 = GetPlayerWeaponSlot(client, 2);
				new idxslot3;
				if (weponslot3 != -1) idxslot3 = GetEntProp(weponslot3, Prop_Send, "m_iItemDefinitionIndex");
				else idxslot3 = -1;
				new Float:chargetime;
				if (idxslot3 == 327) chargetime = 2.0;
				else chargetime = 1.5;
				TF2_AddCondition(client, TFCond_Charging, chargetime);
				pChargeTiming[client] = CreateTimer(chargetime, Timer_TargeReset, any:client);
			}
		}
		if ((buttons & IN_FORWARD) && (TF2_GetPlayerConditionFlags(client) & TF_CONDFLAG_CHARGING) && TF2_GetPlayerClass(client) != TFClass_DemoMan)
		{
			buttons &= ~IN_FORWARD;
		}
	}*/
}

public Action:Reload_Cooldown(Handle:timer, any:client)
{
	pReloadCooldown[client] = false;
}

public CheckFood(client)
{
	decl String:weapon3[64];
	GetClientWeapon(client, weapon3, sizeof(weapon3));
	if (GetPlayerWeaponSlot(client, 1) != -1 && (GetEntityFlags(client) & FL_ONGROUND))
	{
		new idx = GetEntProp(GetPlayerWeaponSlot(client, 1), Prop_Send, "m_iItemDefinitionIndex");
		if (StrEqual(weapon3, "tf_weapon_lunchbox") && TF2_GetPlayerClass(client) != TFClass_Heavy && !pEatCooldown[client] && !pLongEatCooldown[client])
		{
			TF2_StunPlayer(client, Float:3.8, Float:0.0, TF_STUNFLAG_BONKSTUCK|TF_STUNFLAG_NOSOUNDOREFFECT, 0);
			if (idx == 42) SetSandvich(client);
			if (idx == 159) SetDalokohs(client);
		}
		if(StrEqual(weapon3, "tf_weapon_lunchbox_drink") && TF2_GetPlayerClass(client) != TFClass_Scout && !pBonkCooldown[client])
		{
			pBonkCooldown[client] = true;
			BonkCooldownTimer[client] = CreateTimer(31.2, Bonk_Cooldown, GetClientUserId(client));
			TF2_StunPlayer(client, Float:1.2, Float:0.0, TF_STUNFLAG_BONKSTUCK|TF_STUNFLAG_NOSOUNDOREFFECT, 0);
			EmitSoundToAll("player/pl_scout_dodge_can_drink.wav", client);
			SetSpeshulAmmo(client, 1, 0);
			if (idx == 46) TF2_AddCondition(client, TFCond_Bonked, 7.2);
			if (idx == 163) TF2_AddCondition(client, TFCond_CritCola, 7.2);
		}
	}
}

public CheckJars(client)
{
	decl String:weapon3[64];
	GetClientWeapon(client, weapon3, sizeof(weapon3));
	if ((StrEqual(weapon3, "tf_weapon_jar") && TF2_GetPlayerClass(client) != TFClass_Sniper) || (StrEqual(weapon3, "tf_weapon_jar_milk") && TF2_GetPlayerClass(client) != TFClass_Scout)  && !pJarCooldown[client])
	{
		pJarCooldown[client] = true;
		JarCooldownTimer[client] = CreateTimer(20.0, Jar_Cooldown, GetClientUserId(client));
	}
}

public CheckBall(client)
{
	decl String:weapon3[64];
	GetClientWeapon(client, weapon3, sizeof(weapon3));
	if (StrEqual(weapon3, "tf_weapon_bat_wood") && TF2_GetPlayerClass(client) != TFClass_Scout && !pBallCooldown[client])
	{
		pBallCooldown[client] = true;
		BallCooldownTimer[client] = CreateTimer(15.0, Ball_Cooldown, GetClientUserId(client));
	}
	if (GetPlayerWeaponSlot(client, 1) != -1)
	{
		new idx = GetEntProp(GetPlayerWeaponSlot(client, 1), Prop_Send, "m_iItemDefinitionIndex");
		if (StrEqual(weapon3, "tf_weapon_lunchbox") && idx == 42 && TF2_GetPlayerClass(client) != TFClass_Heavy && !pEatCooldown[client] && !pLongEatCooldown[client])
		{
			pEatCooldown[client] = true;
			pLongEatCooldown[client] = true;
			EatCooldownTimer[client] = CreateTimer(25.7, Eat_CooldownTime, GetClientUserId(client));
		}
	}
}

SetSandvich(client)
{
	CreateTimer(1.0, SetSandvichTimer, any:GetClientUserId(client), TIMER_REPEAT);
	pEatCooldown[client] = true;
	if (GetClientHealth(client) < TF2_GetMaxHealth(client))
	{
		EatCooldownTimer[client] = CreateTimer(30.1, Eat_CooldownTime, any:GetClientUserId(client));
		pLongEatCooldown[client] = true;
		if (!(IsValidEntity(GetPlayerWeaponSlot(client, 2)) && GetEntProp(GetPlayerWeaponSlot(client, 2), Prop_Send, "m_iItemDefinitionIndex") == 44)) SetSpeshulAmmo(client, 1, 0);
	}
	else EatCooldownTimer[client] = CreateTimer(4.3, Eat_CooldownTime, any:GetClientUserId(client));
}

public Action:SetSandvichTimer(Handle:timer, any:userid)
{
	static NumPrinted[MAXPLAYERS + 1] = 0;
	new client = GetClientOfUserId(userid);
	if (!IsValidClient(client)) 
	{
		NumPrinted[client] = 0;
		return Plugin_Stop;
	}
	if (NumPrinted[client] == 0) EmitSoundToAll("vo/SandwichEat09.wav", client);
	if (NumPrinted[client]++ >= 4)
	{
		NumPrinted[client] = 0;
		return Plugin_Stop;
	}
	if (GetClientHealth(client) < TF2_GetMaxHealth(client) && (GetClientHealth(client) + 75) > TF2_GetMaxHealth(client))
	{
		TF2_SetHealth(client, TF2_GetMaxHealth(client));
//		NumPrinted[client] = 0;
		return Plugin_Continue; //Stop
	}
	else if (GetClientHealth(client) < TF2_GetMaxHealth(client) && (GetClientHealth(client) + 75) < TF2_GetMaxHealth(client))
	{
		TF2_SetHealth(client, (GetClientHealth(client) + 75));
		return Plugin_Continue;
	}
	return Plugin_Continue;
}

SetDalokohs(client)
{
	CreateTimer(1.0, SetDalokohsTimer, any:GetClientUserId(client), TIMER_REPEAT);
	pEatCooldown[client] = true;
	if (!pDalokohsBuff[client])
	{	
		Command_Weapon(client, 2159);
		pDalokohsBuff[client] = true;
		DalokohsBuffTimer[client] = CreateTimer(30.1, DalokohsBuffTime, any:GetClientUserId(client));
	}
/*	if (GetClientHealth(client) < TF2_GetMaxHealth(client))
	{
		EatCooldownTimer[client] = CreateTimer(30.1, Eat_CooldownTime, any:GetClientUserId(client));
		pLongEatCooldown[client] = true;
		if (!(IsValidEntity(GetPlayerWeaponSlot(client, 2)) && GetEntProp(GetPlayerWeaponSlot(client, 2), Prop_Send, "m_iItemDefinitionIndex") == 44)) SetSpeshulAmmo(client, 1, 0);
	}
	else*/ EatCooldownTimer[client] = CreateTimer(4.3, Eat_CooldownTime, any:GetClientUserId(client));
}

public Action:SetDalokohsTimer(Handle:timer, any:userid)
{
	static NumPrinted[MAXPLAYERS + 1] = 0;
	new client = GetClientOfUserId(userid);
	if (!IsValidClient(client)) 
	{
		NumPrinted[client] = 0;
		return Plugin_Stop;
	}
	if (NumPrinted[client] == 0) EmitSoundToAll("vo/SandwichEat09.wav", client);
	if (NumPrinted[client]++ >= 4)
	{
		NumPrinted[client] = 0;
		return Plugin_Stop;
	}
	if (GetClientHealth(client) < TF2_GetMaxHealth(client) && (GetClientHealth(client) + 15 > TF2_GetMaxHealth(client)))
	{
		TF2_SetHealth(client, TF2_GetMaxHealth(client));
//		NumPrinted[client] = 0;
		return Plugin_Continue; //Stop
	}
	else if (GetClientHealth(client) < TF2_GetMaxHealth(client) && (GetClientHealth(client) + 15) < TF2_GetMaxHealth(client))
	{
		TF2_SetHealth(client, (GetClientHealth(client) + 15));
		return Plugin_Continue;
	}
	return Plugin_Continue;
}

public Action:Eat_CooldownTime(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(pEatCooldown[client])
	{
		pEatCooldown[client] = false;
		if (pLongEatCooldown[client])
		{
			if (IsValidClient(client))
			{
				PrintHintText(client, "[TF2Items]Randomizer: Your Food has Recharged");
				EmitSoundToClient(client, "player/recharged.wav");
			}
			pLongEatCooldown[client] = false;
		}
		if (GetSpeshulAmmo(client, 1) < 1) SetSpeshulAmmo(client, 1, 1);
	}
	EatCooldownTimer[client] = INVALID_HANDLE;
}

public Action:DalokohsBuffTime(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (pDalokohsBuff[client])
	{
		pDalokohsBuff[client] = false;
		if (IsValidClient(client)) Command_Weapon(client, 159);
	}
	if (GetSpeshulAmmo(client, 1) < 1) SetSpeshulAmmo(client, 1, 1);
	DalokohsBuffTimer[client] = INVALID_HANDLE;
}

public Action:Bonk_Cooldown(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(pBonkCooldown[client])
	{
		pBonkCooldown[client] = false;
		if (IsValidClient(client))
		{
			PrintHintText(client, "[TF2Items]Randomizer: Your Drink has Recharged");
			EmitSoundToClient(client, "player/recharged.wav");
		}
	}
	if (GetSpeshulAmmo(client, 1) < 1) SetSpeshulAmmo(client, 1, 1);
	BonkCooldownTimer[client] = INVALID_HANDLE;
}

public Action:Ball_Cooldown(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(pBallCooldown[client])
	{
		pBallCooldown[client] = false;
		if (IsValidClient(client))
		{
			PrintHintText(client, "[TF2Items]Randomizer: Your Ball has Recharged");
			EmitSoundToClient(client, "player/recharged.wav");
		}
	}
	if (GetSpeshulAmmo(client, 2) < 1) SetSpeshulAmmo(client, 2, 1);
	BallCooldownTimer[client] = INVALID_HANDLE;
}

public Action:Jar_Cooldown(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(pJarCooldown[client])
	{
		pJarCooldown[client] = false;
		if (IsValidClient(client))
		{
			PrintHintText(client, "[TF2Items]Randomizer: Your Jar has Recharged");
			EmitSoundToClient(client, "player/recharged.wav");
		}
	}
	if (GetSpeshulAmmo(client, 1) < 1) SetSpeshulAmmo(client, 1, 1);
	JarCooldownTimer[client] = INVALID_HANDLE;
}

/*public Action:timer_uncloak(Handle:event, any:client) {
	spy_status[client] = 1;
}*/

TF2_Ubercharge(client, enable) {
	if (enable) {
//		EmitSoundToClient(client, "player/invulnerable_on.wav");
		TF2_AddCondition(client, TFCond_Ubercharged, Float:999999999);
	} else {
//		EmitSoundToClient(client, "player/invulnerable_off.wav");
		TF2_RemoveCondition(client, TFCond_Ubercharged);
	}
}

TF2_Kritzcharge(client, enable) {
	if (enable) {
//		EmitSoundToClient(client, "weapons/weapon_crit_charged_on.wav");
		TF2_AddCondition(client, TFCond_Kritzkrieged, Float:999999999);
	} else {
//		EmitSoundToClient(client, "weapons/weapon_crit_charged_off.wav");
		TF2_RemoveCondition(client, TFCond_Kritzkrieged);
	}
}
TF2_MegaHealCharge(client, enable) {
	if (enable) {
//		EmitSoundToClient(client, "weapons/weapon_crit_charged_on.wav");
		TF2_AddCondition(client, TFCond_MegaHeal, Float:999999999);
	} else {
//		EmitSoundToClient(client, "weapons/weapon_crit_charged_off.wav");
		TF2_RemoveCondition(client, TFCond_MegaHeal);
	}
}

stock SetSpeshulAmmo(client, wepslot, newAmmo)
{
	if (IsValidClient(client) && IsPlayerAlive(client))
	{
		new weapon = GetPlayerWeaponSlot(client, wepslot);
		if (IsValidEntity(weapon))
		{   
			new iOffset = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType", 1)*4;
			new iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
			SetEntData(client, iAmmoTable+iOffset, newAmmo, 4, true);
		}
	}
}

stock GetSpeshulAmmo(client, wepslot)
{
	if (!IsValidClient(client)) return 0;
	new weapon = GetPlayerWeaponSlot(client, wepslot);
	if (IsValidEntity(weapon))
	{   
		new iOffset = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType", 1)*4;
		new iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
		return GetEntData(client, iAmmoTable+iOffset);
	}
	return 0;
}
//http://pastebin.com/U6vwXX57
/********************
 * Mersenne Twister *
 ********************
new mt_array[624];
new mt_index;

stock mt_srand(seed) {
	mt_array[0] = seed;
	for (new i = 1; i < 624; i++) mt_array[i] = ((mt_array[i - 1] ^ (mt_array[i - 1] >> 30)) * 0x6C078965 + 1) & 0xFFFFFFFF;
}*/

stock mt_rand(min, max) {
	return RoundToNearest(GetURandomFloat() * (max - min) + min);
}

/*stock _mt_getNext() {
	if (!mt_index) _mt_generate();
	new y = mt_array[mt_index];
	y ^= (y >> 11);
	y ^= (y << 7) & 0x9D2C5680;
	y ^= (y << 15) & 0xEFC60000;
	y ^= (y >> 18);
	mt_index = (mt_index + 1) % 624;
	return y;
}

stock _mt_generate() {
	for (new i = 0; i < 623; i++) {
		new y = (mt_array[i] & 0x80000000) + ((mt_array[i + 1] % 624) & 0x7FFFFFFF);
		mt_array[i] = mt_array[(i + 397) % 624] ^ (y >> 1);
		if (y % 2) mt_array[i] ^= 0x9908B0DF;
	}
}*/

Handle:PrepareItemHandle(weaponLookupIndex)
{
	new String:formatBuffer[32];	
	new String:weaponClassname[64];
	new weaponIndex;
	new weaponSlot;
	new weaponQuality;
	new weaponLevel;
	new String:weaponAttribs[256];
	
	Format(formatBuffer, 32, "%d_%s", weaponLookupIndex, "classname");
	GetTrieString(g_hItemInfoTrie, formatBuffer, weaponClassname, 64);
	
	Format(formatBuffer, 32, "%d_%s", weaponLookupIndex, "index");
	GetTrieValue(g_hItemInfoTrie, formatBuffer, weaponIndex);
	
	Format(formatBuffer, 32, "%d_%s", weaponLookupIndex, "slot");
	GetTrieValue(g_hItemInfoTrie, formatBuffer, weaponSlot);
	
	Format(formatBuffer, 32, "%d_%s", weaponLookupIndex, "quality");
	GetTrieValue(g_hItemInfoTrie, formatBuffer, weaponQuality);
	
	Format(formatBuffer, 32, "%d_%s", weaponLookupIndex, "level");
	GetTrieValue(g_hItemInfoTrie, formatBuffer, weaponLevel);
	
	Format(formatBuffer, 32, "%d_%s", weaponLookupIndex, "attribs");
	GetTrieString(g_hItemInfoTrie, formatBuffer, weaponAttribs, 256);
	
	new String:weaponAttribsArray[32][32];
	new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
	
	new Handle:hWeapon = TF2Items_CreateItem(OVERRIDE_CLASSNAME | OVERRIDE_ITEM_DEF | OVERRIDE_ITEM_LEVEL | OVERRIDE_ITEM_QUALITY | OVERRIDE_ATTRIBUTES);

	TF2Items_SetClassname(hWeapon, weaponClassname);
	TF2Items_SetItemIndex(hWeapon, weaponIndex);
	TF2Items_SetLevel(hWeapon, weaponLevel);
	TF2Items_SetQuality(hWeapon, weaponQuality);

	if (attribCount > 0) {
		TF2Items_SetNumAttributes(hWeapon, attribCount/2);
		new i2 = 0;
		for (new i = 0; i < attribCount; i+=2) {
			TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
			i2++;
		}
	} else {
		TF2Items_SetNumAttributes(hWeapon, 0);
	}
	
	return hWeapon;
}

CreateItemInfoTrie()
{
	g_hItemInfoTrie = CreateTrie();

//bat
	SetTrieString(g_hItemInfoTrie, "0_classname", "tf_weapon_bat");
	SetTrieValue(g_hItemInfoTrie, "0_index", 0);
	SetTrieValue(g_hItemInfoTrie, "0_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "0_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "0_level", 1);
	SetTrieString(g_hItemInfoTrie, "0_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "0_ammo", -1);

//bottle
	SetTrieString(g_hItemInfoTrie, "1_classname", "tf_weapon_bottle");
	SetTrieValue(g_hItemInfoTrie, "1_index", 1);
	SetTrieValue(g_hItemInfoTrie, "1_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "1_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "1_level", 1);
	SetTrieString(g_hItemInfoTrie, "1_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "1_ammo", -1);

//fire axe
	SetTrieString(g_hItemInfoTrie, "2_classname", "tf_weapon_fireaxe");
	SetTrieValue(g_hItemInfoTrie, "2_index", 2);
	SetTrieValue(g_hItemInfoTrie, "2_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "2_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "2_level", 1);
	SetTrieString(g_hItemInfoTrie, "2_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "2_ammo", -1);

//kukri
	SetTrieString(g_hItemInfoTrie, "3_classname", "tf_weapon_club");
	SetTrieValue(g_hItemInfoTrie, "3_index", 3);
	SetTrieValue(g_hItemInfoTrie, "3_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "3_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "3_level", 1);
	SetTrieString(g_hItemInfoTrie, "3_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "3_ammo", -1);

//knife
	SetTrieString(g_hItemInfoTrie, "4_classname", "tf_weapon_knife");
	SetTrieValue(g_hItemInfoTrie, "4_index", 4);
	SetTrieValue(g_hItemInfoTrie, "4_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "4_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "4_level", 1);
	SetTrieString(g_hItemInfoTrie, "4_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "4_ammo", -1);

//fists
	SetTrieString(g_hItemInfoTrie, "5_classname", "tf_weapon_fists");
	SetTrieValue(g_hItemInfoTrie, "5_index", 5);
	SetTrieValue(g_hItemInfoTrie, "5_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "5_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "5_level", 1);
	SetTrieString(g_hItemInfoTrie, "5_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "5_ammo", -1);

//shovel
	SetTrieString(g_hItemInfoTrie, "6_classname", "tf_weapon_shovel");
	SetTrieValue(g_hItemInfoTrie, "6_index", 6);
	SetTrieValue(g_hItemInfoTrie, "6_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "6_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "6_level", 1);
	SetTrieString(g_hItemInfoTrie, "6_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "6_ammo", -1);

//wrench
	SetTrieString(g_hItemInfoTrie, "7_classname", "tf_weapon_wrench");
	SetTrieValue(g_hItemInfoTrie, "7_index", 7);
	SetTrieValue(g_hItemInfoTrie, "7_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "7_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "7_level", 1);
	SetTrieString(g_hItemInfoTrie, "7_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "7_ammo", -1);

//bonesaw
	SetTrieString(g_hItemInfoTrie, "8_classname", "tf_weapon_bonesaw");
	SetTrieValue(g_hItemInfoTrie, "8_index", 8);
	SetTrieValue(g_hItemInfoTrie, "8_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "8_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "8_level", 1);
	SetTrieString(g_hItemInfoTrie, "8_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "8_ammo", -1);

//shotgun engineer
	SetTrieString(g_hItemInfoTrie, "9_classname", "tf_weapon_shotgun_primary");
	SetTrieValue(g_hItemInfoTrie, "9_index", 9);
	SetTrieValue(g_hItemInfoTrie, "9_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "9_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "9_level", 1);
	SetTrieString(g_hItemInfoTrie, "9_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "9_ammo", 32);

//shotgun soldier
	SetTrieString(g_hItemInfoTrie, "10_classname", "tf_weapon_shotgun_soldier");
	SetTrieValue(g_hItemInfoTrie, "10_index", 10);
	SetTrieValue(g_hItemInfoTrie, "10_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "10_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "10_level", 1);
	SetTrieString(g_hItemInfoTrie, "10_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "10_ammo", 32);

//shotgun heavy
	SetTrieString(g_hItemInfoTrie, "11_classname", "tf_weapon_shotgun_hwg");
	SetTrieValue(g_hItemInfoTrie, "11_index", 11);
	SetTrieValue(g_hItemInfoTrie, "11_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "11_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "11_level", 1);
	SetTrieString(g_hItemInfoTrie, "11_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "11_ammo", 32);

//shotgun pyro
	SetTrieString(g_hItemInfoTrie, "12_classname", "tf_weapon_shotgun_pyro");
	SetTrieValue(g_hItemInfoTrie, "12_index", 12);
	SetTrieValue(g_hItemInfoTrie, "12_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "12_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "12_level", 1);
	SetTrieString(g_hItemInfoTrie, "12_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "12_ammo", 32);

//scattergun
	SetTrieString(g_hItemInfoTrie, "13_classname", "tf_weapon_scattergun");
	SetTrieValue(g_hItemInfoTrie, "13_index", 13);
	SetTrieValue(g_hItemInfoTrie, "13_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "13_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "13_level", 1);
	SetTrieString(g_hItemInfoTrie, "13_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "13_ammo", 32);

//sniper rifle
	SetTrieString(g_hItemInfoTrie, "14_classname", "tf_weapon_sniperrifle");
	SetTrieValue(g_hItemInfoTrie, "14_index", 14);
	SetTrieValue(g_hItemInfoTrie, "14_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "14_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "14_level", 1);
	SetTrieString(g_hItemInfoTrie, "14_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "14_ammo", 25);

//minigun
	SetTrieString(g_hItemInfoTrie, "15_classname", "tf_weapon_minigun");
	SetTrieValue(g_hItemInfoTrie, "15_index", 15);
	SetTrieValue(g_hItemInfoTrie, "15_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "15_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "15_level", 1);
	SetTrieString(g_hItemInfoTrie, "15_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "15_ammo", 200);

//smg
	SetTrieString(g_hItemInfoTrie, "16_classname", "tf_weapon_smg");
	SetTrieValue(g_hItemInfoTrie, "16_index", 16);
	SetTrieValue(g_hItemInfoTrie, "16_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "16_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "16_level", 1);
	SetTrieString(g_hItemInfoTrie, "16_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "16_ammo", 75);

//syringe gun
	SetTrieString(g_hItemInfoTrie, "17_classname", "tf_weapon_syringegun_medic");
	SetTrieValue(g_hItemInfoTrie, "17_index", 17);
	SetTrieValue(g_hItemInfoTrie, "17_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "17_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "17_level", 1);
	SetTrieString(g_hItemInfoTrie, "17_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "17_ammo", 150);

//rocket launcher
	SetTrieString(g_hItemInfoTrie, "18_classname", "tf_weapon_rocketlauncher");
	SetTrieValue(g_hItemInfoTrie, "18_index", 18);
	SetTrieValue(g_hItemInfoTrie, "18_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "18_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "18_level", 1);
	SetTrieString(g_hItemInfoTrie, "18_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "18_ammo", 20);

//grenade launcher
	SetTrieString(g_hItemInfoTrie, "19_classname", "tf_weapon_grenadelauncher");
	SetTrieValue(g_hItemInfoTrie, "19_index", 19);
	SetTrieValue(g_hItemInfoTrie, "19_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "19_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "19_level", 1);
	SetTrieString(g_hItemInfoTrie, "19_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "19_ammo", 16);

//sticky launcher
	SetTrieString(g_hItemInfoTrie, "20_classname", "tf_weapon_pipebomblauncher");
	SetTrieValue(g_hItemInfoTrie, "20_index", 20);
	SetTrieValue(g_hItemInfoTrie, "20_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "20_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "20_level", 1);
	SetTrieString(g_hItemInfoTrie, "20_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "20_ammo", 24);

//flamethrower
	SetTrieString(g_hItemInfoTrie, "21_classname", "tf_weapon_flamethrower");
	SetTrieValue(g_hItemInfoTrie, "21_index", 21);
	SetTrieValue(g_hItemInfoTrie, "21_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "21_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "21_level", 1);
	SetTrieString(g_hItemInfoTrie, "21_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "21_ammo", 200);

//pistol engineer
	SetTrieString(g_hItemInfoTrie, "22_classname", "tf_weapon_pistol");
	SetTrieValue(g_hItemInfoTrie, "22_index", 22);
	SetTrieValue(g_hItemInfoTrie, "22_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "22_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "22_level", 1);
	SetTrieString(g_hItemInfoTrie, "22_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "22_ammo", 200);

//pistol scout
	SetTrieString(g_hItemInfoTrie, "23_classname", "tf_weapon_pistol_scout");
	SetTrieValue(g_hItemInfoTrie, "23_index", 23);
	SetTrieValue(g_hItemInfoTrie, "23_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "23_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "23_level", 1);
	SetTrieString(g_hItemInfoTrie, "23_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "23_ammo", 36);

//revolver
	SetTrieString(g_hItemInfoTrie, "24_classname", "tf_weapon_revolver");
	SetTrieValue(g_hItemInfoTrie, "24_index", 24);
	SetTrieValue(g_hItemInfoTrie, "24_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "24_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "24_level", 1);
	SetTrieString(g_hItemInfoTrie, "24_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "24_ammo", 24);

//build pda engineer
	SetTrieString(g_hItemInfoTrie, "25_classname", "tf_weapon_pda_engineer_build");
	SetTrieValue(g_hItemInfoTrie, "25_index", 25);
	SetTrieValue(g_hItemInfoTrie, "25_slot", 3);
	SetTrieValue(g_hItemInfoTrie, "25_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "25_level", 1);
	SetTrieString(g_hItemInfoTrie, "25_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "25_ammo", -1);

//destroy pda engineer
	SetTrieString(g_hItemInfoTrie, "26_classname", "tf_weapon_pda_engineer_destroy");
	SetTrieValue(g_hItemInfoTrie, "26_index", 26);
	SetTrieValue(g_hItemInfoTrie, "26_slot", 4);
	SetTrieValue(g_hItemInfoTrie, "26_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "26_level", 1);
	SetTrieString(g_hItemInfoTrie, "26_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "26_ammo", -1);

//disguise kit spy
	SetTrieString(g_hItemInfoTrie, "27_classname", "tf_weapon_pda_spy");
	SetTrieValue(g_hItemInfoTrie, "27_index", 27);
	SetTrieValue(g_hItemInfoTrie, "27_slot", 3);
	SetTrieValue(g_hItemInfoTrie, "27_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "27_level", 1);
	SetTrieString(g_hItemInfoTrie, "27_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "27_ammo", -1);

//builder
	SetTrieString(g_hItemInfoTrie, "28_classname", "tf_weapon_builder");
	SetTrieValue(g_hItemInfoTrie, "28_index", 28);
	SetTrieValue(g_hItemInfoTrie, "28_slot", 5);
	SetTrieValue(g_hItemInfoTrie, "28_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "28_level", 1);
	SetTrieString(g_hItemInfoTrie, "28_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "28_ammo", -1);

//medigun
	SetTrieString(g_hItemInfoTrie, "29_classname", "tf_weapon_medigun");
	SetTrieValue(g_hItemInfoTrie, "29_index", 29);
	SetTrieValue(g_hItemInfoTrie, "29_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "29_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "29_level", 1);
	SetTrieString(g_hItemInfoTrie, "29_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "29_ammo", -1);

//invis watch
	SetTrieString(g_hItemInfoTrie, "30_classname", "tf_weapon_invis");
	SetTrieValue(g_hItemInfoTrie, "30_index", 30);
	SetTrieValue(g_hItemInfoTrie, "30_slot", 4);
	SetTrieValue(g_hItemInfoTrie, "30_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "30_level", 1);
	SetTrieString(g_hItemInfoTrie, "30_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "30_ammo", -1);

/*flaregun engineerpistol
	SetTrieString(g_hItemInfoTrie, "31_classname", "tf_weapon_flaregun");
	SetTrieValue(g_hItemInfoTrie, "31_index", 31);
	SetTrieValue(g_hItemInfoTrie, "31_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "31_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "31_level", 1);
	SetTrieString(g_hItemInfoTrie, "31_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "31_ammo", 16);*/

//kritzkrieg
	SetTrieString(g_hItemInfoTrie, "35_classname", "tf_weapon_medigun");
	SetTrieValue(g_hItemInfoTrie, "35_index", 35);
	SetTrieValue(g_hItemInfoTrie, "35_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "35_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "35_level", 8);
	SetTrieString(g_hItemInfoTrie, "35_attribs", "18 ; 1.0 ; 10 ; 1.25");
	SetTrieValue(g_hItemInfoTrie, "35_ammo", -1);

//blutsauger
	SetTrieString(g_hItemInfoTrie, "36_classname", "tf_weapon_syringegun_medic");
	SetTrieValue(g_hItemInfoTrie, "36_index", 36);
	SetTrieValue(g_hItemInfoTrie, "36_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "36_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "36_level", 5);
	SetTrieString(g_hItemInfoTrie, "36_attribs", "16 ; 3.0 ; 129 ; -2.0");
	SetTrieValue(g_hItemInfoTrie, "36_ammo", 150);

//ubersaw
	SetTrieString(g_hItemInfoTrie, "37_classname", "tf_weapon_bonesaw");
	SetTrieValue(g_hItemInfoTrie, "37_index", 37);
	SetTrieValue(g_hItemInfoTrie, "37_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "37_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "37_level", 10);
	SetTrieString(g_hItemInfoTrie, "37_attribs", "17 ; 0.25 ; 5 ; 1.2 ; 144 ; 1");
	SetTrieValue(g_hItemInfoTrie, "37_ammo", -1);

//axetinguisher
	SetTrieString(g_hItemInfoTrie, "38_classname", "tf_weapon_fireaxe");
	SetTrieValue(g_hItemInfoTrie, "38_index", 38);
	SetTrieValue(g_hItemInfoTrie, "38_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "38_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "38_level", 10);
	SetTrieString(g_hItemInfoTrie, "38_attribs", "20 ; 1.0 ; 21 ; 0.5 ; 22 ; 1.0");
	SetTrieValue(g_hItemInfoTrie, "38_ammo", -1);

//flaregun pyro
	SetTrieString(g_hItemInfoTrie, "39_classname", "tf_weapon_flaregun");
	SetTrieValue(g_hItemInfoTrie, "39_index", 39);
	SetTrieValue(g_hItemInfoTrie, "39_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "39_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "39_level", 10);
	SetTrieString(g_hItemInfoTrie, "39_attribs", "25 ; 0.5");
	SetTrieValue(g_hItemInfoTrie, "39_ammo", 16);

//backburner
	SetTrieString(g_hItemInfoTrie, "40_classname", "tf_weapon_flamethrower");
	SetTrieValue(g_hItemInfoTrie, "40_index", 40);
	SetTrieValue(g_hItemInfoTrie, "40_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "40_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "40_level", 10);
//	SetTrieString(g_hItemInfoTrie, "40_attribs", "23 ; 1.0 ; 24 ; 1.0 ; 28 ; 0.0 ; 2 ; 1.15");	//these are the old backburner attribs (before april 14th, 2011)
	SetTrieString(g_hItemInfoTrie, "40_attribs", "170 ; 2.5 ; 24 ; 1.0 ; 28 ; 0.0 ; 2 ; 1.10");
	SetTrieValue(g_hItemInfoTrie, "40_ammo", 200);

//natascha
	SetTrieString(g_hItemInfoTrie, "41_classname", "tf_weapon_minigun");
	SetTrieValue(g_hItemInfoTrie, "41_index", 41);
	SetTrieValue(g_hItemInfoTrie, "41_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "41_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "41_level", 5);
	SetTrieString(g_hItemInfoTrie, "41_attribs", "32 ; 1.0 ; 1 ; 0.75 ; 86 ; 1.3 ; 144 ; 1");
	SetTrieValue(g_hItemInfoTrie, "41_ammo", 200);

//sandvich
	SetTrieString(g_hItemInfoTrie, "42_classname", "tf_weapon_lunchbox");
	SetTrieValue(g_hItemInfoTrie, "42_index", 42);
	SetTrieValue(g_hItemInfoTrie, "42_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "42_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "42_level", 1);
	SetTrieString(g_hItemInfoTrie, "42_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "42_ammo", 1);

//killing gloves of boxing
	SetTrieString(g_hItemInfoTrie, "43_classname", "tf_weapon_fists");
	SetTrieValue(g_hItemInfoTrie, "43_index", 43);
	SetTrieValue(g_hItemInfoTrie, "43_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "43_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "43_level", 7);
	SetTrieString(g_hItemInfoTrie, "43_attribs", "31 ; 5.0 ; 5 ; 1.2");
	SetTrieValue(g_hItemInfoTrie, "43_ammo", -1);

//sandman
	SetTrieString(g_hItemInfoTrie, "44_classname", "tf_weapon_bat_wood");
	SetTrieValue(g_hItemInfoTrie, "44_index", 44);
	SetTrieValue(g_hItemInfoTrie, "44_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "44_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "44_level", 15);
	SetTrieString(g_hItemInfoTrie, "44_attribs", "38 ; 1.0 ; 125 ; -15.0");
	SetTrieValue(g_hItemInfoTrie, "44_ammo", 1);

//force a nature
	SetTrieString(g_hItemInfoTrie, "45_classname", "tf_weapon_scattergun");
	SetTrieValue(g_hItemInfoTrie, "45_index", 45);
	SetTrieValue(g_hItemInfoTrie, "45_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "45_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "45_level", 10);
	SetTrieString(g_hItemInfoTrie, "45_attribs", "44 ; 1.0 ; 6 ; 0.5 ; 45 ; 1.2 ; 1 ; 0.9 ; 3 ; 0.4 ; 43 ; 1.0");
	SetTrieValue(g_hItemInfoTrie, "45_ammo", 32);

//bonk atomic punch
	SetTrieString(g_hItemInfoTrie, "46_classname", "tf_weapon_lunchbox_drink");
	SetTrieValue(g_hItemInfoTrie, "46_index", 46);
	SetTrieValue(g_hItemInfoTrie, "46_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "46_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "46_level", 5);
	SetTrieString(g_hItemInfoTrie, "46_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "46_ammo", 1);

//huntsman
	SetTrieString(g_hItemInfoTrie, "56_classname", "tf_weapon_compound_bow");
	SetTrieValue(g_hItemInfoTrie, "56_index", 56);
	SetTrieValue(g_hItemInfoTrie, "56_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "56_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "56_level", 10);
	SetTrieString(g_hItemInfoTrie, "56_attribs", "37 ; 0.5");
	SetTrieValue(g_hItemInfoTrie, "56_ammo", 12);

//razorback (broken NO LONGER)
	SetTrieString(g_hItemInfoTrie, "57_classname", "tf_wearable");
	SetTrieValue(g_hItemInfoTrie, "57_index", 57);
	SetTrieValue(g_hItemInfoTrie, "57_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "57_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "57_level", 10);
	SetTrieString(g_hItemInfoTrie, "57_attribs", "52 ; 1");

//jarate
	SetTrieString(g_hItemInfoTrie, "58_classname", "tf_weapon_jar");
	SetTrieValue(g_hItemInfoTrie, "58_index", 58);
	SetTrieValue(g_hItemInfoTrie, "58_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "58_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "58_level", 5);
	SetTrieString(g_hItemInfoTrie, "58_attribs", "56 ; 1.0");
	SetTrieValue(g_hItemInfoTrie, "58_ammo", 1);

//dead ringer
	SetTrieString(g_hItemInfoTrie, "59_classname", "tf_weapon_invis");
	SetTrieValue(g_hItemInfoTrie, "59_index", 59);
	SetTrieValue(g_hItemInfoTrie, "59_slot", 4);
	SetTrieValue(g_hItemInfoTrie, "59_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "59_level", 5);
	SetTrieString(g_hItemInfoTrie, "59_attribs", "33 ; 1.0 ; 34 ; 1.6 ; 35 ; 1.8");
	SetTrieValue(g_hItemInfoTrie, "59_ammo", -1);

//cloak and dagger
	SetTrieString(g_hItemInfoTrie, "60_classname", "tf_weapon_invis");
	SetTrieValue(g_hItemInfoTrie, "60_index", 60);
	SetTrieValue(g_hItemInfoTrie, "60_slot", 4);
	SetTrieValue(g_hItemInfoTrie, "60_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "60_level", 5);
	SetTrieString(g_hItemInfoTrie, "60_attribs", "48 ; 2.0 ; 35 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "60_ammo", -1);

//ambassador
	SetTrieString(g_hItemInfoTrie, "61_classname", "tf_weapon_revolver");
	SetTrieValue(g_hItemInfoTrie, "61_index", 61);
	SetTrieValue(g_hItemInfoTrie, "61_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "61_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "61_level", 5);
	SetTrieString(g_hItemInfoTrie, "61_attribs", "51 ; 1.0 ; 1 ; 0.85 ; 5 ; 1.2");
	SetTrieValue(g_hItemInfoTrie, "61_ammo", 24);

//direct hit
	SetTrieString(g_hItemInfoTrie, "127_classname", "tf_weapon_rocketlauncher_directhit");
	SetTrieValue(g_hItemInfoTrie, "127_index", 127);
	SetTrieValue(g_hItemInfoTrie, "127_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "127_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "127_level", 1);
	SetTrieString(g_hItemInfoTrie, "127_attribs", "100 ; 0.3 ; 103 ; 1.8 ; 2 ; 1.25 ; 114 ; 1.0");
	SetTrieValue(g_hItemInfoTrie, "127_ammo", 20);

//equalizer
	SetTrieString(g_hItemInfoTrie, "128_classname", "tf_weapon_shovel");
	SetTrieValue(g_hItemInfoTrie, "128_index", 128);
	SetTrieValue(g_hItemInfoTrie, "128_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "128_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "128_level", 10);
	SetTrieString(g_hItemInfoTrie, "128_attribs", "115 ; 1.0");
	SetTrieValue(g_hItemInfoTrie, "128_ammo", -1);

//buff banner
	SetTrieString(g_hItemInfoTrie, "129_classname", "tf_weapon_buff_item");
	SetTrieValue(g_hItemInfoTrie, "129_index", 129);
	SetTrieValue(g_hItemInfoTrie, "129_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "129_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "129_level", 5);
	SetTrieString(g_hItemInfoTrie, "129_attribs", "116 ; 1");
	SetTrieValue(g_hItemInfoTrie, "129_ammo", -1);

//scottish resistance
	SetTrieString(g_hItemInfoTrie, "130_classname", "tf_weapon_pipebomblauncher");
	SetTrieValue(g_hItemInfoTrie, "130_index", 130);
	SetTrieValue(g_hItemInfoTrie, "130_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "130_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "130_level", 5);
	SetTrieString(g_hItemInfoTrie, "130_attribs", "6 ; 0.75 ; 119 ; 1.0 ; 121 ; 1.0 ; 78 ; 1.5 ; 88 ; 6.0 ; 120 ; 0.8");
	SetTrieValue(g_hItemInfoTrie, "130_ammo", 24);

//chargin targe (broken NO LONGER)
	SetTrieString(g_hItemInfoTrie, "131_classname", "tf_wearable_demoshield");
	SetTrieValue(g_hItemInfoTrie, "131_index", 131);
	SetTrieValue(g_hItemInfoTrie, "131_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "131_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "131_level", 10);
	SetTrieString(g_hItemInfoTrie, "131_attribs", "60 ; 0.5 ; 64 ; 0.6");

//eyelander
	SetTrieString(g_hItemInfoTrie, "132_classname", "tf_weapon_sword");
	SetTrieValue(g_hItemInfoTrie, "132_index", 132);
	SetTrieValue(g_hItemInfoTrie, "132_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "132_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "132_level", 5);
	SetTrieString(g_hItemInfoTrie, "132_attribs", "15 ; 0 ; 125 ; -25 ; 219 ; 1.0");
	SetTrieValue(g_hItemInfoTrie, "132_ammo", -1);

//gunboats (broken NO LONGER)
	SetTrieString(g_hItemInfoTrie, "133_classname", "tf_wearable");
	SetTrieValue(g_hItemInfoTrie, "133_index", 133);
	SetTrieValue(g_hItemInfoTrie, "133_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "133_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "133_level", 10);
	SetTrieString(g_hItemInfoTrie, "133_attribs", "135 ; 0.4");

//wrangler
	SetTrieString(g_hItemInfoTrie, "140_classname", "tf_weapon_laser_pointer");
	SetTrieValue(g_hItemInfoTrie, "140_index", 140);
	SetTrieValue(g_hItemInfoTrie, "140_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "140_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "140_level", 5);
	SetTrieString(g_hItemInfoTrie, "140_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "140_ammo", -1);

//frontier justice
	SetTrieString(g_hItemInfoTrie, "141_classname", "tf_weapon_sentry_revenge");
	SetTrieValue(g_hItemInfoTrie, "141_index", 141);
	SetTrieValue(g_hItemInfoTrie, "141_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "141_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "141_level", 5);
	SetTrieString(g_hItemInfoTrie, "141_attribs", "136 ; 1 ; 15 ; 0 ; 3 ; 0.5");
	SetTrieValue(g_hItemInfoTrie, "141_ammo", 32);

//gunslinger
	SetTrieString(g_hItemInfoTrie, "142_classname", "tf_weapon_robot_arm");
	SetTrieValue(g_hItemInfoTrie, "142_index", 142);
	SetTrieValue(g_hItemInfoTrie, "142_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "142_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "142_level", 15);
	SetTrieString(g_hItemInfoTrie, "142_attribs", "124 ; 1 ; 26 ; 25.0 ; 15 ; 0");
	SetTrieValue(g_hItemInfoTrie, "142_ammo", -1);

//homewrecker
	SetTrieString(g_hItemInfoTrie, "153_classname", "tf_weapon_fireaxe");
	SetTrieValue(g_hItemInfoTrie, "153_index", 153);
	SetTrieValue(g_hItemInfoTrie, "153_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "153_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "153_level", 5);
	SetTrieString(g_hItemInfoTrie, "153_attribs", "137 ; 2.0 ; 138 ; 0.75 ; 146 ; 1");
	SetTrieValue(g_hItemInfoTrie, "153_ammo", -1);

//pain train
	SetTrieString(g_hItemInfoTrie, "154_classname", "tf_weapon_shovel");
	SetTrieValue(g_hItemInfoTrie, "154_index", 154);
	SetTrieValue(g_hItemInfoTrie, "154_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "154_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "154_level", 5);
	SetTrieString(g_hItemInfoTrie, "154_attribs", "68 ; 1 ; 67 ; 1.1");
	SetTrieValue(g_hItemInfoTrie, "154_ammo", -1);

//southern hospitality
	SetTrieString(g_hItemInfoTrie, "155_classname", "tf_weapon_wrench");
	SetTrieValue(g_hItemInfoTrie, "155_index", 155);
	SetTrieValue(g_hItemInfoTrie, "155_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "155_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "155_level", 20);
	SetTrieString(g_hItemInfoTrie, "155_attribs", "15 ; 0 ; 149 ; 5 ; 61 ; 1.20");
	SetTrieValue(g_hItemInfoTrie, "155_ammo", -1);

//dalokohs bar
	SetTrieString(g_hItemInfoTrie, "159_classname", "tf_weapon_lunchbox");
	SetTrieValue(g_hItemInfoTrie, "159_index", 159);
	SetTrieValue(g_hItemInfoTrie, "159_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "159_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "159_level", 1);
	SetTrieString(g_hItemInfoTrie, "159_attribs", "139 ; 1");
	SetTrieValue(g_hItemInfoTrie, "159_ammo", 1);

//lugermorph
	SetTrieString(g_hItemInfoTrie, "160_classname", "tf_weapon_pistol");
	SetTrieValue(g_hItemInfoTrie, "160_index", 160);
	SetTrieValue(g_hItemInfoTrie, "160_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "160_quality", 3);
	SetTrieValue(g_hItemInfoTrie, "160_level", 5);
	SetTrieString(g_hItemInfoTrie, "160_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "160_ammo", 36);

//big kill
	SetTrieString(g_hItemInfoTrie, "161_classname", "tf_weapon_revolver");
	SetTrieValue(g_hItemInfoTrie, "161_index", 161);
	SetTrieValue(g_hItemInfoTrie, "161_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "161_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "161_level", 5);
	SetTrieString(g_hItemInfoTrie, "161_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "161_ammo", 24);

//crit a cola
	SetTrieString(g_hItemInfoTrie, "163_classname", "tf_weapon_lunchbox_drink");
	SetTrieValue(g_hItemInfoTrie, "163_index", 163);
	SetTrieValue(g_hItemInfoTrie, "163_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "163_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "163_level", 5);
	SetTrieString(g_hItemInfoTrie, "163_attribs", "144 ; 2");
	SetTrieValue(g_hItemInfoTrie, "163_ammo", 1);

//golden wrench
	SetTrieString(g_hItemInfoTrie, "169_classname", "tf_weapon_wrench");
	SetTrieValue(g_hItemInfoTrie, "169_index", 169);
	SetTrieValue(g_hItemInfoTrie, "169_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "169_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "169_level", 25);
	SetTrieString(g_hItemInfoTrie, "169_attribs", "150 ; 1");
	SetTrieValue(g_hItemInfoTrie, "169_ammo", -1);

//tribalmans shiv
	SetTrieString(g_hItemInfoTrie, "171_classname", "tf_weapon_club");
	SetTrieValue(g_hItemInfoTrie, "171_index", 171);
	SetTrieValue(g_hItemInfoTrie, "171_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "171_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "171_level", 5);
	SetTrieString(g_hItemInfoTrie, "171_attribs", "149 ; 6 ; 1 ; 0.5");
	SetTrieValue(g_hItemInfoTrie, "171_ammo", -1);

//scotsmans skullcutter
	SetTrieString(g_hItemInfoTrie, "172_classname", "tf_weapon_sword");
	SetTrieValue(g_hItemInfoTrie, "172_index", 172);
	SetTrieValue(g_hItemInfoTrie, "172_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "172_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "172_level", 5);
	SetTrieString(g_hItemInfoTrie, "172_attribs", "2 ; 1.2 ; 54 ; 0.85");
	SetTrieValue(g_hItemInfoTrie, "172_ammo", -1);

//The Vita-Saw
	SetTrieString(g_hItemInfoTrie, "173_classname", "tf_weapon_bonesaw");
	SetTrieValue(g_hItemInfoTrie, "173_index", 173);
	SetTrieValue(g_hItemInfoTrie, "173_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "173_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "173_level", 5);
	SetTrieString(g_hItemInfoTrie, "173_attribs", "188 ; 20 ; 125 ; -10 ; 144 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "173_ammo", -1);

//Upgradeable bat
	SetTrieString(g_hItemInfoTrie, "190_classname", "tf_weapon_bat");
	SetTrieValue(g_hItemInfoTrie, "190_index", 190);
	SetTrieValue(g_hItemInfoTrie, "190_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "190_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "190_level", 1);
	SetTrieString(g_hItemInfoTrie, "190_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "190_ammo", -1);

//Upgradeable bottle
	SetTrieString(g_hItemInfoTrie, "191_classname", "tf_weapon_bottle");
	SetTrieValue(g_hItemInfoTrie, "191_index", 191);
	SetTrieValue(g_hItemInfoTrie, "191_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "191_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "191_level", 1);
	SetTrieString(g_hItemInfoTrie, "191_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "191_ammo", -1);

//Upgradeable fire axe
	SetTrieString(g_hItemInfoTrie, "192_classname", "tf_weapon_fireaxe");
	SetTrieValue(g_hItemInfoTrie, "192_index", 192);
	SetTrieValue(g_hItemInfoTrie, "192_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "192_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "192_level", 1);
	SetTrieString(g_hItemInfoTrie, "192_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "192_ammo", -1);

//Upgradeable kukri
	SetTrieString(g_hItemInfoTrie, "193_classname", "tf_weapon_club");
	SetTrieValue(g_hItemInfoTrie, "193_index", 193);
	SetTrieValue(g_hItemInfoTrie, "193_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "193_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "193_level", 1);
	SetTrieString(g_hItemInfoTrie, "193_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "193_ammo", -1);

//Upgradeable knife
	SetTrieString(g_hItemInfoTrie, "194_classname", "tf_weapon_knife");
	SetTrieValue(g_hItemInfoTrie, "194_index", 194);
	SetTrieValue(g_hItemInfoTrie, "194_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "194_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "194_level", 1);
	SetTrieString(g_hItemInfoTrie, "194_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "194_ammo", -1);

//Upgradeable fists
	SetTrieString(g_hItemInfoTrie, "195_classname", "tf_weapon_fists");
	SetTrieValue(g_hItemInfoTrie, "195_index", 195);
	SetTrieValue(g_hItemInfoTrie, "195_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "195_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "195_level", 1);
	SetTrieString(g_hItemInfoTrie, "195_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "195_ammo", -1);

//Upgradeable shovel
	SetTrieString(g_hItemInfoTrie, "196_classname", "tf_weapon_shovel");
	SetTrieValue(g_hItemInfoTrie, "196_index", 196);
	SetTrieValue(g_hItemInfoTrie, "196_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "196_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "196_level", 1);
	SetTrieString(g_hItemInfoTrie, "196_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "196_ammo", -1);

//Upgradeable wrench
	SetTrieString(g_hItemInfoTrie, "197_classname", "tf_weapon_wrench");
	SetTrieValue(g_hItemInfoTrie, "197_index", 197);
	SetTrieValue(g_hItemInfoTrie, "197_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "197_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "197_level", 1);
	SetTrieString(g_hItemInfoTrie, "197_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "197_ammo", -1);

//Upgradeable bonesaw
	SetTrieString(g_hItemInfoTrie, "198_classname", "tf_weapon_bonesaw");
	SetTrieValue(g_hItemInfoTrie, "198_index", 198);
	SetTrieValue(g_hItemInfoTrie, "198_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "198_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "198_level", 1);
	SetTrieString(g_hItemInfoTrie, "198_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "198_ammo", -1);

//Upgradeable shotgun engineer
	SetTrieString(g_hItemInfoTrie, "199_classname", "tf_weapon_shotgun_primary");
	SetTrieValue(g_hItemInfoTrie, "199_index", 199);
	SetTrieValue(g_hItemInfoTrie, "199_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "199_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "199_level", 1);
	SetTrieString(g_hItemInfoTrie, "199_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "199_ammo", 32);

//Upgradeable shotgun other classes
	SetTrieString(g_hItemInfoTrie, "4199_classname", "tf_weapon_shotgun_soldier");
	SetTrieValue(g_hItemInfoTrie, "4199_index", 199);
	SetTrieValue(g_hItemInfoTrie, "4199_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "4199_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "4199_level", 1);
	SetTrieString(g_hItemInfoTrie, "4199_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "4199_ammo", 32);

//Upgradeable scattergun
	SetTrieString(g_hItemInfoTrie, "200_classname", "tf_weapon_scattergun");
	SetTrieValue(g_hItemInfoTrie, "200_index", 200);
	SetTrieValue(g_hItemInfoTrie, "200_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "200_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "200_level", 1);
	SetTrieString(g_hItemInfoTrie, "200_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "200_ammo", 32);

//Upgradeable sniper rifle
	SetTrieString(g_hItemInfoTrie, "201_classname", "tf_weapon_sniperrifle");
	SetTrieValue(g_hItemInfoTrie, "201_index", 201);
	SetTrieValue(g_hItemInfoTrie, "201_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "201_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "201_level", 1);
	SetTrieString(g_hItemInfoTrie, "201_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "201_ammo", 25);

//Upgradeable minigun
	SetTrieString(g_hItemInfoTrie, "202_classname", "tf_weapon_minigun");
	SetTrieValue(g_hItemInfoTrie, "202_index", 202);
	SetTrieValue(g_hItemInfoTrie, "202_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "202_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "202_level", 1);
	SetTrieString(g_hItemInfoTrie, "202_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "202_ammo", 200);

//Upgradeable smg
	SetTrieString(g_hItemInfoTrie, "203_classname", "tf_weapon_smg");
	SetTrieValue(g_hItemInfoTrie, "203_index", 203);
	SetTrieValue(g_hItemInfoTrie, "203_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "203_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "203_level", 1);
	SetTrieString(g_hItemInfoTrie, "203_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "203_ammo", 75);

//Upgradeable syringe gun
	SetTrieString(g_hItemInfoTrie, "204_classname", "tf_weapon_syringegun_medic");
	SetTrieValue(g_hItemInfoTrie, "204_index", 204);
	SetTrieValue(g_hItemInfoTrie, "204_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "204_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "204_level", 1);
	SetTrieString(g_hItemInfoTrie, "204_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "204_ammo", 150);

//Upgradeable rocket launcher
	SetTrieString(g_hItemInfoTrie, "205_classname", "tf_weapon_rocketlauncher");
	SetTrieValue(g_hItemInfoTrie, "205_index", 205);
	SetTrieValue(g_hItemInfoTrie, "205_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "205_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "205_level", 1);
	SetTrieString(g_hItemInfoTrie, "205_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "205_ammo", 20);

//Upgradeable grenade launcher
	SetTrieString(g_hItemInfoTrie, "206_classname", "tf_weapon_grenadelauncher");
	SetTrieValue(g_hItemInfoTrie, "206_index", 206);
	SetTrieValue(g_hItemInfoTrie, "206_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "206_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "206_level", 1);
	SetTrieString(g_hItemInfoTrie, "206_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "206_ammo", 16);

//Upgradeable sticky launcher
	SetTrieString(g_hItemInfoTrie, "207_classname", "tf_weapon_pipebomblauncher");
	SetTrieValue(g_hItemInfoTrie, "207_index", 207);
	SetTrieValue(g_hItemInfoTrie, "207_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "207_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "207_level", 1);
	SetTrieString(g_hItemInfoTrie, "207_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "207_ammo", 24);

//Upgradeable flamethrower
	SetTrieString(g_hItemInfoTrie, "208_classname", "tf_weapon_flamethrower");
	SetTrieValue(g_hItemInfoTrie, "208_index", 208);
	SetTrieValue(g_hItemInfoTrie, "208_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "208_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "208_level", 1);
	SetTrieString(g_hItemInfoTrie, "208_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "208_ammo", 200);

//Upgradeable pistol
	SetTrieString(g_hItemInfoTrie, "209_classname", "tf_weapon_pistol");
	SetTrieValue(g_hItemInfoTrie, "209_index", 209);
	SetTrieValue(g_hItemInfoTrie, "209_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "209_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "209_level", 1);
	SetTrieString(g_hItemInfoTrie, "209_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "209_ammo", 100); //36 for scout, 200 for engy, but idk what to use.

//Upgradeable revolver
	SetTrieString(g_hItemInfoTrie, "210_classname", "tf_weapon_revolver");
	SetTrieValue(g_hItemInfoTrie, "210_index", 210);
	SetTrieValue(g_hItemInfoTrie, "210_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "210_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "210_level", 1);
	SetTrieString(g_hItemInfoTrie, "210_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "210_ammo", 24);

//Upgradeable medigun
	SetTrieString(g_hItemInfoTrie, "211_classname", "tf_weapon_medigun");
	SetTrieValue(g_hItemInfoTrie, "211_index", 211);
	SetTrieValue(g_hItemInfoTrie, "211_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "211_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "211_level", 1);
	SetTrieString(g_hItemInfoTrie, "211_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "211_ammo", -1);

//Upgradeable invis watch
	SetTrieString(g_hItemInfoTrie, "212_classname", "tf_weapon_invis");
	SetTrieValue(g_hItemInfoTrie, "212_index", 212);
	SetTrieValue(g_hItemInfoTrie, "212_slot", 4);
	SetTrieValue(g_hItemInfoTrie, "212_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "212_level", 1);
	SetTrieString(g_hItemInfoTrie, "212_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "212_ammo", -1);

//The Powerjack
	SetTrieString(g_hItemInfoTrie, "214_classname", "tf_weapon_fireaxe");
	SetTrieValue(g_hItemInfoTrie, "214_index", 214);
	SetTrieValue(g_hItemInfoTrie, "214_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "214_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "214_level", 5);
//	SetTrieString(g_hItemInfoTrie, "214_attribs", "180 ; 75 ; 2 ; 1.25 ; 15 ; 0");	//old attribs (before april 14, 2011)
	SetTrieString(g_hItemInfoTrie, "214_attribs", "180 ; 75 ; 206 ; 1.2");
	SetTrieValue(g_hItemInfoTrie, "214_ammo", -1);
	
//The Degreaser
	SetTrieString(g_hItemInfoTrie, "215_classname", "tf_weapon_flamethrower");
	SetTrieValue(g_hItemInfoTrie, "215_index", 215);
	SetTrieValue(g_hItemInfoTrie, "215_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "215_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "215_level", 10);
	SetTrieString(g_hItemInfoTrie, "215_attribs", "178 ; 0.35 ; 72 ; 0.75");
	SetTrieValue(g_hItemInfoTrie, "215_ammo", 200);

//The Shortstop
	SetTrieString(g_hItemInfoTrie, "220_classname", "tf_weapon_handgun_scout_primary");
	SetTrieValue(g_hItemInfoTrie, "220_index", 220);
	SetTrieValue(g_hItemInfoTrie, "220_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "220_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "220_level", 1);
	SetTrieString(g_hItemInfoTrie, "220_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "220_ammo", 36);

//The Holy Mackerel
	SetTrieString(g_hItemInfoTrie, "221_classname", "tf_weapon_bat_fish");
	SetTrieValue(g_hItemInfoTrie, "221_index", 221);
	SetTrieValue(g_hItemInfoTrie, "221_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "221_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "221_level", 42);
	SetTrieString(g_hItemInfoTrie, "221_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "221_ammo", -1);

//Mad Milk
	SetTrieString(g_hItemInfoTrie, "222_classname", "tf_weapon_jar_milk");
	SetTrieValue(g_hItemInfoTrie, "222_index", 222);
	SetTrieValue(g_hItemInfoTrie, "222_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "222_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "222_level", 5);
	SetTrieString(g_hItemInfoTrie, "222_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "222_ammo", 1);

//L'Etranger
	SetTrieString(g_hItemInfoTrie, "224_classname", "tf_weapon_revolver");
	SetTrieValue(g_hItemInfoTrie, "224_index", 224);
	SetTrieValue(g_hItemInfoTrie, "224_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "224_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "224_level", 5);
	SetTrieString(g_hItemInfoTrie, "224_attribs", "166 ; 15.0 ; 1 ; 0.8");
	SetTrieValue(g_hItemInfoTrie, "224_ammo", 24);

//Your Eternal Reward
	SetTrieString(g_hItemInfoTrie, "225_classname", "tf_weapon_knife");
	SetTrieValue(g_hItemInfoTrie, "225_index", 225);
	SetTrieValue(g_hItemInfoTrie, "225_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "225_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "225_level", 1);
	SetTrieString(g_hItemInfoTrie, "225_attribs", "154 ; 1.0 ; 156 ; 1.0 ; 155 ; 1.0 ; 144 ; 1.0");
	SetTrieValue(g_hItemInfoTrie, "225_ammo", -1);

//The Battalion's Backup
	SetTrieString(g_hItemInfoTrie, "226_classname", "tf_weapon_buff_item");
	SetTrieValue(g_hItemInfoTrie, "226_index", 226);
	SetTrieValue(g_hItemInfoTrie, "226_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "226_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "226_level", 10);
	SetTrieString(g_hItemInfoTrie, "226_attribs", "116 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "226_ammo", -1);

//The Black Box
	SetTrieString(g_hItemInfoTrie, "228_classname", "tf_weapon_rocketlauncher");
	SetTrieValue(g_hItemInfoTrie, "228_index", 228);
	SetTrieValue(g_hItemInfoTrie, "228_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "228_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "228_level", 5);
	SetTrieString(g_hItemInfoTrie, "228_attribs", "16 ; 15.0 ; 3 ; 0.75");
	SetTrieValue(g_hItemInfoTrie, "228_ammo", 20);

//The Sydney Sleeper
	SetTrieString(g_hItemInfoTrie, "230_classname", "tf_weapon_sniperrifle");
	SetTrieValue(g_hItemInfoTrie, "230_index", 230);
	SetTrieValue(g_hItemInfoTrie, "230_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "230_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "230_level", 1);
	SetTrieString(g_hItemInfoTrie, "230_attribs", "42 ; 1.0 ; 175 ; 8.0 ; 15 ; 0 ; 41 ; 1.25");
	SetTrieValue(g_hItemInfoTrie, "230_ammo", 25);

//darwin's danger shield (broken NO LONGER)
	SetTrieString(g_hItemInfoTrie, "231_classname", "tf_wearable");
	SetTrieValue(g_hItemInfoTrie, "231_index", 231);
	SetTrieValue(g_hItemInfoTrie, "231_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "231_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "231_level", 10);
	SetTrieString(g_hItemInfoTrie, "231_attribs", "26 ; 25");

//The Bushwacka
	SetTrieString(g_hItemInfoTrie, "232_classname", "tf_weapon_club");
	SetTrieValue(g_hItemInfoTrie, "232_index", 232);
	SetTrieValue(g_hItemInfoTrie, "232_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "232_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "232_level", 5);
	SetTrieString(g_hItemInfoTrie, "232_attribs", "179 ; 1 ; 61 ; 1.2");
	SetTrieValue(g_hItemInfoTrie, "232_ammo", -1);

//Rocket Jumper
	SetTrieString(g_hItemInfoTrie, "237_classname", "tf_weapon_rocketlauncher");
	SetTrieValue(g_hItemInfoTrie, "237_index", 237);
	SetTrieValue(g_hItemInfoTrie, "237_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "237_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "237_level", 1);
	SetTrieString(g_hItemInfoTrie, "237_attribs", "1 ; 0.0 ; 181 ; 1.0 ; 76 ; 3.0 ; 65 ; 2.0 ; 67 ; 2.0 ; 61 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "237_ammo", 60);

//gloves of running urgently 
	SetTrieString(g_hItemInfoTrie, "239_classname", "tf_weapon_fists");
	SetTrieValue(g_hItemInfoTrie, "239_index", 239);
	SetTrieValue(g_hItemInfoTrie, "239_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "239_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "239_level", 10);
	SetTrieString(g_hItemInfoTrie, "239_attribs", "128 ; 1.0 ; 107 ; 1.3 ; 1 ; 0.5 ; 191 ; -6.0 ; 144 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "239_ammo", -1);

//Frying Pan (Now if only it had augment slots)
	SetTrieString(g_hItemInfoTrie, "264_classname", "tf_weapon_shovel");
	SetTrieValue(g_hItemInfoTrie, "264_index", 264);
	SetTrieValue(g_hItemInfoTrie, "264_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "264_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "264_level", 5);
	SetTrieString(g_hItemInfoTrie, "264_attribs", "195 ; 1");
	SetTrieValue(g_hItemInfoTrie, "264_ammo", -1);

//sticky jumper
	SetTrieString(g_hItemInfoTrie, "265_classname", "tf_weapon_pipebomblauncher");
	SetTrieValue(g_hItemInfoTrie, "265_index", 265);
	SetTrieValue(g_hItemInfoTrie, "265_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "265_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "265_level", 1);
	SetTrieString(g_hItemInfoTrie, "265_attribs", "1 ; 0.0 ; 181 ; 1.0 ; 78 ; 3.0 ; 65 ; 2.0 ; 67 ; 2.0 ; 61 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "265_ammo", 72);

//horseless headless horsemann's headtaker
	SetTrieString(g_hItemInfoTrie, "266_classname", "tf_weapon_sword");
	SetTrieValue(g_hItemInfoTrie, "266_index", 266);
	SetTrieValue(g_hItemInfoTrie, "266_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "266_quality", 5);
	SetTrieValue(g_hItemInfoTrie, "266_level", 5);
	SetTrieString(g_hItemInfoTrie, "266_attribs", "15 ; 0 ; 125 ; -25 ; 219 ; 1.0");
	SetTrieValue(g_hItemInfoTrie, "266_ammo", -1);

//lugermorph from Poker Night
	SetTrieString(g_hItemInfoTrie, "294_classname", "tf_weapon_pistol");
	SetTrieValue(g_hItemInfoTrie, "294_index", 294);
	SetTrieValue(g_hItemInfoTrie, "294_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "294_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "294_level", 5);
	SetTrieString(g_hItemInfoTrie, "294_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "294_ammo", 36);

//Enthusiast's Timepiece
	SetTrieString(g_hItemInfoTrie, "297_classname", "tf_weapon_invis");
	SetTrieValue(g_hItemInfoTrie, "297_index", 297);
	SetTrieValue(g_hItemInfoTrie, "297_slot", 4);
	SetTrieValue(g_hItemInfoTrie, "297_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "297_level", 5);
	SetTrieString(g_hItemInfoTrie, "297_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "297_ammo", -1);

//The Iron Curtain
	SetTrieString(g_hItemInfoTrie, "298_classname", "tf_weapon_minigun");
	SetTrieValue(g_hItemInfoTrie, "298_index", 298);
	SetTrieValue(g_hItemInfoTrie, "298_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "298_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "298_level", 5);
	SetTrieString(g_hItemInfoTrie, "298_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "298_ammo", 200);

//Amputator
	SetTrieString(g_hItemInfoTrie, "304_classname", "tf_weapon_bonesaw");
	SetTrieValue(g_hItemInfoTrie, "304_index", 304);
	SetTrieValue(g_hItemInfoTrie, "304_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "304_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "304_level", 15);
	SetTrieString(g_hItemInfoTrie, "304_attribs", "200 ; 1 ; 144 ; 3.0");
	SetTrieValue(g_hItemInfoTrie, "304_ammo", -1);

//Crusader's Crossbow
	SetTrieString(g_hItemInfoTrie, "305_classname", "tf_weapon_crossbow");
	SetTrieValue(g_hItemInfoTrie, "305_index", 305);
	SetTrieValue(g_hItemInfoTrie, "305_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "305_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "305_level", 15);
	SetTrieString(g_hItemInfoTrie, "305_attribs", "199 ; 1.0 ; 42 ; 1.0 ; 77 ; 0.25");
	SetTrieValue(g_hItemInfoTrie, "305_ammo", 38);

//Ullapool Caber
	SetTrieString(g_hItemInfoTrie, "307_classname", "tf_weapon_stickbomb");
	SetTrieValue(g_hItemInfoTrie, "307_index", 307);
	SetTrieValue(g_hItemInfoTrie, "307_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "307_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "307_level", 10);
	SetTrieString(g_hItemInfoTrie, "307_attribs", "15 ; 0");
	SetTrieValue(g_hItemInfoTrie, "307_ammo", -1);

//Loch-n-Load
	SetTrieString(g_hItemInfoTrie, "308_classname", "tf_weapon_grenadelauncher");
	SetTrieValue(g_hItemInfoTrie, "308_index", 308);
	SetTrieValue(g_hItemInfoTrie, "308_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "308_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "308_level", 10);
	SetTrieString(g_hItemInfoTrie, "308_attribs", "3 ; 0.4 ; 2 ; 1.2 ; 103 ; 1.25 ; 207 ; 1.25 ; 127 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "308_ammo", 16);

//Warrior's Spirit
	SetTrieString(g_hItemInfoTrie, "310_classname", "tf_weapon_fists");
	SetTrieValue(g_hItemInfoTrie, "310_index", 310);
	SetTrieValue(g_hItemInfoTrie, "310_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "310_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "310_level", 10);
	SetTrieString(g_hItemInfoTrie, "310_attribs", "2 ; 1.3 ; 125 ; -20");
	SetTrieValue(g_hItemInfoTrie, "310_ammo", -1);

//Buffalo Steak Sandvich
	SetTrieString(g_hItemInfoTrie, "311_classname", "tf_weapon_lunchbox");
	SetTrieValue(g_hItemInfoTrie, "311_index", 311);
	SetTrieValue(g_hItemInfoTrie, "311_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "311_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "311_level", 1);
	SetTrieString(g_hItemInfoTrie, "311_attribs", "144 ; 2");
	SetTrieValue(g_hItemInfoTrie, "311_ammo", 1);

//Brass Beast
	SetTrieString(g_hItemInfoTrie, "312_classname", "tf_weapon_minigun");
	SetTrieValue(g_hItemInfoTrie, "312_index", 312);
	SetTrieValue(g_hItemInfoTrie, "312_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "312_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "312_level", 5);
	SetTrieString(g_hItemInfoTrie, "312_attribs", "2 ; 1.2 ; 86 ; 1.5 ; 183 ; 0.4");
	SetTrieValue(g_hItemInfoTrie, "312_ammo", 200);

//Candy Cane
	SetTrieString(g_hItemInfoTrie, "317_classname", "tf_weapon_bat");
	SetTrieValue(g_hItemInfoTrie, "317_index", 317);
	SetTrieValue(g_hItemInfoTrie, "317_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "317_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "317_level", 25);
	SetTrieString(g_hItemInfoTrie, "317_attribs", "203 ; 1.0 ; 65 ; 1.25");
	SetTrieValue(g_hItemInfoTrie, "317_ammo", -1);

//Boston Basher
	SetTrieString(g_hItemInfoTrie, "325_classname", "tf_weapon_bat");
	SetTrieValue(g_hItemInfoTrie, "325_index", 325);
	SetTrieValue(g_hItemInfoTrie, "325_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "325_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "325_level", 25);
	SetTrieString(g_hItemInfoTrie, "325_attribs", "149 ; 5.0 ; 204 ; 1.0");
	SetTrieValue(g_hItemInfoTrie, "325_ammo", -1);

//Backscratcher
	SetTrieString(g_hItemInfoTrie, "326_classname", "tf_weapon_fireaxe");
	SetTrieValue(g_hItemInfoTrie, "326_index", 326);
	SetTrieValue(g_hItemInfoTrie, "326_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "326_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "326_level", 10);
	SetTrieString(g_hItemInfoTrie, "326_attribs", "2 ; 1.25 ; 69 ; 0.25 ; 108 ; 1.5");
	SetTrieValue(g_hItemInfoTrie, "326_ammo", -1);

//Claidheamh Mòr
	SetTrieString(g_hItemInfoTrie, "327_classname", "tf_weapon_sword");
	SetTrieValue(g_hItemInfoTrie, "327_index", 327);
	SetTrieValue(g_hItemInfoTrie, "327_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "327_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "327_level", 5);
	SetTrieString(g_hItemInfoTrie, "327_attribs", "15 ; 0.0 ; 202 ; 0.5 ; 125 ; -15");
	SetTrieValue(g_hItemInfoTrie, "327_ammo", -1);

//Jag
	SetTrieString(g_hItemInfoTrie, "329_classname", "tf_weapon_wrench");
	SetTrieValue(g_hItemInfoTrie, "329_index", 329);
	SetTrieValue(g_hItemInfoTrie, "329_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "329_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "329_level", 15);
	SetTrieString(g_hItemInfoTrie, "329_attribs", "92 ; 1.3 ; 1 ; 0.75");
	SetTrieValue(g_hItemInfoTrie, "329_ammo", -1);

//Fists of Steel
	SetTrieString(g_hItemInfoTrie, "331_classname", "tf_weapon_fists");
	SetTrieValue(g_hItemInfoTrie, "331_index", 331);
	SetTrieValue(g_hItemInfoTrie, "331_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "331_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "331_level", 10);
	SetTrieString(g_hItemInfoTrie, "331_attribs", "205 ; 0.6 ; 206 ; 2.0 ; 177 ; 1.2");
	SetTrieValue(g_hItemInfoTrie, "331_ammo", -1);

//Sharpened Volcano Fragment
	SetTrieString(g_hItemInfoTrie, "348_classname", "tf_weapon_fireaxe");
	SetTrieValue(g_hItemInfoTrie, "348_index", 348);
	SetTrieValue(g_hItemInfoTrie, "348_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "348_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "348_level", 10);
	SetTrieString(g_hItemInfoTrie, "348_attribs", "208 ; 1.0 ; 1 ; 0.8");
	SetTrieValue(g_hItemInfoTrie, "348_ammo", -1);

//Sun on a Stick
	SetTrieString(g_hItemInfoTrie, "349_classname", "tf_weapon_bat");
	SetTrieValue(g_hItemInfoTrie, "349_index", 349);
	SetTrieValue(g_hItemInfoTrie, "349_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "349_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "349_level", 10);
//	SetTrieString(g_hItemInfoTrie, "349_attribs", "209 ; 1.0 ; 1 ; 0.85 ; 153 ; 1.0");	//old pre april 14, 2011 attribs
	SetTrieString(g_hItemInfoTrie, "349_attribs", "20 ; 1.0 ; 1 ; 0.75");
	SetTrieValue(g_hItemInfoTrie, "349_ammo", -1);

//Soldier's Sashimono - The Concheror
	SetTrieString(g_hItemInfoTrie, "354_classname", "tf_weapon_buff_item");
	SetTrieValue(g_hItemInfoTrie, "354_index", 354);
	SetTrieValue(g_hItemInfoTrie, "354_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "354_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "354_level", 5);
	SetTrieString(g_hItemInfoTrie, "354_attribs", "116 ; 3.0");
	SetTrieValue(g_hItemInfoTrie, "354_ammo", -1);

//Gunbai - Fan o'War
	SetTrieString(g_hItemInfoTrie, "355_classname", "tf_weapon_bat");
	SetTrieValue(g_hItemInfoTrie, "355_index", 355);
	SetTrieValue(g_hItemInfoTrie, "355_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "355_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "355_level", 5);
	SetTrieString(g_hItemInfoTrie, "355_attribs", "218 ; 1.0 ; 1 ; 0.1");
	SetTrieValue(g_hItemInfoTrie, "355_ammo", -1);

//Kunai - Conniver's Kunai
	SetTrieString(g_hItemInfoTrie, "356_classname", "tf_weapon_knife");
	SetTrieValue(g_hItemInfoTrie, "356_index", 356);
	SetTrieValue(g_hItemInfoTrie, "356_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "356_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "356_level", 1);
	SetTrieString(g_hItemInfoTrie, "356_attribs", "217 ; 1.0 ; 125 ; -65 ; 144 ; 1");
	SetTrieValue(g_hItemInfoTrie, "356_ammo", -1);

//Soldier Katana - The Half-Zatoichi
	SetTrieString(g_hItemInfoTrie, "357_classname", "tf_weapon_katana");
	SetTrieValue(g_hItemInfoTrie, "357_index", 357);
	SetTrieValue(g_hItemInfoTrie, "357_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "357_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "357_level", 5);
	SetTrieString(g_hItemInfoTrie, "357_attribs", "219 ; 1.0 ; 220 ; 100.0 ; 226 ; 1");
	SetTrieValue(g_hItemInfoTrie, "357_ammo", -1);

//valve rocket launcher
	SetTrieString(g_hItemInfoTrie, "9018_classname", "tf_weapon_rocketlauncher");
	SetTrieValue(g_hItemInfoTrie, "9018_index", 18);
	SetTrieValue(g_hItemInfoTrie, "9018_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "9018_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "9018_level", 100);
	SetTrieString(g_hItemInfoTrie, "9018_attribs", "2 ; 1.15 ; 4 ; 1.5 ; 6 ; 0.85 ; 110 ; 15.0 ; 20 ; 1.0 ; 26 ; 50.0 ; 31 ; 5.0 ; 32 ; 0.30 ; 53 ; 1.0 ; 60 ; 0.85 ; 123 ; 1.15 ; 134 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "9018_ammo", 200);

//valve sticky launcher
	SetTrieString(g_hItemInfoTrie, "9020_classname", "tf_weapon_pipebomblauncher");
	SetTrieValue(g_hItemInfoTrie, "9020_index", 20);
	SetTrieValue(g_hItemInfoTrie, "9020_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "9020_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "9020_level", 100);
	SetTrieString(g_hItemInfoTrie, "9020_attribs", "2 ; 1.15 ; 4 ; 1.5 ; 6 ; 0.85 ; 110 ; 15.0 ; 20 ; 1.0 ; 26 ; 50.0 ; 31 ; 5.0 ; 32 ; 0.30 ; 53 ; 1.0 ; 60 ; 0.85 ; 123 ; 1.15 ; 134 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "9020_ammo", 200);

//valve sniper rifle
	SetTrieString(g_hItemInfoTrie, "9014_classname", "tf_weapon_sniperrifle");
	SetTrieValue(g_hItemInfoTrie, "9014_index", 14);
	SetTrieValue(g_hItemInfoTrie, "9014_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "9014_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "9014_level", 100);
	SetTrieString(g_hItemInfoTrie, "9014_attribs", "2 ; 1.15 ; 4 ; 1.5 ; 6 ; 0.85 ; 110 ; 15.0 ; 20 ; 1.0 ; 26 ; 50.0 ; 31 ; 5.0 ; 32 ; 0.30 ; 53 ; 1.0 ; 60 ; 0.85 ; 123 ; 1.15 ; 134 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "9014_ammo", 200);

//valve scattergun
	SetTrieString(g_hItemInfoTrie, "9013_classname", "tf_weapon_scattergun");
	SetTrieValue(g_hItemInfoTrie, "9013_index", 13);
	SetTrieValue(g_hItemInfoTrie, "9013_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "9013_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "9013_level", 100);
	SetTrieString(g_hItemInfoTrie, "9013_attribs", "2 ; 1.15 ; 4 ; 1.5 ; 6 ; 0.85 ; 110 ; 15.0 ; 20 ; 1.0 ; 26 ; 50.0 ; 31 ; 5.0 ; 32 ; 0.30 ; 53 ; 1.0 ; 60 ; 0.85 ; 123 ; 1.15 ; 134 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "9013_ammo", 200);

//valve flamethrower
	SetTrieString(g_hItemInfoTrie, "9021_classname", "tf_weapon_flamethrower");
	SetTrieValue(g_hItemInfoTrie, "9021_index", 21);
	SetTrieValue(g_hItemInfoTrie, "9021_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "9021_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "9021_level", 100);
	SetTrieString(g_hItemInfoTrie, "9021_attribs", "2 ; 1.15 ; 4 ; 1.5 ; 6 ; 0.85 ; 110 ; 15.0 ; 20 ; 1.0 ; 26 ; 50.0 ; 31 ; 5.0 ; 32 ; 0.30 ; 53 ; 1.0 ; 60 ; 0.85 ; 123 ; 1.15 ; 134 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "9021_ammo", 400);

//valve syringe gun
	SetTrieString(g_hItemInfoTrie, "9017_classname", "tf_weapon_syringegun_medic");
	SetTrieValue(g_hItemInfoTrie, "9017_index", 17);
	SetTrieValue(g_hItemInfoTrie, "9017_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "9017_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "9017_level", 100);
	SetTrieString(g_hItemInfoTrie, "9017_attribs", "2 ; 1.15 ; 4 ; 1.5 ; 6 ; 0.85 ; 110 ; 15.0 ; 20 ; 1.0 ; 26 ; 50.0 ; 31 ; 5.0 ; 32 ; 0.30 ; 53 ; 1.0 ; 60 ; 0.85 ; 123 ; 1.15 ; 134 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "9017_ammo", 300);

//valve minigun
	SetTrieString(g_hItemInfoTrie, "9015_classname", "tf_weapon_minigun");
	SetTrieValue(g_hItemInfoTrie, "9015_index", 15);
	SetTrieValue(g_hItemInfoTrie, "9015_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "9015_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "9015_level", 100);
	SetTrieString(g_hItemInfoTrie, "9015_attribs", "2 ; 1.15 ; 4 ; 1.5 ; 6 ; 0.85 ; 110 ; 15.0 ; 20 ; 1.0 ; 26 ; 50.0 ; 31 ; 5.0 ; 32 ; 0.30 ; 53 ; 1.0 ; 60 ; 0.85 ; 123 ; 1.15 ; 134 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "9015_ammo", 400);

//valve revolver
	SetTrieString(g_hItemInfoTrie, "9024_classname", "tf_weapon_revolver");
	SetTrieValue(g_hItemInfoTrie, "9024_index", 24);
	SetTrieValue(g_hItemInfoTrie, "9024_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "9024_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "9024_level", 100);
	SetTrieString(g_hItemInfoTrie, "9024_attribs", "2 ; 1.15 ; 4 ; 1.5 ; 6 ; 0.85 ; 110 ; 15.0 ; 20 ; 1.0 ; 26 ; 50.0 ; 31 ; 5.0 ; 32 ; 0.30 ; 53 ; 1.0 ; 60 ; 0.85 ; 123 ; 1.15 ; 134 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "9024_ammo", 100);

//valve shotgun engineer
	SetTrieString(g_hItemInfoTrie, "9009_classname", "tf_weapon_shotgun_primary");
	SetTrieValue(g_hItemInfoTrie, "9009_index", 9);
	SetTrieValue(g_hItemInfoTrie, "9009_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "9009_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "9009_level", 100);
	SetTrieString(g_hItemInfoTrie, "9009_attribs", "2 ; 1.15 ; 4 ; 1.5 ; 6 ; 0.85 ; 110 ; 15.0 ; 20 ; 1.0 ; 26 ; 50.0 ; 31 ; 5.0 ; 32 ; 0.30 ; 53 ; 1.0 ; 60 ; 0.85 ; 123 ; 1.15 ; 134 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "9009_ammo", 100);

//valve medigun
	SetTrieString(g_hItemInfoTrie, "9029_classname", "tf_weapon_medigun");
	SetTrieValue(g_hItemInfoTrie, "9029_index", 29);
	SetTrieValue(g_hItemInfoTrie, "9029_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "9029_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "9029_level", 100);
	SetTrieString(g_hItemInfoTrie, "9029_attribs", "8 ; 1.15 ; 10 ; 1.15 ; 13 ; 0.0 ; 26 ; 50.0 ; 53 ; 1.0 ; 60 ; 0.85 ; 123 ; 1.5 ; 134 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "9029_ammo", -1);

//ludmila
	SetTrieString(g_hItemInfoTrie, "2041_classname", "tf_weapon_minigun");
	SetTrieValue(g_hItemInfoTrie, "2041_index", 41);
	SetTrieValue(g_hItemInfoTrie, "2041_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "2041_quality", 10);
	SetTrieValue(g_hItemInfoTrie, "2041_level", 5);
	SetTrieString(g_hItemInfoTrie, "2041_attribs", "29 ; 1 ; 86 ; 1.2 ; 5 ; 1.1");
	SetTrieValue(g_hItemInfoTrie, "2041_ammo", 200);

//spycrab pda
	SetTrieString(g_hItemInfoTrie, "9027_classname", "tf_weapon_pda_spy");
	SetTrieValue(g_hItemInfoTrie, "9027_index", 27);
	SetTrieValue(g_hItemInfoTrie, "9027_slot", 3);
	SetTrieValue(g_hItemInfoTrie, "9027_quality", 2);
	SetTrieValue(g_hItemInfoTrie, "9027_level", 100);
	SetTrieString(g_hItemInfoTrie, "9027_attribs", "128 ; 1.0 ; 60 ; 0.0 ; 62 ; 0.0 ; 64 ; 0.0 ; 66 ; 0.0 ; 169 ; 0.0 ; 205 ; 0.0 ; 206 ; 0.0 ; 70 ; 2.0 ; 53 ; 1.0 ; 68 ; -1.0 ; 134 ; 9.0");
	SetTrieValue(g_hItemInfoTrie, "9027_ammo", -1);

//fire retardant suit (revolver does no damage)
	SetTrieString(g_hItemInfoTrie, "2061_classname", "tf_weapon_revolver");
	SetTrieValue(g_hItemInfoTrie, "2061_index", 61);
	SetTrieValue(g_hItemInfoTrie, "2061_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "2061_quality", 10);
	SetTrieValue(g_hItemInfoTrie, "2061_level", 5);
	SetTrieString(g_hItemInfoTrie, "2061_attribs", "168 ; 1.0 ; 1 ; 0.0");
	SetTrieValue(g_hItemInfoTrie, "2061_ammo", -1);

//valve cheap rocket launcher
	SetTrieString(g_hItemInfoTrie, "8018_classname", "tf_weapon_rocketlauncher");
	SetTrieValue(g_hItemInfoTrie, "8018_index", 18);
	SetTrieValue(g_hItemInfoTrie, "8018_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "8018_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "8018_level", 100);
	SetTrieString(g_hItemInfoTrie, "8018_attribs", "2 ; 100.0 ; 4 ; 91.0 ; 6 ; 0.25 ; 110 ; 500.0 ; 26 ; 250.0 ; 31 ; 10.0 ; 107 ; 3.0 ; 97 ; 0.4 ; 134 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "8018_ammo", 200);

//PCG cheap Community rocket launcher
	SetTrieString(g_hItemInfoTrie, "7018_classname", "tf_weapon_rocketlauncher");
	SetTrieValue(g_hItemInfoTrie, "7018_index", 18);
	SetTrieValue(g_hItemInfoTrie, "7018_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "7018_quality", 7);
	SetTrieValue(g_hItemInfoTrie, "7018_level", 100);
	SetTrieString(g_hItemInfoTrie, "7018_attribs", "26 ; 500.0 ; 110 ; 500.0 ; 6 ; 0.25 ; 4 ; 200.0 ; 2 ; 100.0 ; 97 ; 0.2 ; 134 ; 4.0");
	SetTrieValue(g_hItemInfoTrie, "7018_ammo", 200);

//derpFaN
	SetTrieString(g_hItemInfoTrie, "8045_classname", "tf_weapon_scattergun");
	SetTrieValue(g_hItemInfoTrie, "8045_index", 45);
	SetTrieValue(g_hItemInfoTrie, "8045_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "8045_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "8045_level", 99);
	SetTrieString(g_hItemInfoTrie, "8045_attribs", "44 ; 1.0 ; 6 ; 0.25 ; 45 ; 2.0 ; 2 ; 10.0 ; 4 ; 100.0 ; 43 ; 1.0 ; 26 ; 500.0 ; 110 ; 500.0 ; 97 ; 0.2 ; 31 ; 10.0 ; 107 ; 3.0 ; 134 ; 4.0");
	SetTrieValue(g_hItemInfoTrie, "8045_ammo", 200);

//Trilby's Rebel Pack - Texas Ten-Shot
	SetTrieString(g_hItemInfoTrie, "2141_classname", "tf_weapon_sentry_revenge");
	SetTrieValue(g_hItemInfoTrie, "2141_index", 141);
	SetTrieValue(g_hItemInfoTrie, "2141_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "2141_quality", 10);
	SetTrieValue(g_hItemInfoTrie, "2141_level", 10);
	SetTrieString(g_hItemInfoTrie, "2141_attribs", "4 ; 1.66 ; 19 ; 0.15 ; 76 ; 1.25 ; 96 ; 1.8 ; 134 ; 3");
	SetTrieValue(g_hItemInfoTrie, "2141_ammo", 40);

//Trilby's Rebel Pack - Texan Love
	SetTrieString(g_hItemInfoTrie, "2161_classname", "tf_weapon_revolver");
	SetTrieValue(g_hItemInfoTrie, "2161_index", 161);
	SetTrieValue(g_hItemInfoTrie, "2161_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "2161_quality", 10);
	SetTrieValue(g_hItemInfoTrie, "2161_level", 10);
	SetTrieString(g_hItemInfoTrie, "2161_attribs", "106 ; 0.65 ; 6 ; 0.80 ; 146 ; 1.0 ; 96 ; 5.0 ; 69 ; 0.80");
	SetTrieValue(g_hItemInfoTrie, "2161_ammo", 24);

//direct hit LaN
	SetTrieString(g_hItemInfoTrie, "2127_classname", "tf_weapon_rocketlauncher_directhit");
	SetTrieValue(g_hItemInfoTrie, "2127_index", 127);
	SetTrieValue(g_hItemInfoTrie, "2127_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "2127_quality", 10);
	SetTrieValue(g_hItemInfoTrie, "2127_level", 1);
	SetTrieString(g_hItemInfoTrie, "2127_attribs", "3 ; 0.5 ; 103 ; 1.8 ; 2 ; 1.25 ; 114 ; 1.0 ; 67 ; 1.1");
	SetTrieValue(g_hItemInfoTrie, "2127_ammo", 20);

//dalokohs bar Effect
	SetTrieString(g_hItemInfoTrie, "2159_classname", "tf_weapon_lunchbox");
	SetTrieValue(g_hItemInfoTrie, "2159_index", 159);
	SetTrieValue(g_hItemInfoTrie, "2159_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "2159_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "2159_level", 1);
	SetTrieString(g_hItemInfoTrie, "2159_attribs", "140 ; 50 ; 139 ; 1");
	SetTrieValue(g_hItemInfoTrie, "2159_ammo", 1);

//The Army of One
	SetTrieString(g_hItemInfoTrie, "2228_classname", "tf_weapon_rocketlauncher");
	SetTrieValue(g_hItemInfoTrie, "2228_index", 228);
	SetTrieValue(g_hItemInfoTrie, "2228_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "2228_quality", 10);
	SetTrieValue(g_hItemInfoTrie, "2228_level", 5);
	SetTrieString(g_hItemInfoTrie, "2228_attribs", "2 ; 5.0 ; 99 ; 3.0 ; 3 ; 0.25 ; 104 ; 0.3 ; 37 ; 0.0");
	SetTrieValue(g_hItemInfoTrie, "2228_ammo", 0);
	SetTrieString(g_hItemInfoTrie, "2228_model", "models/advancedweaponiser/fbomb/c_fbomb.mdl");

//Shotgun for all
	SetTrieString(g_hItemInfoTrie, "2009_classname", "tf_weapon_sentry_revenge");
	SetTrieValue(g_hItemInfoTrie, "2009_index", 141);
	SetTrieValue(g_hItemInfoTrie, "2009_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "2009_quality", 0);
	SetTrieValue(g_hItemInfoTrie, "2009_level", 1);
	SetTrieString(g_hItemInfoTrie, "2009_attribs", "");
	SetTrieValue(g_hItemInfoTrie, "2009_ammo", 32);

//Another weapon by Trilby- Fighter's Falcata
	SetTrieString(g_hItemInfoTrie, "2193_classname", "tf_weapon_club");
	SetTrieValue(g_hItemInfoTrie, "2193_index", 193);
	SetTrieValue(g_hItemInfoTrie, "2193_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "2193_quality", 10);
	SetTrieValue(g_hItemInfoTrie, "2193_level", 5);
	SetTrieString(g_hItemInfoTrie, "2193_attribs", "6 ; 0.8 ; 2 ; 1.1 ; 15 ; 0 ; 98 ; -15");
	SetTrieValue(g_hItemInfoTrie, "2193_ammo", -1);

//Khopesh Climber- MECHA!
	SetTrieString(g_hItemInfoTrie, "2171_classname", "tf_weapon_club");
	SetTrieValue(g_hItemInfoTrie, "2171_index", 171);
	SetTrieValue(g_hItemInfoTrie, "2171_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "2171_quality", 10);
	SetTrieValue(g_hItemInfoTrie, "2171_level", 11);
	SetTrieString(g_hItemInfoTrie, "2171_attribs", "1 ; 0.9 ; 5 ; 1.95");
	SetTrieValue(g_hItemInfoTrie, "2171_ammo", -1);
	SetTrieString(g_hItemInfoTrie, "2171_model", "models/advancedweaponiser/w_sickle_sniper.mdl");
//	SetTrieString(g_hItemInfoTrie, "2171_viewmodel", "models/advancedweaponiser/v_sickle_sniper.mdl");

//Robin's new cheap Rocket Launcher
	SetTrieString(g_hItemInfoTrie, "9205_classname", "tf_weapon_rocketlauncher");
	SetTrieValue(g_hItemInfoTrie, "9205_index", 205);
	SetTrieValue(g_hItemInfoTrie, "9205_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "9205_quality", 8);
	SetTrieValue(g_hItemInfoTrie, "9205_level", 100);
	SetTrieString(g_hItemInfoTrie, "9205_attribs", "2 ; 10100.0 ; 4 ; 1100.0 ; 6 ; 0.25 ; 16 ; 250.0 ; 31 ; 10.0 ; 103 ; 1.5 ; 107 ; 2.0 ; 134 ; 2.0");
	SetTrieValue(g_hItemInfoTrie, "9205_ammo", 200);

//Trilby's Rebel Pack - Rebel's Curse
	SetTrieString(g_hItemInfoTrie, "2197_classname", "tf_weapon_wrench");
	SetTrieValue(g_hItemInfoTrie, "2197_index", 197);
	SetTrieValue(g_hItemInfoTrie, "2197_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "2197_quality", 10);
	SetTrieValue(g_hItemInfoTrie, "2197_level", 13);
	SetTrieString(g_hItemInfoTrie, "2197_attribs", "156 ; 1 ; 2 ; 1.05 ; 107 ; 1.1 ; 62 ; 0.90 ; 64 ; 0.90 ; 125 ; -10 ; 5 ; 1.2 ; 81 ; 0.75");
	SetTrieValue(g_hItemInfoTrie, "2197_ammo", -1);
	SetTrieString(g_hItemInfoTrie, "2197_model", "models/custom/weapons/rebelscurse/c_wrench_v2.mdl");
	SetTrieString(g_hItemInfoTrie, "2197_viewmodel", "models/custom/weapons/rebelscurse/v_wrench_engineer_v2.mdl");

//Jar of Ants
	SetTrieString(g_hItemInfoTrie, "2058_classname", "tf_weapon_jar");
	SetTrieValue(g_hItemInfoTrie, "2058_index", 58);
	SetTrieValue(g_hItemInfoTrie, "2058_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "2058_quality", 10);
	SetTrieValue(g_hItemInfoTrie, "2058_level", 6);
	SetTrieString(g_hItemInfoTrie, "2058_attribs", "149 ; 10.0");
	SetTrieValue(g_hItemInfoTrie, "2058_ammo", 1);

//The Horsemann's Axe
	SetTrieString(g_hItemInfoTrie, "9266_classname", "tf_weapon_sword");
	SetTrieValue(g_hItemInfoTrie, "9266_index", 266);
	SetTrieValue(g_hItemInfoTrie, "9266_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "9266_quality", 5);
	SetTrieValue(g_hItemInfoTrie, "9266_level", 100);
	SetTrieString(g_hItemInfoTrie, "9266_attribs", "15 ; 0 ; 26 ; 600.0 ; 2 ; 999.0 ; 107 ; 4.0 ; 109 ; 0.0 ; 57 ; 50.0 ; 69 ; 0.0 ; 68 ; -1 ; 53 ; 1.0 ; 27 ; 1.0 ; 180 ; -25 ; 219 ; 1.0 ; 134 ; 8.0");
	SetTrieValue(g_hItemInfoTrie, "9266_ammo", -1);

//Goldslinger
	SetTrieString(g_hItemInfoTrie, "5142_classname", "tf_weapon_robot_arm");
	SetTrieValue(g_hItemInfoTrie, "5142_index", 142);
	SetTrieValue(g_hItemInfoTrie, "5142_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "5142_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "5142_level", 25);
	SetTrieString(g_hItemInfoTrie, "5142_attribs", "124 ; 1 ; 26 ; 25.0 ; 15 ; 0 ; 150 ; 1");
	SetTrieValue(g_hItemInfoTrie, "5142_ammo", -1);
	SetTrieString(g_hItemInfoTrie, "5142_model", "models/custom/weapons/goldslinger/engineer_v2.mdl");
	SetTrieString(g_hItemInfoTrie, "5142_viewmodel", "models/custom/weapons/goldslinger/c_engineer_arms.mdl");


//TF2 BETA SECTION, THESE MAY NOT WORK AT ALL
//Quick Fix
	SetTrieString(g_hItemInfoTrie, "186_classname", "tf_weapon_medigun");
	SetTrieValue(g_hItemInfoTrie, "186_index", 29);
	SetTrieValue(g_hItemInfoTrie, "186_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "186_quality", 4);
	SetTrieValue(g_hItemInfoTrie, "186_level", 5);
	SetTrieString(g_hItemInfoTrie, "186_attribs", "144 ; 2.0 ; 8 ; 1.5 ; 18 ; 2.0 ; 10 ; 1.5");
	SetTrieValue(g_hItemInfoTrie, "186_ammo", -1);

//Detonator
	SetTrieString(g_hItemInfoTrie, "351_classname", "tf_weapon_flaregun");
	SetTrieValue(g_hItemInfoTrie, "351_index", 39);
	SetTrieValue(g_hItemInfoTrie, "351_slot", 1);
	SetTrieValue(g_hItemInfoTrie, "351_quality", 4);
	SetTrieValue(g_hItemInfoTrie, "351_level", 10);
	SetTrieString(g_hItemInfoTrie, "351_attribs", "25 ; 0.5 ; 65 ; 1.2 ; 144 ; 1.0");
	SetTrieValue(g_hItemInfoTrie, "351_ammo", 16);

//Beta syringe gun
	SetTrieString(g_hItemInfoTrie, "412_classname", "tf_weapon_syringegun_medic");
	SetTrieValue(g_hItemInfoTrie, "412_index", 17);
	SetTrieValue(g_hItemInfoTrie, "412_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "412_quality", 4);
	SetTrieValue(g_hItemInfoTrie, "412_level", 5);
	SetTrieString(g_hItemInfoTrie, "412_attribs", "144 ; 1.0 ; 5 ; 1.5 ; 1 ; 0.5");
	SetTrieValue(g_hItemInfoTrie, "412_ammo", 150);

//Beta bonesaw
	SetTrieString(g_hItemInfoTrie, "413_classname", "tf_weapon_bonesaw");
	SetTrieValue(g_hItemInfoTrie, "413_index", 8);
	SetTrieValue(g_hItemInfoTrie, "413_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "413_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "413_level", 10);
	SetTrieString(g_hItemInfoTrie, "413_attribs", "144 ; 4.0");
	SetTrieValue(g_hItemInfoTrie, "413_ammo", -1);

//Beta Sniper Club 1
	SetTrieString(g_hItemInfoTrie, "19014_classname", "tf_weapon_club");
	SetTrieValue(g_hItemInfoTrie, "19014_index", 3);
	SetTrieValue(g_hItemInfoTrie, "19014_slot", 2);
	SetTrieValue(g_hItemInfoTrie, "19014_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "19014_level", 5);
	SetTrieString(g_hItemInfoTrie, "19014_attribs", "224 ; 1.25 ; 225 ; 0.75");
	SetTrieValue(g_hItemInfoTrie, "19014_ammo", -1);

//Beta Sniper Rifle 1
	SetTrieString(g_hItemInfoTrie, "19015_classname", "tf_weapon_sniperrifle");
	SetTrieValue(g_hItemInfoTrie, "19015_index", 14);
	SetTrieValue(g_hItemInfoTrie, "19015_slot", 0);
	SetTrieValue(g_hItemInfoTrie, "19015_quality", 6);
	SetTrieValue(g_hItemInfoTrie, "19015_level", 10);
	SetTrieString(g_hItemInfoTrie, "19015_attribs", "222 ; 1.35 ; 223 ; 0.35");
	SetTrieValue(g_hItemInfoTrie, "19015_ammo", 25);
}

PrepareAllModels()
{
	for (new i = 2170; i <= 5142; i++)
	{
		decl String:modelname[PLATFORM_MAX_PATH];
		decl String:formatBuffer[32];
		decl String:modelfile[PLATFORM_MAX_PATH + 4];
		decl String:strLine[PLATFORM_MAX_PATH];
		Format(formatBuffer, sizeof(formatBuffer), "%d_model", i);
		if (GetTrieString(g_hItemInfoTrie, formatBuffer, modelname, sizeof(modelname)))
		{
			Format(modelfile, sizeof(modelfile), "%s.dep", modelname);
			new Handle:hStream = INVALID_HANDLE;
			if (FileExists(modelfile))
			{
				// Open stream, if possible
				hStream = OpenFile(modelfile, "r");
				if (hStream == INVALID_HANDLE) { LogMessage("[TF2Items Randomizer]%d: Error, can't read file containing model dependencies %s", i, modelfile); return; }
				
				while(!IsEndOfFile(hStream))
				{
					// Try to read line. If EOF has been hit, exit.
					ReadFileLine(hStream, strLine, sizeof(strLine));
					
					// Cleanup line
					CleanString(strLine);

					// If file exists...
					if (!FileExists(strLine, true))
					{
						LogMessage("[TF2Items Randomizer + VisWeps]%d: File %s doesn't exist, skipping", i, strLine);
						continue;
					}
					
					// Precache depending on type, and add to download table
					if (StrContains(strLine, ".vmt", false) != -1)		PrecacheDecal(strLine, true);
					else if (StrContains(strLine, ".mdl", false) != -1)	PrecacheModel(strLine, true);
					else if (StrContains(strLine, ".pcf", false) != -1)	PrecacheGeneric(strLine, true);
					LogMessage("[TF2Items Randomizer]%d: Preparing %s", i, strLine);
					AddFileToDownloadsTable(strLine);
				}
				
				// Close file
				CloseHandle(hStream);
			}
			else if (FileExists(modelname) && StrContains(modelname, ".mdl", false) != -1)
			{
				PrecacheModel(modelname, true);
				LogMessage("[TF2Items Randomizer]%d: Preparing %s", i, modelname);
			}
			else LogMessage("[TF2Items Randomizer]%d: cannot find valid model %s, skipping", i, modelname);
		}
		decl String:viewmodelname[128];
		Format(formatBuffer, sizeof(formatBuffer), "%d_viewmodel", i);
		if (GetTrieString(g_hItemInfoTrie, formatBuffer, viewmodelname, sizeof(viewmodelname)))
		{
			Format(modelfile, sizeof(modelfile), "%s.dep", viewmodelname);
			new Handle:hStream = INVALID_HANDLE;
			if (FileExists(modelfile))
			{
				// Open stream, if possible
				hStream = OpenFile(modelfile, "r");
				if (hStream == INVALID_HANDLE) { LogMessage("[TF2Items Randomizer]%d: Error, can't read file containing model dependencies %s", i, modelfile); return; }
				
				while(!IsEndOfFile(hStream))
				{
					// Try to read line. If EOF has been hit, exit.
					ReadFileLine(hStream, strLine, sizeof(strLine));
					
					// Cleanup line
					CleanString(strLine);

					// If file exists...
					if (!FileExists(strLine, true))
					{
						LogMessage("[TF2Items Randomizer]%d: File %s doesn't exist, skipping", i, strLine);
						continue;
					}
					
					// Precache depending on type, and add to download table
					if (StrContains(strLine, ".vmt", false) != -1)		PrecacheDecal(strLine, true);
					else if (StrContains(strLine, ".mdl", false) != -1)	PrecacheModel(strLine, true);
					else if (StrContains(strLine, ".pcf", false) != -1)	PrecacheGeneric(strLine, true);
					LogMessage("[TF2Items Randomizer]%d: Preparing %s", i, strLine);
					AddFileToDownloadsTable(strLine);
				}
				
				// Close file
				CloseHandle(hStream);
			}
			else if (FileExists(viewmodelname) && StrContains(viewmodelname, ".mdl", false) != -1)
			{
				PrecacheModel(viewmodelname, true);
				LogMessage("[TF2Items Randomizer]%d: Preparing %s", i, viewmodelname);
			}
			else LogMessage("[TF2Items Randomizer]%d: cannot find valid model %s, skipping", i, viewmodelname);
		}
	}
}
stock CleanString(String:strBuffer[])
{
	// Cleanup any illegal characters
	new Length = strlen(strBuffer);
	for (new iPos=0; iPos<Length; iPos++)
	{
		switch(strBuffer[iPos])
		{
			case '\r': strBuffer[iPos] = ' ';
			case '\n': strBuffer[iPos] = ' ';
			case '\t': strBuffer[iPos] = ' ';
		}
	}
	
	// Trim string
	TrimString(strBuffer);
}
stock TF2_GetMaxHealth(client)
{
	return SDKCall(hMaxHealth, client);
}

/*stock TF2_SetMaxHealth(client, MaxHealth)
{
	SetEntProp(client, Prop_Data, "m_iMaxHealth", MaxHealth);
}

stock TF2_GetHealth(client)
{
	return GetEntData(client, FindDataMapOffs(client, "m_iHealth"), 4);
}*/

stock TF2_SetHealth(client, NewHealth)
{
	SetEntProp(client, Prop_Send, "m_iHealth", NewHealth, 1);
	SetEntProp(client, Prop_Data, "m_iHealth", NewHealth, 1);
}

public Action:Command_Weapon(client, randomIndex)
{
	decl String:strSteamID[32];
	new weaponLookupIndex = 0;
	weaponLookupIndex = randomIndex;
  
	new weaponSlot;
	new String:formatBuffer[32];
	Format(formatBuffer, 32, "%d_%s", weaponLookupIndex, "slot");
	new bool:isValidItem = GetTrieValue(g_hItemInfoTrie, formatBuffer, weaponSlot);
	
	if (!isValidItem)
	{
		ReplyToCommand(client, "[TF2Items] Invalid Weapon Index");
		return Plugin_Handled;
	}
	
	new weaponIndex;
	while ((weaponIndex = GetPlayerWeaponSlot(client, weaponSlot)) != -1)
	{
		RemovePlayerItem(client, weaponIndex);
		RemoveEdict(weaponIndex);
	}
	
	new Handle:hWeapon = PrepareItemHandle(weaponLookupIndex);
	new entity = TF2Items_GiveNamedItem(client, hWeapon);
	CloseHandle(hWeapon);
	
	if (IsValidEntity(entity))
	{
		switch (weaponLookupIndex)
		{
			case 2041: SetEntProp(entity, Prop_Send, "m_nSkin", 0, 1);
			case 2171:
			{
				SetEntProp(entity, Prop_Send, "m_iEntityLevel", -117);
				GetClientAuthString(client, strSteamID, sizeof(strSteamID));
				if (StrEqual(strSteamID, "STEAM_0:0:17402999") || StrEqual(strSteamID, "STEAM_0:1:35496121")) SetEntProp(entity, Prop_Send, "m_iEntityQuality", 9); //Mecha the Slag's Self-Made Khopesh Climber
			}
			case 2197:
			{
				SetEntProp(entity, Prop_Send, "m_iEntityLevel", 128+13);
/*				SetEntityRenderFx(entity, RENDERFX_PULSE_SLOW);
				SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
				SetEntityRenderColor(entity, 120, 10, 255, 205);*/
				if (GetEntData(client, FindDataMapOffs(client, "m_iAmmo") + (3 * 4), 4) > 150)
					SetEntData(client, FindDataMapOffs(client, "m_iAmmo") + (3 * 4), 150, 4);
			}
/*			case 215:
			{
				if (TF2_GetPlayerClass(client) == TFClass_Medic) //Medic with Degreaser: fix for screen-blocking
				{
					SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
					SetEntityRenderColor(entity, 255, 255, 255, 75);
				}
			}*/
			case 35:
			{
				new TFClassType:class = TF2_GetPlayerClass(client);
				if (class == TFClass_Sniper || class == TFClass_Engineer) //Sniper or Engineer with Kritzkrieg: fix for screen-blocking
				{
					SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
					SetEntityRenderColor(entity, 255, 255, 255, 75);
				}
			}
			case 2058:
			{
				SetEntProp(entity, Prop_Send, "m_iEntityLevel", -122);
/*				GetClientAuthString(client, strSteamID, sizeof(strSteamID));
				if (StrEqual(strSteamID, "STEAM_0:1:19100391", false)) SetEntProp(entity, Prop_Send, "m_iEntityQuality", 9); //FlaminSarge's Self-Made Jar of Ants*/
			}
			case 142:
			{
				if (TF2_GetPlayerClass(client) == TFClass_Engineer)
				{
					new flags = GetEntProp(client, Prop_Send, "m_nBody");
					if (!(flags & (1 << 1)))
					{
						flags |= (1 << 1);
						SetEntProp(client, Prop_Send, "m_nBody", flags);
					}
				}
			}
			case 45:
			{
				if (TF2_GetPlayerClass(client) == TFClass_Sniper)
				{
					SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
					SetEntityRenderColor(entity, 255, 255, 255, 75);
				}
			}
			case 8045:
			{
				if (TF2_GetPlayerClass(client) == TFClass_Sniper)
				{
					SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
					SetEntityRenderColor(entity, 255, 255, 255, 75);
				}
			}
			case 9266:
			{
				new model = PrecacheModel("models/weapons/c_models/c_bigaxe/c_bigaxe.mdl");
				SetEntProp(entity, Prop_Send, "m_iWorldModelIndex", model);
			}
			case 5142:
			{
				SetEntProp(entity, Prop_Send, "m_iEntityLevel", -103);
				if (TF2_GetPlayerClass(client) == TFClass_Engineer)
				{
					new flags = GetEntProp(client, Prop_Send, "m_nBody");
					if (!(flags & (1 << 1)))
					{
						flags |= (1 << 1);
						SetEntProp(client, Prop_Send, "m_nBody", flags);
					}
				}
			}
		}

		decl String:classname[32];
		new bool:wearablewep = false;
		Format(formatBuffer, sizeof(formatBuffer), "%d_%s", weaponLookupIndex, "classname");
		GetTrieString(g_hItemInfoTrie, formatBuffer, classname, sizeof(classname));
/*		decl String:viewmodel[128];
		Format(formatBuffer, sizeof(formatBuffer), "%d_%s", weaponLookupIndex, "viewmodel");
		if (GetTrieString(g_hItemInfoTrie, formatBuffer, viewmodel, sizeof(viewmodel)) && FileExists(viewmodel))
		{
			new model = PrecacheModel(viewmodel);
			SetEntProp(entity, Prop_Send, "m_nModelIndex", model);
			SetEntProp(entity, Prop_Send, "m_iViewModelIndex", model);
			ChangeEdictState(entity, FindDataMapOffs(entity, "m_nModelIndex"));
		}*/
		decl String:worldmodel[128];
		Format(formatBuffer, sizeof(formatBuffer), "%d_%s", weaponLookupIndex, "model");
		if (GetTrieString(g_hItemInfoTrie, formatBuffer, worldmodel, sizeof(worldmodel)) && FileExists(worldmodel) && weaponLookupIndex != 169)
		{
			new model = PrecacheModel(worldmodel);
			if (StrContains(classname, "wearable", false) == -1) SetEntProp(entity, Prop_Send, "m_iWorldModelIndex", model);
			else SetEntityModel(entity, worldmodel);	//SetEntProp(entity, Prop_Send, "m_nModelIndex", model);
			if (weaponLookupIndex == 5142)
			{
				if (TF2_GetPlayerClass(client) == TFClass_Engineer)
				{
					new flags = GetEntProp(client, Prop_Send, "m_nBody");
					if (IsModelPrecached(worldmodel))
					{
						SetVariantString(worldmodel);
						AcceptEntityInput(client, "SetCustomModel");
						SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
					}
					flags |= (1 << 1);
					SetEntProp(client, Prop_Send, "m_nBody", flags);
				}
			}
		}
		if (StrContains(classname, "wearable", false) != -1)
		{
			TF2_EquipWearable(client, entity);
			wearablewep = true;
			if (weaponLookupIndex == 131)
			{
				decl String:attachment[32];
				new TFClassType:class = TF2_GetPlayerClass(client);
				switch (class)
				{
					case TFClass_Scout: strcopy(attachment, sizeof(attachment), "hand_L");
					case TFClass_Pyro, TFClass_Soldier: strcopy(attachment, sizeof(attachment), "weapon_bone_L");
					case TFClass_Engineer: strcopy(attachment, sizeof(attachment), "exhaust");
					default: strcopy(attachment, sizeof(attachment), "");
				}
				if (attachment[0] != '\0')
				{
					SetVariantString(attachment);
					AcceptEntityInput(entity, "SetParentAttachment");
				}
			}
		}
		else EquipPlayerWeapon(client, entity);

		new weaponAmmo;
		Format(formatBuffer, sizeof(formatBuffer), "%d_%s", weaponLookupIndex, "ammo");
		GetTrieValue(g_hItemInfoTrie, formatBuffer, weaponAmmo);

		if (weaponAmmo != -1)
		{
			SetSpeshulAmmo(client, weaponSlot, weaponAmmo);
		}
#if defined _visweps_included_
		if (visibleweapons)
		{
			decl String:indexmodel[128];
			new index = weaponLookupIndex;
			Format(formatBuffer, sizeof(formatBuffer), "%d_%s", index, "model");
			if (GetTrieString(g_hItemInfoTrie, formatBuffer, indexmodel, sizeof(indexmodel)) && (IsModelPrecached(indexmodel) || strcmp(indexmodel, "-1", false) == 0))
			{
				if (wearablewep) weaponSlot = 6;
				VisWep_GiveWeapon(client, weaponSlot, indexmodel, _, (weaponSlot == 1));
//				LogMessage("Setting Wep Model to %s", indexmodel);
			}
			else
			{
				if (wearablewep) weaponSlot = 6;
				new index2;
				Format(formatBuffer, sizeof(formatBuffer), "%d_%s", index, "index");
				GetTrieValue(g_hItemInfoTrie, formatBuffer, index2);
//				if (index2 == 193) index2 = 3;
//				if (index2 == 205) index2 = 18;
				if (index == 2041 && index2 == 41) index2 = 2041;
				if (index == 2009 && index2 == 141) index2 = 9;
				if (index == 9266 && index2 == 266) index2 = 9266;
				IntToString(index2, indexmodel, sizeof(indexmodel));
				VisWep_GiveWeapon(client, weaponSlot, indexmodel, _, (weaponSlot == 1));
//				LogMessage("Setting Wep Model to %s", indexmodel);
			}
		}
#endif
	}
	else
	{
		PrintToChat(client, "[TF2Items] Error giving one of your weapons D:");
	}
	return Plugin_Handled;
}

public Action:Command_Reroll(client, args)
{
	new String:arg1[32];
	if (args != 1 && args != 0)
	{
		ReplyToCommand(client, "[TF2Items] Usage: tf2items_rnd_reroll <target> or sm_reroll");
		return Plugin_Handled;
	}
	if (args == 1)
	{
		/* Get the arguments */
		GetCmdArg(1, arg1, sizeof(arg1));
	}
	else if (args == 0) arg1 = "@me"; // If no args, set arg1 to @me
	
	/**
	 * target_name - stores the noun identifying the target(s)
	 * target_list - array to store clients
	 * target_count - variable to store number of clients
	 * tn_is_ml - stores whether the noun must be translated
	 */
	new String:target_name[MAX_TARGET_LENGTH];
	new target_list[MAXPLAYERS], target_count;
	new bool:tn_is_ml;
 
	if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			MAXPLAYERS,
			0,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		/* This function replies to the admin with a failure message */
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
 
	for (new i = 0; i < target_count; i++)
	{
		if(cvar_enabled)
		{
			if(IsClientInGame(target_list[i]))
			{
				SetRandomization(target_list[i]);
				if (IsPlayerAlive(target_list[i]))
				{
					TF2_RespawnPlayer(target_list[i]);
				}
			}
		}
		LogAction(client, target_list[i], "\"%L\" rerolled \"%L\"", client, target_list[i]);
	} 
	return Plugin_Handled;
}

public Action:TF2_CalcIsAttackCritical(client, weapon, String:weaponname[], &bool:result)
{
	new secondary = GetPlayerWeaponSlot(client, 1);
	if (secondary != -1 && GetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex") == 311 && TF2_GetPlayerClass(client) == TFClass_Heavy && (TF2_GetPlayerConditionFlags(client) & TF_CONDFLAG_CRITCOLA))
	{
		if (!(StrEqual(weaponname, "tf_weapon_wrench")
			|| StrEqual(weaponname, "tf_weapon_shovel")
			|| StrEqual(weaponname, "tf_weapon_bottle")
			|| StrEqual(weaponname, "tf_weapon_fists")
			|| StrEqual(weaponname, "tf_weapon_bat")
			|| StrEqual(weaponname, "tf_weapon_bonesaw")
			|| StrEqual(weaponname, "tf_weapon_sword")
			|| StrEqual(weaponname, "tf_weapon_fireaxe")
			|| StrEqual(weaponname, "tf_weapon_robot_arm")
			|| StrEqual(weaponname, "tf_weapon_bat_wood")
			|| StrEqual(weaponname, "tf_weapon_club")
			|| StrEqual(weaponname, "tf_weapon_bat_fish")
			|| StrEqual(weaponname, "tf_weapon_stickbomb")
			|| StrEqual(weaponname, "tf_weapon_knife")
			|| StrEqual(weaponname, "tf_weapon_katana")))
		{
			if (strcmp(weaponname, "tf_weapon_minigun", false) == 0)
			{
				SetEntProp(weapon, Prop_Send, "m_iWeaponState", 0);
				TF2_RemoveCondition(client, TFCond_Slowed);
			}
			new melee = GetPlayerWeaponSlot(client, 2);
			if (melee && IsValidEntity(melee)) SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", melee);
		}
	}
	if (cvar_fixspy && TF2_GetPlayerClass(client) == TFClass_Spy && (TF2_GetPlayerConditionFlags(client) & (TF_CONDFLAG_DISGUISING | TF_CONDFLAG_DISGUISED)))
	{
		if (StrEqual(weaponname, "tf_weapon_flamethrower")
			|| StrEqual(weaponname, "tf_weapon_grenadelauncher")
			|| StrEqual(weaponname, "tf_weapon_pipebomblauncher")
			|| StrEqual(weaponname, "tf_weapon_wrench")
			|| StrEqual(weaponname, "tf_weapon_shovel")
			|| StrEqual(weaponname, "tf_weapon_bottle")
			|| StrEqual(weaponname, "tf_weapon_fists")
			|| StrEqual(weaponname, "tf_weapon_bat")
			|| StrEqual(weaponname, "tf_weapon_bonesaw")
			|| StrEqual(weaponname, "tf_weapon_sword")
			|| StrEqual(weaponname, "tf_weapon_fireaxe")
			|| StrEqual(weaponname, "tf_weapon_robot_arm")
			|| StrEqual(weaponname, "tf_weapon_bat_wood")
			|| StrEqual(weaponname, "tf_weapon_club")
			|| StrEqual(weaponname, "tf_weapon_compound_bow")
			|| StrEqual(weaponname, "tf_weapon_bat_fish")
			|| StrEqual(weaponname, "tf_weapon_stickbomb")
			|| StrEqual(weaponname, "tf_weapon_katana")) TF2_RemovePlayerDisguise(client);
	}
	if (!tf2items_giveweapon && StrEqual(weaponname, "tf_weapon_club") && GetEntProp(weapon, Prop_Send, "m_iEntityLevel") == -117 && GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 171)
	{
		SickleClimbWalls(client);
	}
}

public SickleClimbWalls(client)
{
	if (!IsValidClient(client)) return;
//	if (GetPlayerClass(client) != 7) return;
//	if (!(g_iSpecialAttributes[client] & attribute_climbwalls)) return;

	decl String:classname[64];
	decl Float:vecClientEyePos[3];
	decl Float:vecClientEyeAng[3];
	GetClientEyePosition(client, vecClientEyePos);	 // Get the position of the player's eyes
	GetClientEyeAngles(client, vecClientEyeAng);	   // Get the angle the player is looking

	//Check for colliding entities
	TR_TraceRayFilter(vecClientEyePos, vecClientEyeAng, MASK_PLAYERSOLID, RayType_Infinite, TraceRayDontHitSelf, client);

	if (!TR_DidHit(INVALID_HANDLE)) return;
	
	new TRIndex = TR_GetEntityIndex(INVALID_HANDLE);
	GetEdictClassname(TRIndex, classname, sizeof(classname));
	if (!StrEqual(classname, "worldspawn")) return;
	
	decl Float:fNormal[3];
	TR_GetPlaneNormal(INVALID_HANDLE, fNormal);
	GetVectorAngles(fNormal, fNormal);
	
	//PrintToChatAll("Normal: %f", fNormal[0]);
	
	if (fNormal[0] >= 30.0 && fNormal[0] <= 330.0) return;
	if (fNormal[0] <= -30.0) return;

	decl Float:pos[3];
	TR_GetEndPosition(pos);
	new Float:distance = GetVectorDistance(vecClientEyePos, pos);
	
	//PrintToChatAll("Distance: %f", distance);
	if (distance >= 100.0) return;
	
	new Float:fVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);
	fVelocity[2] = 600.0;
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fVelocity);
	ClientCommand(client, "playgamesound \"%s\"", "player\\taunt_clip_spin.wav");
}

public bool:TraceRayDontHitSelf(entity, mask, any:data)
{
	return (entity != data);
}
stock bool:IsValidClient(client)
{
	if (client <= 0) return false;
	if (client > MaxClients) return false;
	if (!IsClientConnected(client)) return false;
	return IsClientInGame(client);
}
stock RemovePlayerBack(client)
{
	new edict = MaxClients+1;
	while((edict = FindEntityByClassname2(edict, "tf_wearable")) != -1)
	{
		decl String:netclass[32];
		if (GetEntityNetClass(edict, netclass, sizeof(netclass)) && StrEqual(netclass, "CTFWearable"))
		{
			new idx = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
			if ((idx == 57 || idx == 133 || idx == 231) && GetEntPropEnt(edict, Prop_Send, "m_hOwnerEntity") == client && !GetEntProp(edict, Prop_Send, "m_bDisguiseWearable"))
			{
				if (setwep[client][1] != 0)
				{	
					RemoveEdict(edict);
				}
			}
		}
	}
}
stock RemovePlayerTarge(client)
{
	new edict = MaxClients+1;
	while((edict = FindEntityByClassname2(edict, "tf_wearable_demoshield")) != -1)
	{
		new idx = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
		if (idx == 131 && GetEntPropEnt(edict, Prop_Send, "m_hOwnerEntity") == client && !GetEntProp(edict, Prop_Send, "m_bDisguiseWearable"))
		{
			if (setwep[client][1] != 0)
			{
				RemoveEdict(edict);
			}
		}
	}
}

public Action:OnGetGameDescription(String:gameDesc[64])
{
	if (cvar_enabled && cvar_gamedesc && (g_bMapLoaded || !cvar_manifix))
	{
		decl String:g_szGameDesc[64];
		Format(g_szGameDesc, 64, "%s v%s", "[TF2Items]Randomizer", PLUGIN_VERSION);
		strcopy(gameDesc, sizeof(gameDesc), g_szGameDesc);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}
stock FindEntityByClassname2(startEnt, const String:classname[])
{
	/* If startEnt isn't valid shifting it back to the nearest valid one */
	while (startEnt > -1 && !IsValidEntity(startEnt)) startEnt--;
	return FindEntityByClassname(startEnt, classname);
}

//will eventually make this fixreload
/*stock SetNextAttack(client, Float:duration = 0.0)
{
    new Float:nextAttack = GetGameTime() + duration;
    new offset = FindSendPropInfo("CBasePlayer", "m_hMyWeapons"); //weapon = GetPlayerWeaponSlot(client, 0)
    for(new i = 0; i < 48; i++) //48?
    {
        new weapon = GetEntDataEnt2(client, offset);
        if (weapon > 0 && IsValidEdict(weapon))
        {
            SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", nextAttack);
            SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", nextAttack);
        }
        offset += 4;
    }
}*/
stock TF2_SdkStartup()
{
	new Handle:hGameConf = LoadGameConfigFile("tf2items.randomizer");
	if (hGameConf != INVALID_HANDLE)
	{
		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "EquipWearable");
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
		g_hSdkEquipWearable = EndPrepSDKCall();
		
/*		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hGameConf,SDKConf_Virtual,"RemoveWearable");
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
		g_hSdkRemoveWearable = EndPrepSDKCall();*/
		
		CloseHandle(hGameConf);
		g_bSdkStarted = true;
	} else {
		SetFailState("Couldn't load SDK Wearable functions (Randomizer). Make sure tf2items.randomizer.txt is in your gamedata folder!");
	}
}
stock TF2_EquipWearable(client, entity)
{
	if (g_bSdkStarted == false) TF2_SdkStartup();
	
	if (TF2_IsEntityWearable(entity)) SDKCall(g_hSdkEquipWearable, client, entity);
	else							 LogMessage("Error: Item %i isn't a valid wearable.", entity);
}
stock bool:TF2_IsEntityWearable(entity)
{
	if ((entity > 0) && IsValidEdict(entity))
	{
		new String:strClassname[32]; GetEdictClassname(entity, strClassname, sizeof(strClassname));
		return (StrEqual(strClassname, "tf_wearable", false) || StrEqual(strClassname, "tf_wearable_demoshield", false));
	}
	
	return false;
}
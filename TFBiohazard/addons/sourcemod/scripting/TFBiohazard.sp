/*
  _______ ______     ____  _       _                            _ 
 |__   __|  ____|_  |  _ \(_)     | |                          | |
    | |  | |__  |_| | |_) |_  ___ | |__   __ _ ______ _ _ __ __| |
    | |  |  __|     |  _ <| |/ _ \| '_ \ / _` |_  / _` | '__/ _` |
    | |  | |     _  | |_) | | (_) | | | | (_| |/ / (_| | | | (_| |
    |_|  |_|    |_| |____/|_|\___/|_| |_|\__,_/___\__,_|_|  \__,_|
    
    [X6] Herbius, first created 16th April 2012
*/

#include <sourcemod>
#include <tf2>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>
#include <tf2items>

#include "playerdata"
#include "plugininfo"

#pragma semicolon 1

#define DEVELOPER           0
#define LIFESTATE_PROP      "m_lifeState"
#define TFBH_CPM            "tfbh_cp_master"
#define TFBH_ROUND_TIMER    "tfbh_round_timer"

// State flags
// Control what aspects of the plugin will run.
#define STATE_DISABLED      16  // Plugin is disabled via convar. No gameplay-modifying activity will occur.
#define STATE_FEW_PLAYERS   8   // There are not enough players to begin a game.
#define STATE_NOT_IN_ROUND  4   // Round has ended or has not yet begun.
#define STATE_AWAITING      1   // A round has started and the Blue team is empty because no-one has yet become a zombie.

// Debug flags
// Used with tfbh_debug to display debug messages to the server console.
#define DEBUG_GENERAL       (1 << 0)    // General debugging. 1
#define DEBUG_TEAMCHANGE    (1 << 1)    // Debugging team changes. 2
#define DEBUG_HEALTH        (1 << 2)    // Debugging health calculations. 4
#define DEBUG_DAMAGE        (1 << 3)    // Debugging OnTakeDamage hook. 8
#define DEBUG_DATA          (1 << 4)    // Debugging data arrays. 16
#define DEBUG_CRASHES       (1 << 5)    // Debugging crashes. NOTE: These are probably caused by an outdated SM, so check the latest branch first. 32
#define DEBUG_ZOMBIFY       (1 << 6)    // Debugging creation of zombies. 64
#define DEBUG_RAGE          (1 << 7)    // Debugging zombie rage. 128
#define DEBUG_HEALTHPACKS   (1 << 8)    // Debugging zombie health pack touches. 256
#define DEBUG_ROUNDTIMER    (1 << 9)    // Debugging setting round/setup time. 512

// Cleanup flags
// Pass one of these to Cleanup() to specify what to clean up.
// This is mainly to keep things tidy and avoid doing these operations
// all over the code.
#define CLEANUP_ROUNDEND    1
#define CLEANUP_FIRSTSTART  2
#define CLEANUP_ENDALL      3
#define CLEANUP_ROUNDSTART  4
#define CLEANUP_MAPSTART    5
#define CLEANUP_MAPEND      6

// Team integers
// Used with ChangeClientTeam() etc.
// I know there are proper enums but I got used to using this way and it works.
#define TEAM_INVALID        -1
#define TEAM_UNASSIGNED     0
#define TEAM_SPECTATOR      1
#define TEAM_RED            2
#define TEAM_BLUE           3

// Building destroy flags
#define BUILD_SENTRY        4
#define BUILD_DISPENSER     2
#define BUILD_TELEPORTER    1

// Weapon slots
#define SLOT_PRIMARY        0
#define SLOT_SECONDARY      1
#define SLOT_MELEE          2
#define SLOT_BUILD          3
#define SLOT_DESTROY        4
#define SLOT_FIVE           5   // Builder entity that allows building from the console - will probably need to remove this too!

// Change the following to specify what the plugin should change the balancing CVars to. Must be integers.
#define DES_UNBALANCE       0   // Desired value for mp_teams_unbalance_limit
#define DES_AUTOBALANCE     0   // Desired value for mp_autoteambalance
#define DES_SCRAMBLE        0   // Desired value for mp_scrambleteams_auto
#define DES_STALEMATE       0   // Desired value for mp_stalemate_enable

// Convenient weapon attributes:
#define UBER_ON_HIT         17
#define HEALTH_ON_HIT       16
#define HEALTH_REGEN        57
#define LUNCHBOX_MINICRITS  144
#define DECREASED_DAMAGE    1
#define HEALING_BOLTS       199
#define REDUCE_PRI_AMMO     77
#define DECREASED_RELOAD    97

#define STANDARD_GREEN      148, 197, 143, 255

// Weapon attribute strings
new const String:defWrench[]        = "292 ; 3.0 ; 293 ; 0.0 ; 287 ; 2.0";
new const String:defGoldenWrench[]  = "150 ; 1.0 ; 153 ; 1.0 ; 287 ; 2.0";
new const String:defGunslinger[]    = "124 ; 1.0 ; 26 ; 25.0 ; 15 ; 0.0 ; 292 ; 3.0 ; 293 ; 0.0 ; 287 ; 2.0";
new const String:defSouthHosp[]     = "15 ; 0.0 ; 149 ; 5.0 ; 61 ; 1.2 ; 287 ; 2.0";
new const String:defJag[]           = "92 ; 1.3 ; 1 ; 0.75 ; 292 ; 3.0 ; 293 ; 0.0 ; 287 ; 2.0";
new const String:defEurekaEffect[]  = "352 ; 1.0 ; 353 ; 1.0 ; 287 ; 2.0";
new const String:defSniperRifle[]   = "395 ; 1";

new g_PluginState;                          // Holds the global state of the plugin.
new g_Disconnect;                           // Sidesteps team count issues by tracking the index of a disconnecting player. See Event_TeamsChange.
new bool:b_AllowChange;                     // If true, team changes will not be blocked.
new bool:b_Setup;                           // If true, PluginStart has already run. This avoids double loading from OnMapStart when plugin is loaded during a game.
new g_GameRules = INVALID_ENT_REFERENCE;    // Index of a tf_gamerules entity.
new g_NextJarate = 0;                       // If this is set, the next Jarate projectile to be created will have its owner set to the player of this user ID.
new g_RoundTimer = INVALID_ENT_REFERENCE;

// ConVars
new Handle:cv_PluginEnabled = INVALID_HANDLE;       // Enables or disables the plugin.
new Handle:cv_Debug = INVALID_HANDLE;               // Enables or disables debugging using debug flags.
new Handle:cv_DebugRage = INVALID_HANDLE;           // If 1, enables rage charging rate output.
new Handle:cv_Pushback = INVALID_HANDLE;            // General multiplier for zombie pushback.
new Handle:cv_SentryPushback = INVALID_HANDLE;      // Multiplier for sentry pushback.
new Handle:cv_ZHMin = INVALID_HANDLE;               // Minimum zombie health multiplier when against number of players specified in tfbh_zhscale_minplayers.
new Handle:cv_ZHMinPlayers = INVALID_HANDLE;        // When players are <= this value, zombies will be given minimum health.
new Handle:cv_ZHMax = INVALID_HANDLE;               // Maximum zombie health multiplier when against number of players specified in tfbh_zhscale_maxplayers.
new Handle:cv_ZHMaxPlayers = INVALID_HANDLE;        // When players are >= this value, zombies will be given maximum health.
new Handle:cv_ZombieRatio = INVALID_HANDLE;         // At the beginning of a round, the number of zombies that spawn is the quotient of (Red players/this value), rounded up.
new Handle:cv_ZRespawnMin = INVALID_HANDLE;         // Minimum respawn time for zombies, when all survivors are alive.
new Handle:cv_ZRespawnMax = INVALID_HANDLE;         // Maximum respawn time for zombies, when one survivor is left alive.
new Handle:cv_ZRageChargeClose = INVALID_HANDLE;    // The max percentage rate at which a zombie's rage will charge every second when they are close to Red players.
new Handle:cv_ZRageChargeFar = INVALID_HANDLE;      // The min percentage rate at which a zombie's rage will charge every second when they are far from Red players.
new Handle:cv_ZRageCloseDist = INVALID_HANDLE;      // 'Close' distance to Red players, when zombie rage will charge fastest.
new Handle:cv_ZRageFarDist = INVALID_HANDLE;        // 'Far' distance from Red players, when zombie rage will charge slowest.
new Handle:cv_ZRageDuration = INVALID_HANDLE;       // How long a zombie's rage lasts, in seconds.
//new Handle:cv_ZRageRadius = INVALID_HANDLE;       // The radius within which other zombies will be granted mini-crits when a zombie rages.
new Handle:cv_ZRageStunRadius = INVALID_HANDLE;     // The radius within which players and sentries will be stunned when a zombie rages.
new Handle:cv_ZRageStunDuration = INVALID_HANDLE;   // Duration to stun players when a zombie rages. Sentries remain stunned for an extra two seconds.
new Handle:cv_AlwaysZombify = INVALID_HANDLE;       // If 0, suicides will not make Red players turn into zombies. If 1, all deaths result in zombification.
new Handle:cv_SuperJumpForce = INVALID_HANDLE;      // Force to apply when a zombie super-jumps.
new Handle:cv_WetRagePenalty = INVALID_HANDLE;      // Penalty to apply per second to a zombie's rage when they are Jarate'd or milked.
new Handle:cv_JarateKnockForce = INVALID_HANDLE;    // Force with which to push players when a zombie Jarate jar explodes.
new Handle:cv_RedJarateKnock = INVALID_HANDLE;      // Whether survivor Jarate also pushes zombies.
new Handle:cv_UberOnHit = INVALID_HANDLE;           // How much uber a Medic is given per syringe hit.
new Handle:cv_UberOnBolt = INVALID_HANDLE;          // How much uber a Medic is given per crossbow bolt hit.
new Handle:cv_RespawnInSetup = INVALID_HANDLE;      // If >= 0, specified the delay after which a player who dies in setup will be respawned. If < 0, player is respawned only when setup time finishes.
new Handle:cv_TeleChargePerSec = INVALID_HANDLE;    // How fast a zombie Engineer's teleport ability should charge, in points per second.
new Handle:cv_SetupTime = INVALID_HANDLE;           // Amount of setup time given to survivors before players are zombified.
new Handle:cv_RoundTime = INVALID_HANDLE;           // Amount of time Red players must survive before they win the round.

// DHooks
new Handle:hDamageHook = INVALID_HANDLE;            // SDKHook's OnTakeDamage reports damage values before TF2 applies spread. Hence, we have to manually hook OnTakeDamage_Alive.

// Timers
new Handle:timer_ZRefresh = INVALID_HANDLE;         // Timer to refresh zombie health.
new Handle:timer_Cond = INVALID_HANDLE;             // Timer to refresh zombie conditions.

 // HUD syncs
new Handle:hs_ZText = INVALID_HANDLE;               // HUD sync for showing zombie info text.

// Stock ConVars and values.
// We keep track of the server's values for these ConVars when the plugin is loaded but not active.
// When they change, we update their values in the variables below.
// When the plugin is active, we set all of the ConVars to 0 (because team balancing will get in the way).
// If the plugin is unloaded, we can then set the ConVars back to the values they were before we loaded.
new Handle:cv_Unbalance = INVALID_HANDLE;           // Handle to mp_teams_unbalance_limit.
new Handle:cv_Autobalance = INVALID_HANDLE;         // Handle to mp_autoteambalance.
new Handle:cv_Scramble = INVALID_HANDLE;            // Handle to mp_scrambleteams_auto.
new Handle:cv_Stalemate = INVALID_HANDLE;           // Handle to mp_stalemate_enable.
new cvdef_Unbalance;                                // Original value of mp_teams_unbalance_limit.
new cvdef_Autobalance;                              // Original value of mp_autoteambalance.
new cvdef_Scramble;                                 // Original value of mp_scrambleteams_auto.
new cvdef_Stalemate;                                // Original value of mp_stalemate_enable.

// DHook offsets
// When hooking OnTakeDamage_Alive, the one parameter passed is a CDamageInfo struct,
// within which we need to know the offsets of the different variables.
// When the plugin starts, the offsets inside the struct are read from the gamedata and stored.
new ofAttacker;
new ofInflictor;
new ofDamage;
//new ofDamageType;
new ofWeapon;
new ofDamageForce;
new ofDamagePosition;
new ofDamageCustom;

public OnPluginStart()
{
    LogMessage("== %s v%s ==", PLUGIN_NAME, PLUGIN_VERSION);
    
    LogMessage("Checking for dependencies...");
    
    if ( !LibraryExists("TF2Items") )
    {
        SetFailState("Critical extension 'TF2Items' not found, plugin terminated.");
    }
    else if ( !LibraryExists("sdkhooks") )
    {
        SetFailState("Critical extension 'sdkhooks' not found, plugin terminated.");
    }
    else if ( !LibraryExists("dhooks") )
    {
        SetFailState("Critical extension 'dhooks' not found, plugin terminated.");
    }
    else LogMessage("All required dependencies installed.");
    
    LoadTranslations("TFBiohazard/TFBiohazard_phrases");
    LoadTranslations("common.phrases");
    AutoExecConfig(true, "TFBiohazard", "sourcemod/TFBiohazard");
    Precache();
    
    // Plugin version convar
    CreateConVar("tfbh_version", PLUGIN_VERSION, "Plugin version.", FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_DONTRECORD);
    
    // ConVars
    cv_PluginEnabled  = CreateConVar("tfbh_enabled",
                                        "1",
                                        "Enables or disables the plugin.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0,
                                        true,
                                        1.0);

    cv_Debug  = CreateConVar("tfbh_debug",
                                        "0",
                                        "Enables or disables debugging using debug flags.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_DONTRECORD,
                                        true,
                                        0.0);
    
    cv_DebugRage  = CreateConVar("tfbh_debug_rage",
                                        "0",
                                        "If 1, enables rage charging rate output.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_DONTRECORD,
                                        true,
                                        0.0,
                                        true,
                                        1.0);
    
    cv_Pushback = CreateConVar("tfbh_pushback_scale",
                                        "2.0",
                                        "General multiplier for zombie pushback.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0);
    
    cv_SentryPushback = CreateConVar("tfbh_sentry_pushback_scale",
                                        "0.5",
                                        "Multiplier for sentry pushback.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0);
    
    cv_ZHMin = CreateConVar("tfbh_zhscale_min",
                                        "1.0",
                                        "Minimum zombie health multiplier when against number of players specified in tfbh_zhscale_minplayercount.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.1);
    
    cv_ZHMinPlayers = CreateConVar("tfbh_zhscale_minplayercount",
                                        "1",
                                        "When player count is <= this value, zombies will be given minimum health.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        1.0);
    
    cv_ZHMax = CreateConVar("tfbh_zhscale_max",
                                        "16.0",
                                        "Maximum zombie health multiplier when against number of players specified in tfbh_zhscale_maxplayercount.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.1);
    
    cv_ZHMaxPlayers = CreateConVar("tfbh_zhscale_maxplayercount",
                                        "24",
                                        "When player count is >= this value, zombies will be given maximum health.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        1.0);
                                        
    cv_ZombieRatio = CreateConVar("tfbh_zombie_player_ratio",
                                        "7",
                                        "At the beginning of a round, the number of zombies that spawn is (Red players/this value), rounded up.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        1.0);
    
    cv_ZRespawnMin = CreateConVar("tfbh_zrespawn_min",
                                        "1",
                                        "Minimum respawn time for zombies, when all survivors are alive.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0);
    
    cv_ZRespawnMax = CreateConVar("tfbh_zrespawn_max",
                                        "6",
                                        "Maximum respawn time for zombies, when one survivor is left alive.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0);
    
    cv_ZRageChargeClose = CreateConVar("tfbh_zrage_maxrate",
                                        "6.0",
                                        "The max percentage rate at which a zombie's rage will charge every second when they are close to Red players.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0,
                                        true,
                                        100.0);
    
    cv_ZRageChargeFar = CreateConVar("tfbh_zrage_minrate",
                                        "0.5",
                                        "The min percentage rate at which a zombie's rage will charge every second when they are far from Red players.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0,
                                        true,
                                        100.0);
    
    cv_ZRageCloseDist = CreateConVar("tfbh_zrage_close",
                                        "128",
                                        "'Close' distance to Red players, when zombie rage will charge fastest.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0);
    
    cv_ZRageFarDist = CreateConVar("tfbh_zrage_far",
                                        "1024",
                                        "'Far' distance to Red players, when zombie rage will charge slowest.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0);
    
    cv_ZRageDuration = CreateConVar("tfbh_zrage_duration",
                                        "3",
                                        "How long a zombie's rage lasts, in seconds.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.5);
    
    /*cv_ZRageRadius = CreateConVar("tfbh_zrage_radius",
                                        "380",
                                        "The radius within which other zombies will be granted mini-crits when a zombie rages.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        8.0);*/
    
    cv_ZRageStunRadius = CreateConVar("tfbh_zrage_radius",
                                        "350",
                                        "The radius within which players and sentries will be stunned when a zombie rages.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        8.0);
    
    cv_ZRageStunDuration = CreateConVar("tfbh_zrage_stunduration",
                                        "3",
                                        "Duration to stun players when a zombie rages.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0);
    
    cv_AlwaysZombify = CreateConVar("tfbh_always_zombify",
                                        "1",
                                        "If 0, suicides will not make Red players turn into zombies. If 1, all deaths result in zombification.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0,
                                        true,
                                        1.0);
    
    cv_SuperJumpForce = CreateConVar("tfbh_superjump_force",
                                        "800",
                                        "Upward force to apply when a zombie super-jumps, in units per second.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0);
    
    cv_WetRagePenalty = CreateConVar("tfbh_zrage_wetpenalty",
                                        "2",
                                        "Penalty to apply per second to a zombie's rage when they are Jarate'd or milked.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE);
                                        
    cv_JarateKnockForce = CreateConVar("tfbh_zjarate_force",
                                        "850",
                                        "Force with which to push players when a zombie Jarate jar explodes.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0);
                                        
    cv_RedJarateKnock = CreateConVar("tfbh_survivor_jarate_pushes",
                                        "1",
                                        "Whether survivor Jarate also pushes zombies.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0,
                                        true,
                                        1.0);
    cv_UberOnHit = CreateConVar("tfbh_uber_added_on_hit",
                                        "3",
                                        "How much uber a Medic is given per syringe hit.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0,
                                        true,
                                        100.0);
                                        
    cv_UberOnBolt = CreateConVar("tfbh_uber_added_on_bolt",
                                        "3",
                                        "How much uber a Medic is given per crossbow bolt hit.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                        true,
                                        0.0,
                                        true,
                                        100.0);
    
    cv_RespawnInSetup = CreateConVar("tfbh_setup_respawn_delay",
                                        "0.5",
                                        "If >= 0, specified the delay after which a player who dies in setup will be respawned. If < 0, plugin does not force respawn (map might).",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE);
                                                                                
    cv_TeleChargePerSec = CreateConVar("tfbh_teleport_charge_per_sec",
                                        "1.66",
                                        "How fast a zombie Engineer's teleport ability should charge, in points per second.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                                                                true,
                                                                                0.0);
                                                                                
    cv_SetupTime = CreateConVar("tfbh_setup_time",
                                        "60",
                                        "Amount of setup time given to survivors before players are zombified.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                                                                true,
                                                                                1.0);
                                                                                
    cv_RoundTime = CreateConVar("tfbh_round_time",
                                        "300",
                                        "Amount of time Red players must survive before they win the round.",
                                        FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                                                                true,
                                                                                1.0);
    
    cv_Unbalance = FindConVar("mp_teams_unbalance_limit");
    cv_Autobalance = FindConVar("mp_autoteambalance");
    cv_Scramble = FindConVar("mp_scrambleteams_auto");
    cv_Stalemate = FindConVar("mp_stalemate_enable");
    
    HookEventEx("teamplay_round_start",        Event_RoundStart,    EventHookMode_Post);
    HookEventEx("teamplay_round_win",        Event_RoundWin,        EventHookMode_Post);
    HookEventEx("teamplay_round_stalemate",        Event_RoundStalemate,    EventHookMode_Post);
    HookEventEx("player_team",            Event_TeamsChange,    EventHookMode_Post);
    HookEventEx("teamplay_setup_finished",        Event_SetupFinished,    EventHookMode_Post);
    HookEventEx("player_death",            Event_PlayerDeath,    EventHookMode_Post);
    HookEventEx("player_spawn",            Event_PlayerSpawn,    EventHookMode_Post);
    HookEventEx("object_deflected",         Event_Deflect,         EventHookMode_Post);
    HookEventEx("post_inventory_application",     Event_Inventory,     EventHookMode_Post);
    
    AddCommandListener(TeamChange,          "jointeam");    // For blocking team change commands.
    AddCommandListener(DoTaunt,        "taunt");       // Activating zombie rage.
    AddCommandListener(DoTaunt,        "+taunt");
    
    HookConVarChange(cv_PluginEnabled,    CvarChange);
    HookConVarChange(cv_Unbalance,        CvarChange);
    HookConVarChange(cv_Autobalance,    CvarChange);
    HookConVarChange(cv_Scramble,        CvarChange);
    HookConVarChange(cv_Stalemate,        CvarChange);
    
    // Find offsets for the damage hook.
    new Handle:gamedata = LoadGameConfigFile("tfbiohazard.offsets"); 
    if ( gamedata == INVALID_HANDLE ) SetFailState("Offset gamedata file not found."); 
    
    new offset = GameConfGetOffset(gamedata, "OnTakeDamage_Alive");
    hDamageHook = DHookCreate(offset, HookType_Entity, ReturnType_Int, ThisPointer_CBaseEntity, OnTakeDamage_Alive); 
    DHookAddParam(hDamageHook, HookParamType_ObjectPtr);
    
    ofAttacker = GameConfGetOffset(gamedata, "m_hAttacker");
    ofInflictor = GameConfGetOffset(gamedata, "m_hInflictor");
    ofDamage = GameConfGetOffset(gamedata, "m_flDamage");
    //ofDamageType = GameConfGetOffset(gamedata, "m_iAmmoType");
    ofWeapon = GameConfGetOffset(gamedata, "m_hWeapon");
    ofDamageForce = GameConfGetOffset(gamedata, "m_vecDamageForce");
    ofDamagePosition = GameConfGetOffset(gamedata, "m_vecDamagePosition");
    ofDamageCustom = GameConfGetOffset(gamedata, "m_iDamageCustom");
    
    CloseHandle(gamedata);
    
    #if DEVELOPER == 1
    RegConsoleCmd("tfbh_debug_showdata", Debug_ShowData, "Outputs player data arrays to the console.", FCVAR_PLUGIN | FCVAR_CHEAT);
    RegConsoleCmd("tfbh_fullrage", Debug_FullRage, "Caller client gets full rage if a zombie.", FCVAR_PLUGIN | FCVAR_CHEAT);
    #endif
    
    decl String:deb[8];
    GetConVarDefault(cv_Debug, deb, sizeof(deb));
    if ( StringToInt(deb) > 0 )
    {
        LogMessage("Debug cvar default is not 0! Reset this before release!");
    }
    
    #if DEVELOPER == 1
    LogMessage("DEVELOPER flag set! Reset this before release!");
    #endif
    
    #if defined PD_DEBUG
    LogMessage("Player data array debugging compiled in - this will be (marginally) less efficient.");
    #endif
    
    // If we're not enabled, don't set anything up.
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED )
    {
        LogMessage("Plugin starting disabled.");
        return;
    }
    
    // If the server is not yet processing, flag NOT_IN_ROUND and FEW_PLAYERS.
    if ( !IsServerProcessing() )
    {
        g_PluginState |= STATE_NOT_IN_ROUND;
        g_PluginState |= STATE_FEW_PLAYERS;
    }
    
    // Run first start initialisation.
    Cleanup(CLEANUP_FIRSTSTART);
    
    b_Setup = true;
}

stock Precache()
{
    // Nothing yet!
}

public OnPluginEnd()
{
    // Note that this can be called if the "map" command is entered from the server console (I think)!
    // Make sure our flags are reset!
    
    g_PluginState |= STATE_NOT_IN_ROUND;
    g_PluginState |= STATE_FEW_PLAYERS;
    
    Cleanup(CLEANUP_ENDALL);
}

/*    Checks which ConVar has changed and performs the relevant actions.    */
public CvarChange( Handle:convar, const String:oldValue[], const String:newValue[])
{
    if ( convar == cv_PluginEnabled ) PluginEnabledStateChanged(GetConVarBool(cv_PluginEnabled));
        
    else if ( convar == cv_Unbalance )
    {
        // Don't change these values if we're enabled.
        if ( g_PluginState & STATE_DISABLED != STATE_DISABLED )
        {
            if ( StringToInt(newValue) != DES_UNBALANCE )
            {
                LogMessage("mp_teams_unbalance_limit changed while plugin is active, blocking change.");
                ServerCommand("mp_teams_unbalance_limit %d", DES_UNBALANCE);
            }
        }
        // If we're not enabled, record the new value for us to return to when the plugin is unloaded.
        else
        {
            cvdef_Unbalance == StringToInt(newValue);
            LogMessage("mp_teams_unbalance_limit changed, value stored: %d", cvdef_Unbalance);
        }
    }
        
    else if ( convar == cv_Autobalance )
    {
        // Don't change these values if we're enabled.
        if ( g_PluginState & STATE_DISABLED != STATE_DISABLED )
        {
            if ( StringToInt(newValue) != DES_AUTOBALANCE )
            {
                LogMessage("mp_autoteambalance changed while plugin is active, blocking change.");
                ServerCommand("mp_autoteambalance %d", DES_AUTOBALANCE);
            }
        }
        // If we're not enabled, record the new value for us to return to when the plugin is unloaded.
        else
        {
            cvdef_Autobalance == StringToInt(newValue);
            LogMessage("mp_autoteambalance changed, value stored: %d", cvdef_Autobalance);
        }
    }
        
    else if ( convar == cv_Scramble )
    {
        // Don't change these values if we're enabled.
        if ( g_PluginState & STATE_DISABLED != STATE_DISABLED )
        {
            if ( StringToInt(newValue) != DES_SCRAMBLE )
            {
                LogMessage("mp_scrambleteams_auto changed while plugin is active, blocking change.");
                ServerCommand("mp_scrambleteams_auto %d", DES_SCRAMBLE);
            }
        }
        // If we're not enabled, record the new value for us to return to when the plugin is unloaded.
        else
        {
            cvdef_Scramble == StringToInt(newValue);
            LogMessage("mp_scrambleteams_auto changed, value stored: %d", cvdef_Scramble);
        }
    }
    else if ( convar == cv_Stalemate )
    {
        // Don't change these values if we're enabled.
        if ( g_PluginState & STATE_DISABLED != STATE_DISABLED )
        {
            if ( StringToInt(newValue) != DES_STALEMATE )
            {
                LogMessage("mp_stalemate_enable changed while plugin is active, blocking change.");
                ServerCommand("mp_stalemate_enable %d", DES_STALEMATE);
            }
        }
        // If we're not enabled, record the new value for us to return to when the plugin is unloaded.
        else
        {
            cvdef_Stalemate == StringToInt(newValue);
            LogMessage("mp_stalemate_enable changed, value stored: %d", cvdef_Stalemate);
        }
    }
}

/*    Sets the enabled/disabled state of the plugin.
    Passing true enables, false disables.    */
PluginEnabledStateChanged(bool:b_state)
{
    if ( b_state )
    {
        // If we're already enabled, do nothing.
        if ( g_PluginState & STATE_DISABLED != STATE_DISABLED ) return;
            
        g_PluginState &= ~STATE_DISABLED;    // Clear the disabled flag.
        Cleanup(CLEANUP_FIRSTSTART);        // Initialise values.
    }
    else
    {
        // If we're already disabled, do nothing.
        if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ) return;
        
        g_PluginState |= STATE_DISABLED;    // Set the disabled flag.
        Cleanup(CLEANUP_ENDALL);            // Clean up.
    }
}

// =======================================================================================
// ===================================== Event hooks =====================================
// =======================================================================================

/*    Called when a round starts.    */
public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    // Remove me!
    // For testing purposes: work out which entity index the player resource entity is and output its classname.
//     decl String:cname[64];
//     GetEntityClassname(38, cname, sizeof(cname));    // 38 works for my current SRCDS setup, I think it's proportional to MaxClients.
//     LogMessage("Resource classname: %s", cname);
    // Name output: tf_player_manager
    
    // Clear the NOT_IN_ROUND flag.
    g_PluginState &= ~STATE_NOT_IN_ROUND;
    
    Cleanup(CLEANUP_ROUNDSTART);
    
    // Check whether the player counts are adequate.
    if ( PlayerCountAdequate() ) g_PluginState &= ~STATE_FEW_PLAYERS;
    else g_PluginState |= STATE_FEW_PLAYERS;
    
    if ( (g_PluginState & STATE_DISABLED == STATE_DISABLED) ||
            (g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS) ) return;
    
    // Plugin is enabled.
    
    new cvDebug = GetConVarInt(cv_Debug);
    
    // Set the AWAITING flag.
    g_PluginState |= STATE_AWAITING;
    
    // Disable resupply lockers.
    new i = -1;
    while ( (i = FindEntityByClassname(i, "func_regenerate")) != -1 )
    {
        AcceptEntityInput(i, "Disable");
    }
    
    // Allow team changes to Red.
    b_AllowChange = true;
    
    // Move everyone on Blue to the Red team.
    for ( i = 1; i <= MaxClients; i++ )
    {
        if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Checking client %d...", i);
        
        if ( IsClientConnected(i) && !IsClientReplay(i) && !IsClientSourceTV(i) )
        {
            if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %d (%N) is connected.", i, i);
            
            if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_BLUE )    // If the player is on Blue:
            {
                if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Cleared zombie flag for client %N.", i);
                PD_SetClientFlag(i, UsrZombie, false);  // Mark the player as not being a zombie.
                
                if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Changing %N to Red.", i);
                ChangeClientTeam(i, TEAM_RED);                                  // Change the player to Red.
                TF2_RespawnPlayer(i);
            }
        }
    }
    
    // Finished adding players to the Red team.
    b_AllowChange = false;
    
    ModifyRespawnTimes();    // Set up respawn times for the round.
}

/*    Called when a round is won.    */
public Event_RoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
    Event_RoundEnd();
}

/*    Called when a round is drawn.    */
public Event_RoundStalemate(Handle:event, const String:name[], bool:dontBroadcast)
{
    Event_RoundEnd();
}

public OnMapStart()
{
    // Set the NOT_IN_ROUND flag.
    g_PluginState |= STATE_NOT_IN_ROUND;
    
    // Set the FEW_PLAYERS flag.
    g_PluginState |= STATE_FEW_PLAYERS;
    
    Cleanup(CLEANUP_MAPSTART);
}

public OnMapEnd()
{
    // Set the NOT_IN_ROUND flag.
    g_PluginState |= STATE_NOT_IN_ROUND;
    
    // Set the FEW_PLAYERS flag.
    g_PluginState |= STATE_FEW_PLAYERS;
    
    Cleanup(CLEANUP_MAPEND);
}

/*    Called when a player disconnects.
    This is called BEFORE TeamsChange below.    */
public Event_Disconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
    g_Disconnect = GetClientOfUserId(GetEventInt(event, "userid"));
}

public Event_SetupFinished(Handle:event, const String:name[], bool:dontBroadcast)
{
    // If the plugin is disabled, there are not enough players or we are not in a round, return;
    if ( (g_PluginState & STATE_DISABLED == STATE_DISABLED) ||
            (g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS) ||
            (g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND)    ) return;
    
    new cvDebug = GetConVarInt(cv_Debug);
    
    for ( new i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame(i) && GetClientTeam(i) >= TEAM_RED )
        {
            // Ensure all blue players are swapped to Red BEFORE we clear STATE_AWAITING.
            if ( GetClientTeam(i) == TEAM_BLUE )
            {
                ChangeClientTeam(i, TEAM_RED);
                TF2_RespawnPlayer(i);    
                PD_SetClientFlag(i, UsrZombie, false);

            }
            
            // If the player is not currently alive, respawn them.
            if ( !IsPlayerAlive(i) )
            {
                TF2_RespawnPlayer(i);
            }
        }
    }
    
    // Clear the AWAITING flag. This will ensure that if Blue drops to 0 players from this point on, Red will win the game.
    g_PluginState &= ~STATE_AWAITING;
    
    // A round is currently being played. Infect some people.
    
    // Find how many players are alive on Red.
    new redTeam;
    for ( new i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) ) redTeam++;
    }
    
    new Float:fRedTeam = float(redTeam);
    
    // Decide how many zombies should spawn.
    new Float:n = GetConVarFloat(cv_ZombieRatio);
    new nZombies = RoundToCeil(fRedTeam/n);
    
    if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE )
    {
        LogMessage("redTeam: %d. n: %f. Before rounding: %f", redTeam, n, fRedTeam/n);
        LogMessage("Number of zombies to spawn: %d", nZombies);
    }
    
    // Build an array of the Red players.
    decl players[redTeam];
    new pos;
    
    for ( new i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) )
        {
            players[pos] = i;
            pos++;
        }
    }
    
    if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE )
    {
        LogMessage("Before sort:");
        
        for ( new i = 0; i < redTeam; i++ )
        {
            LogMessage("Array index %d - %d %N", i, players[i], players[i]);
        }
    }
    
    // Randomise the array.
    SortIntegers(players, redTeam, Sort_Random);
    
    // Due to a SourceMod bug, the first element of the array will always remain unsorted.
    // We correct this here.
    
    // I think this is fixed now.
//     new slotToSwap = GetRandomInt(0, redTeam-1);    // Choose a random slot to swap between.
//     
//     if ( slotToSwap > 0 )    // If the slot is 0, don't bother doing anything else.
//     {
//         new temp = players[0];                            // Make a note of the index in the first element.
//         players[0] = players[slotToSwap];                                       // Put the data from the chosen slot into the first slot.
//         players[slotToSwap] = temp;                        // Put the value in temp back into the random slot.
//     }
    
    if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE )
    {
        LogMessage("After sort:");
        
        for ( new i = 0; i < redTeam; i++ )
        {
            LogMessage("Array index %d - %d %N", i, players[i], players[i]);
        }
    }
    
    // Choose clients from the top of the array.
    for ( new i = 0; i < nZombies; i++ )
    {
        if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N chosen to be zombified.", players[i]);
        
        MakeClientZombie2(players[i]);                                            // Make the client into a zombie.
        //g_StartBoost[DataIndexForUserId(GetClientUserId(players[i]))] = true;    // Mark them as being roundstart boosted.
        PD_SetClientFlag(players[i], UsrStartBoost, true);
    }
}

/*    Called when a player changes team.    */
public Event_TeamsChange(Handle:event, const String:name[], bool:dontBroadcast)
{
    if ( (g_PluginState & STATE_DISABLED == STATE_DISABLED) )
    {
        // Clear g_Disconnect just in case.
        g_Disconnect = 0;
        
        return;
    }
    
    // I've never liked team change hooks.
    
    // If the plugin is disabled or we're not in a round, ignore team changes.
    // If there are not enough players to begin a game, allow team changes but monitor team counts.
    // When the team counts go over the required threshold, end the round.
    
    // After team change is complete, check team numbers. If either Red or Blue has < 1 player, declare a win.
    // This means that players can leave Red or Blue to go spec or leave the game, at the expense of their team.
    
    // The main complicating factor here is that using GetTeamClientCount in this hook reports
    // the number of clients as it was BEFORE the change, even with HookMode_Post.
    // To get around this we need to build up what the teams will look like after the change.
    
    new userid = GetEventInt(event, "userid");
    new client = GetClientOfUserId(userid);
    new newTeam = GetEventInt(event, "team");
    new oldTeam = GetEventInt(event, "oldteam");
    new bool:disconnect = GetEventBool(event, "disconnect");
    
    new redTeam = GetTeamClientCount(TEAM_RED);        // These will give us the team counts BEFORE the client has switched.
    new blueTeam = GetTeamClientCount(TEAM_BLUE);
    
    new cvDebug = GetConVarInt(cv_Debug);
    
    if ( disconnect )             // If the team change happened because the client was disconnecting:
    {
        if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is disconnecting.", client);
        
                                // Note that, if disconnect == true, the userid will point to the index 0.
                                // We fix this here.
        client = g_Disconnect;    // This is retrieved from player_disconnect, which is fired before player_team.
        g_Disconnect = 0;
        
                                // If disconnected, this means the team he was on will lose a player and the other teams will stay the same.
        switch (oldTeam)
        {
            case TEAM_RED:
            {
                if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is leaving team Red.", client);
                redTeam--;
            }
            
            case TEAM_BLUE:
            {
                if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is leaving team Blue.", client);
                blueTeam--;
            }
        }
    }
    else                        // The client is not disconnecting.
    {
        if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is not disconnecting.", client);
        
                                // Decrease the count for the team the client is leaving.
        switch (oldTeam)
        {
            case TEAM_RED:
            {
                if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is leaving team Red.", client);
                redTeam--;
            }
            
            case TEAM_BLUE:
            {
                if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is leaving team Blue.", client);
                blueTeam--;
            }
        }
        
                                // Increase the count for the team the client is joining.
        switch (newTeam)
        {
            case TEAM_RED:
            {
                if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is joining team Red.", client);
                redTeam++;
            }
            
            case TEAM_BLUE:
            {
                if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is joining team Blue.", client);
                blueTeam++;
            }
        }
    }
    
    // Team counts after the change are now held in redTeam and blueTeam.
    new total = redTeam + blueTeam;
    
    if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Team counts after change - Red: %d, Blue: %d, Total: %d", redTeam, blueTeam, total);
    
    // If there were not enough players but we have just broken the threshold, end the round in a stalemate.
    if ( g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS )
    {
        if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Player count was below the threshold.");
        
        if ( total > 1 )
        {
            if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Player count is now above the threshold!");
            
            g_PluginState &= ~STATE_FEW_PLAYERS;    // Clear the FEW_PLAYERS flag.
            
            // Print a message to clients.
            decl String:buffer[256];
            
            for ( new i = 1; i <= MaxClients; i++ )
            {
                if ( IsClientInGame(i) )
                {
                    SetHudTextParams(-1.0, 0.43, 4.0, 255, 255, 255, 255, 1, 4.0);
                    Format(buffer, sizeof(buffer), "%T", "Time_For_New_Round", i);
                    ShowSyncHudText(i, hs_ZText, buffer);
                }
            }
            
            RoundWinWithCleanup();
            
            return;
        }
        else
        {
            if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Player count is still below the threshold.");
            
            return;
        }
    }
    // If there were enough players but now there are not, win the round for the team which has the remaining player.
    else if ( (g_PluginState & STATE_FEW_PLAYERS != STATE_FEW_PLAYERS) && total <= 1 )
    {
        if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Player count is now below the threshold.");
        
        if        ( redTeam > 0 )        RoundWinWithCleanup(TEAM_RED);
        else if    ( blueTeam > 0 )    RoundWinWithCleanup(TEAM_BLUE);
        else                        RoundWinWithCleanup();
        
        return;
    }
    
    if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Player count is still above the threshold.");
    
    // IGNORE
    // If the player is marked as a zombie but is changing to a team that is not Blue, clear the flag.
    // Ignore if the client is disconnecting, since this is dealt with elsewhere.
    //if ( !disconnect && g_Zombie[DataIndexForUserId(userid)] && newTeam != TEAM_BLUE ) g_Zombie[DataIndexForUserId(userid)] = false;
    
    // If this hook is fired it means the player was allowed through the jointeam command listener.
    // If they are changing to any team which is not Red, set the Zombie flag.
    // This means that they will not be able to rejoin Red until the next round.
    if ( !disconnect )
    {
        PD_SetClientFlag(client, UsrZombie, newTeam != TEAM_RED);
    }
    
    // Check whether Red is out of alive players.
    
    /*new redCount;
    
    for ( new i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) ) redCount++;
    }*/
    
    if ( redTeam < 1 )
    {
        if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Red team is out of players.");
        RoundWinWithCleanup(TEAM_BLUE);
    }
    
    // Check whether Blue is out of players.
    // Make sure the AWAITING flag is not set, otherwise we'll end the round while players are being swapped back to Red.
    else if ( blueTeam < 1 && (g_PluginState & STATE_AWAITING != STATE_AWAITING) )
    {
        if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Blue team is out of players.");
        RoundWinWithCleanup(TEAM_RED);
    }
    
    CreateTimer(0.1, Timer_CheckTeams);
}

/*    Used to block players changing team when they aren't allowed.
    Possible arguments are red, blue, auto or spectate.
    GetTeamClientCount returns the team values from before the change.*/
public Action:TeamChange(client, const String:command[], argc)
{
    // Don't block team changes if there are any abnormal states.
    if ( (g_PluginState & STATE_DISABLED == STATE_DISABLED) ||
            (g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS) ||
            (g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND)    ) return Plugin_Continue;
    
    new cvDebug = GetConVarInt(cv_Debug);
    
    if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE )
    {
        decl String:argument[512];
        GetCmdArgString(argument, sizeof(argument));
        LogMessage ("Client %N, command %s, args %s, red %d, blue %d", client, command, argument, GetTeamClientCount(TEAM_RED), GetTeamClientCount(TEAM_BLUE));
    }
    
    // We can't get the player's current team because GetClientTeam returns -1.
    // If we are still awaiting the first zombie, allow changes to Red from any team,
    // changes to spec from any team and disallow changes to Blue.
    // If the found is fully in progress, disallow changes to Red from any team,
    // allow changes to spec from any team and allow changes to Blue only if the
    // client is a Zombie.
    
    if ( b_AllowChange ) return Plugin_Continue;    // If this flag is true then players are being swapped in round initialisation, don't restrict.
    
    new String:arg[16];
    GetCmdArg(1, arg, sizeof(arg));
    if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Arg: %s", arg);
    
    if ( g_PluginState & STATE_AWAITING == STATE_AWAITING )    // If a zombie has yet to be chosen:
    {
        // Disallow players joining Blue.
        if ( StrContains(arg, "blue", false) != -1 || StrContains(arg, "auto", false) != -1 )
        {
            if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Arg contains blue or auto, overriding to red.");
            FakeClientCommandEx(client, "jointeam red");    // Ex is delayed by 1 frame
            return Plugin_Handled;
        }
    }
    else    // The first zombie has been chosen.
    {
        // Disallow players joining Red if they are marked as a zombie.
        if ( (StrContains(arg, "red", false) != -1 || StrContains(arg, "auto", false) != -1) && _PD_IsClientFlagSet(client, UsrZombie) )
        {
            if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Arg contains red or auto, overriding to blue.");
            FakeClientCommandEx(client, "jointeam blue");    // Ex is delayed by 1 frame
            return Plugin_Handled;
        }
        // Disallow players joining Blue if they are not marked as a zombie,
        else if ( (StrContains(arg, "blue", false) != -1 || StrContains(arg, "auto", false) != -1) && !_PD_IsClientFlagSet(client, UsrZombie) )
        {
            if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Arg contains blue or auto, overriding to red.");
            FakeClientCommandEx(client, "jointeam red");    // Ex is delayed by 1 frame
            return Plugin_Handled;
        }
    }
    
    return Plugin_Continue;
}

/*    For checking zombies to activate rage.    */
public Action:DoTaunt(client, const String:command[], argc)
{
    // Don't check unless the round has fully started.
    if ( g_PluginState > 0    ) return Plugin_Continue;
    
    if ( !IsClientInGame(client) || GetClientTeam(client) != TEAM_BLUE || !IsPlayerAlive(client) || TF2_IsPlayerInCondition(client, TFCond_Cloaked) || TF2_IsPlayerInCondition(client, TFCond_DeadRingered) ) return Plugin_Continue;
    
    // Check to see if the client is a zombie with full rage.
    new slot = _PD_GetClientSlot(client);
    if ( !_PD_IsFlagSet(slot, UsrZombie) || (_PD_GetRageLevel(slot) < 100.0 && _PD_GetTeleportLevel(slot) < 100.0) || _PD_IsFlagSet(slot, UsrRaging) ) return Plugin_Continue;
        
    // If we should teleport, do this first.
    if ( _PD_GetTeleportLevel(slot) >= 100.0 )
    {
        ActivateTeleport(client);
    }
    
    // Then activate rage.
    if ( _PD_GetRageLevel(slot) >= 100.0 )
    {
        ActivateRage(client);
    }
    
    return Plugin_Handled;
}

/* Teleports the client to a random person on the Red team. */
stock ActivateTeleport(client)
{
    new victims[MaxClients];
    
    // Get an array of players on Red. If we get no victims back, exit.
    new numVictims = GetClientIndexArray(victims, MaxClients, TEAM_RED);
    if ( numVictims < 1 ) return;
    
    // Randomise the array.
    SortIntegers(victims, numVictims, Sort_Random);
    
    // Choose the top player in the array.
    new victim = victims[0];
    
    // Get their origin.
    new Float:origin[3];
    GetClientAbsOrigin(victim, origin);
    
    // TODO: Bring other players along?
    
    // Teleport to their origin.
    TeleportEntity(client, origin, NULL_VECTOR, NULL_VECTOR);
    
    // Set our teleport charge to zero.
    PD_SetTeleportLevel(_PD_GetClientSlot(client), 0.0);
}

/* Moved from DoTaunt: activate the client's rage. This assumes client is valid and has full rage. */
stock ActivateRage(client)
{
    // Rage should be activated. Set the raging flag (decrease of rage meter is handled elsewhere).
    PD_SetClientFlag(client, UsrRaging, true);
    
    // Hoping this method will work: un-disguise if we are a Spy.
    TF2_RemoveCondition(client, TFCond_Disguising);
    TF2_RemoveCondition(client, TFCond_Disguised);
    
    // Check whether the player is a Pyro - should ignite victims if so.
    // NOTE: I have strange vague nightmares that TF2_IgnitePlayer used to crash the game - keep an eye on this!
    new bool:shouldIgnite = false;
    if ( TF2_GetPlayerClass(client) == TFClass_Pyro ) shouldIgnite = true;
    
    // Stun any players within the specified radius.
    new Float:cOrigin[3];
    GetClientAbsOrigin(client, cOrigin);
    //CalcPlayerMidpoint(client, cOrigin);  // Having problems with this.
    
    for ( new i = 1; i <= MaxClients; i++ )
    {
            if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) )
            {
                    new Float:tOrigin[3];
                    GetClientAbsOrigin(i, tOrigin);
                    //CalcPlayerMidpoint(i, tOrigin);
                    if ( GetConVarInt(cv_Debug) & DEBUG_RAGE == DEBUG_RAGE ) LogMessage("Getting origin of %N. Distance = %f", i, GetVectorDistance(cOrigin, tOrigin));
                    
                    if ( !TF2_IsPlayerInCondition(i, TFCond_Ubercharged) && GetVectorDistance(cOrigin, tOrigin) <= GetConVarFloat(cv_ZRageStunRadius) )
                    {
                            TF2_StunPlayer(i, GetConVarFloat(cv_ZRageStunDuration), 0.0, TF_STUNFLAGS_GHOSTSCARE, client);
                            if ( shouldIgnite ) TF2_IgnitePlayer(i, client);
                            if ( GetConVarInt(cv_Debug) & DEBUG_RAGE == DEBUG_RAGE ) LogMessage("Player %N stunned by zombie %N.", i, client);
                    }
            }
    }
    
    // Stun any sentries within the specified radius.
    new ent = -1;
    while ( (ent = FindEntityByClassname(ent, "obj_sentrygun")) != -1 )
    {
            new Float:tOrigin[3];
            GetEntPropVector(ent, Prop_Send, "m_vecOrigin", tOrigin);
            
            if ( GetVectorDistance(cOrigin, tOrigin) <= GetConVarFloat(cv_ZRageStunRadius) )
            {
                    SetEntProp(ent, Prop_Send, "m_bDisabled", 1);
                    new particle = AttachParticle(ent, "yikes_fx", 75.0);
                    
                    new Handle:pack = CreateDataPack();
                    WritePackCell(pack, EntIndexToEntRef(ent));         // Record the sentry.
                    WritePackCell(pack, EntIndexToEntRef(particle));    // Record the particle.
                    
                    CreateTimer(GetConVarFloat(cv_ZRageDuration) + 2.0, Timer_EnableStunnedSentry, pack);
            }
    }
}

public Action:Event_Deflect(Handle:event, const String:name[], bool:dontBroadcast)
{
    // Don't check unless the round has fully started.
    if ( g_PluginState > 0    ) return Plugin_Continue;
    
    new ownerid = GetEventInt(event, "ownerid");
    new owner = GetClientOfUserId(ownerid);
    new weaponid = GetEventInt(event, "weaponid");
    new slot = _PD_GetClientSlot(owner);
    
    if ( GetClientTeam(owner) != TEAM_BLUE || !_PD_IsFlagSet(slot, UsrZombie) || weaponid != 0 ) return Plugin_Continue;
    
    // Add rage to the zombie who was pushed.
    PD_IncrementRageLevel(slot, 3.0);
    if ( _PD_GetRageLevel(slot) > 100.0 ) PD_SetRageLevel(slot, 100.0);
    
    return Plugin_Continue;
}

/*    Called when a client connects.    */
public OnClientConnected(client)
{
    // Don't set up things for Replay or Source TV.
    if ( IsClientReplay(client) || IsClientSourceTV(client) ) return;
    
    // Give the client a slot in the data arrays.
    new slot = PD_RegisterClient(client);
    if ( slot < 0 )
    {
        SetFailState("Cannot find a free data index for client %N (MaxClients %d, MAXPLAYERS %d).", client, MaxClients, MAXPLAYERS);
    }
}

public Action:Event_Inventory(Handle:event, const String:name[], bool:dontBroadcast)
{
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
            g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return Plugin_Continue;
            
    new userid = GetEventInt(event, "userid");
    new client = GetClientOfUserId(userid);
    
    if ( GetClientTeam(client) == TEAM_BLUE )
    {
        if ( _PD_IsClientFlagSet(client, UsrZombie) )
        {
            // Validate weapons.
            ManageZombieWeapons(client);
            EquipSlot(client, SLOT_MELEE);
        }
    }
    else if ( GetClientTeam(client) == TEAM_RED )
    {
        // Validate weapons.
        ValidateSurvivorWeapons(client);
    }
    
    return Plugin_Continue;
}

/*    Called when a client disconnects.    */
public OnClientDisconnect(client)
{
    // Don't set up things for Replay or Source TV.
    if ( IsClientReplay(client) || IsClientSourceTV(client) ) return;
    
    // Clear the client's data arrays.
    PD_UnregisterClient(client);
    
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ) return;
    
    //SDKUnhook(client, SDKHook_OnTakeDamage,        OnTakeDamage);
    SDKUnhook(client, SDKHook_OnTakeDamagePost,    OnTakeDamagePost);
}

public OnClientPutInServer(client)
{
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ) return;
    
    // Don't set up things for Replay or Source TV.
    if ( IsClientReplay(client) || IsClientSourceTV(client) ) return;
    
    //SDKHook(client, SDKHook_OnTakeDamage,        OnTakeDamage);        // Hooks when the client takes damage.
    SDKHook(client, SDKHook_OnTakeDamagePost,    OnTakeDamagePost);
    
    DHookEntity(hDamageHook, false, client); 
}

/*    Custom OnTakeDamage_Alive hook - this reports damage after spread has been applied.
    BUG: Fists of Steel modify melee damage taken AFTER this hook (fucking...), meaning
    players can die without becoming a zombie.
    Removing them in full for now unless/until we find a way around it.    */
public MRESReturn:OnTakeDamage_Alive(client, Handle:hReturn, Handle:hParams) 
{
    // <ocd> I might want to clean this up someday... </ocd>
    
    // Don't bother checking damage values if we're not in a valid round.
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
            g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
            g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return MRES_Ignored;
    
    // Read params:
    // (OnTakeDamage_Alive passes a struct, hence the param number will always be 1)
    new attacker = DHookGetParamObjectPtrVar(hParams, 1, ofAttacker, ObjectValueType_Ehandle);
    new inflictor = DHookGetParamObjectPtrVar(hParams, 1, ofInflictor, ObjectValueType_Ehandle);
    new Float:damage = DHookGetParamObjectPtrVar(hParams, 1, ofDamage, ObjectValueType_Float);
    //new damageType = DHookGetParamObjectPtrVar(hParams, 1, ofDamageType, ObjectValueType_Int);
    new weapon = DHookGetParamObjectPtrVar(hParams, 1, ofWeapon, ObjectValueType_Ehandle);
    new custom = DHookGetParamObjectPtrVar(hParams, 1, ofDamageCustom, ObjectValueType_Int);
    
    // Should these be VectorPtr?
    new Float:damageForce[3];
    DHookGetParamObjectPtrVarVector(hParams, 1, ofDamageForce, ObjectValueType_Vector, damageForce);
    
    new Float:damagePosition[3];
    DHookGetParamObjectPtrVarVector(hParams, 1, ofDamagePosition, ObjectValueType_Vector, damagePosition);
    
    new index = _PD_GetClientSlot(client);
    new cvDebug = GetConVarInt(cv_Debug);
    
    // If the player is on Red and not a zombie, the attacker is on Blue and is a zombie and the damage will kill the player, convert Red player to zombie.
    // This jumps in before the player actually dies, since it's nigh impossible to respawn the player instantly in the
    // same place using the death hook.
    
    //if ( cvDebug & DEBUG_ZOMBIFY == DEBUG_ZOMBIFY ) LogMessage("Team %d, damage %f, health %d, attacker %d, attacker team %d, g_Zombie %d", GetClientTeam(client), damage, GetEntProp(client, Prop_Send, "m_iHealth"), attacker, GetClientTeam(attacker), g_Zombie[DataIndexForUserId(GetClientUserId(attacker))]);
    
    new bool:zombify = true;
    
    // If cv_AlwaysZombify is not set, only attacks specifically caused by a Blue zombie player should cause us to zombify.
    if ( !GetConVarBool(cv_AlwaysZombify) && (attacker <= 0 || attacker > MaxClients || GetClientTeam(attacker) != TEAM_BLUE || !_PD_IsClientFlagSet(attacker, UsrZombie)) ) zombify = false;
    
    // Don't zombify if setup hasn't finished yet.
    else if ( (g_PluginState & STATE_AWAITING) == STATE_AWAITING ) zombify = false;
    
    if ( GetClientTeam(client) == TEAM_RED && zombify )
    {
        //PrintToChatAll("Should zombify: damage %f, client %N's health: %d", damage, client, GetEntProp(client, Prop_Send, "m_iHealth"));
        new Float:dmg = damage;
        if ( TF2_GetPlayerClass(client) == TFClass_Spy )
        {
            if ( GetEntProp(client, Prop_Send, "m_bFeignDeathReady") == 1 || TF2_IsPlayerInCondition(client, TFCond_DeadRingered) ) dmg *= 0.1;    // DR reduces damage to 10%.
        }
        
        if ( RoundFloat(dmg) >= GetEntProp(client, Prop_Send, "m_iHealth") )    // Must use the player health property here, since g_Health doesn't update until the post hook.
        {
            if ( cvDebug & DEBUG_ZOMBIFY == DEBUG_ZOMBIFY ) LogMessage("Client %N killed by zombie %N", client, attacker);
            damage = 0.0;
            DHookSetParamObjectPtrVar(hParams, 1, ofDamage, ObjectValueType_Float, damage);    // Negate the damage.
            MakeClientZombie2(client);                                                        // Make the client a zombie.
            BuildZombieMessage(client, attacker, inflictor, DMG_CLUB, weapon);                // Build and fire the death message.
            
            // If the kill was a backstab:
            if ( custom == TF_CUSTOM_BACKSTAB )
            {
                // Grant full rage if not already raging.
                new dataindex = _PD_GetClientSlot(attacker);
                if ( !_PD_IsFlagSet(dataindex, UsrRaging) ) PD_SetRageLevel(dataindex, 100.0);
            }
            
            return MRES_ChangedHandled;                                                        // AFAIK ChangedHandled is for changed params, Override is for changed return.
        }
        else if ( cvDebug & DEBUG_ZOMBIFY == DEBUG_ZOMBIFY ) LogMessage("Damage not enough to kill player.");
    }
    
    // If the player is on Blue and a zombie, and the attacker is on Red and not a zombie:
    else if ( GetClientTeam(client) == TEAM_BLUE && _PD_IsFlagSet(index, UsrZombie) &&
            attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) &&
            GetClientTeam(attacker) == TEAM_RED && !_PD_IsClientFlagSet(attacker, UsrZombie) )
    {
        new Float:mx;
        if ( TF2_GetPlayerClass(client) == TFClass_Heavy && GetEntProp(client, Prop_Send, "m_bDucked") == 1 ) mx = 0.0;
        else if ( IsValidEntity(inflictor) )
        {
            new String:classname[64];
            GetEntityClassname(inflictor, classname, sizeof(classname));
            
            if ( strcmp(classname, "obj_sentrygun") == 0 ) mx = GetConVarFloat(cv_SentryPushback);
            else mx = GetConVarFloat(cv_Pushback);
        }
        else mx = GetConVarFloat(cv_Pushback);
        
        damageForce[0] = damageForce[0] * mx;    // This method seems to work better...? Might just be me.
        damageForce[1] = damageForce[1] * mx;
        damageForce[2] = damageForce[2] * mx;
        //ScaleVector(damageForce, GetConVarFloat(cv_Pushback));
        
        DHookSetParamObjectPtrVarVector(hParams, 1, ofDamageForce, ObjectValueType_Vector, damageForce);    // Override the pushback.
        
        // If the attack was a backstab, grant crits to the attacker.
        if ( custom == TF_CUSTOM_BACKSTAB )
        {
            TF2_AddCondition(attacker, TFCond_CritOnKill, 5.0);
            TF2_AddCondition(attacker, TFCond_SpeedBuffAlly, 5.0);
        }
        
        return MRES_ChangedHandled;
    }
    
    // V Doesn't work. V
    // If the attacker was world and the damage was 200 or over, it's fairly safe to assume we fell in a death pit or somesuch.
    // Make sure we are killed instantly.
//     else if ( GetClientTeam(client) == TEAM_BLUE && g_Zombie[index] && attacker == 0 && damage >= 200.0 )
//     {
//         damage = float(GetEntProp(client, Prop_Send, "m_iHealth")) + 10.0;
//         DHookSetParamObjectPtrVar(hParams, 1, ofDamage, ObjectValueType_Float, damage);
//         return MRES_ChangedHandled;
//     }
    
    return MRES_Ignored;
}

public Action:OnTakeDamagePost(client, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3])
{
    // Don't bother checking damage values if we're not in a valid round.
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
            g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
            g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return Plugin_Continue;
    
    new index = _PD_GetClientSlot(client);
    
    if ( GetConVarInt(cv_Debug) & DEBUG_ZOMBIFY == DEBUG_ZOMBIFY ) LogMessage("Client %N's health is now %d", client, GetEntProp(client, Prop_Send, "m_iHealth"));
    
    // If a zombie was hurt, update their recorded health.
    if ( GetClientTeam(client) == TEAM_BLUE && _PD_IsFlagSet(index, UsrZombie) )
    {
        PD_SetCurrentHealth(index, GetEntProp(client, Prop_Send, "m_iHealth"));
    }

    return Plugin_Continue;
}

/*    Called when a player dies.    */
public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
            g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return;
            
    // If we're in setup time and a player has died, respawn them.
    if ( g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND )
    {
        new Float:delay = GetConVarFloat(cv_RespawnInSetup);
        
        if ( delay > 0.0 )
        {
            if ( delay >= 0.1 ) CreateTimer(delay, Timer_RespawnPlayerInSetup, any:GetEventInt(event, "userid"));    // Create a timer if needed.
            else RespawnPlayerInSetup(GetEventInt(event, "userid"));                                            // Time interval is too small, call instantly.
        }
        
        // We don't need to do anything else right now, so return.
        return;
    }
    
    new cvDebug = GetConVarInt(cv_Debug);
    
    new userid = GetEventInt(event, "userid");
    new client = GetClientOfUserId(userid);
    //new atuserid = GetEventInt(event, "attacker");
    //new attacker = GetClientOfUserId(atuserid);
    //new deathFlags = GetEventInt(event, "death_flags");
    
    // If the player is a Red Engineer, destroy their sentry.
    if ( GetClientTeam(client) == TEAM_RED && TF2_GetPlayerClass(client) == TFClass_Engineer )
    {
        if ( cvDebug & DEBUG_GENERAL == DEBUG_GENERAL ) LogMessage("Client %N is a Red Engineer, killing any sentries.", client);
        KillBuildings(client, BUILD_SENTRY);
    }
    
    // VV REDUNDANT: Handled in damage pre-hook instead. VV
    // If the player was on Red and not a zombie, and the killer was on Blue and was a zombie, and the player didn't DR,
    // change them into a zombie.
    /*if ( GetClientTeam(client) == TEAM_RED && !g_Zombie[DataIndexForUserId(userid)] &&
            attacker > 0 && attacker <= MaxClients && GetClientTeam(attacker) == TEAM_BLUE && g_Zombie[DataIndexForUserId(atuserid)] &&
            deathFlags & 32 != 32 )
    {
        if ( cvDebug & DEBUG_GENERAL == DEBUG_GENERAL ) LogMessage("%N killed by zombie %N.", client, attacker);
        MakeClientZombie(client, true);
        
    }*/
    
    CreateTimer(0.1, Timer_CheckTeams);
}

/*    Called when a player spawns.    */
public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
            /*g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||*/
            g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return;
    
    new userid = GetEventInt(event, "userid");
    new client = GetClientOfUserId(userid);
    new index = _PD_GetClientSlot(client);
    
    // If the player is on Blue and is a zombie:
    if ( GetClientTeam(client) == TEAM_BLUE && _PD_IsFlagSet(index, UsrZombie) )
    {
        SetLargeHealth(client);
        
        PD_ResetPropertyToDefault(index, RageLevel);
        PD_SetFlag(index, UsrRaging, false);
        PD_SetFlag(index, UsrSuperJump, false);
        PD_SetFlag(index, UsrJumpPrevFrame, false);
        PD_ResetPropertyToDefault(index, TeleportLevel);
    }
    else if ( GetClientTeam(client) == TEAM_RED )
    {
        ValidateSurvivorWeapons(client);
    }
    
    if ( g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ) return;
}

// /*    To prevent zombies from picking up health.    */
// public Action:OnHealthPackTouch(entity, other) 
// { 
//     if ( g_PluginState > 0 ) return Plugin_Continue;
//     
//     if ( GetConVarInt(cv_Debug) & DEBUG_HEALTHPACKS ) LogMessage("Health pack touch: entity %d, other %d", entity, other);
//     if (other > 0 && other <= MaxClients && g_Zombie[DataIndexForUserId(GetClientUserId(other))]) return Plugin_Handled; 
//     return Plugin_Continue; 
// }

/*    Called when an entity is created.    */
public OnEntityCreated(entity, const String:classname[])
{
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ) return;
    
    if ( strcmp(classname, "team_round_timer") == 0 )
    {
        // TODO: Can we block things from spawning here?
    
        // If we haven't recorded a timer:
        if ( g_RoundTimer == INVALID_ENT_REFERENCE || EntRefToEntIndex(g_RoundTimer) <= MaxClients )
        {
            g_RoundTimer = EntIndexToEntRef(entity);
            SDKHook(entity, SDKHook_Spawn, OnRoundTimerSpawned);
        }
    }
    
    if ( g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return;
    
    // If sentry, hook to change to mini.
    if ( strcmp(classname, "obj_sentrygun") == 0 )
    {
        SDKHook(entity, SDKHook_Spawn, OnSentrySpawned);
    }
    
    if ( g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ) return;
    
    // If Jarate, ungraciously hack our owner in here.
    if ( strcmp(classname, "tf_projectile_jar") == 0 )
    {
        new index = -1;
        if ( g_NextJarate > 0 ) index = _PD_GetClientSlot(GetClientOfUserId(g_NextJarate));
        if ( index > -1 )
        {
            PD_SetJarateRef(index, EntIndexToEntRef(entity));   // Record this jar.
        }
        
        g_NextJarate = 0;
    }
}

/*    Called when an entity is destroyed.    */
public OnEntityDestroyed(entity)
{
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
         g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ||
         g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ) return;
         
    // Getting the name of a disconnected client won't work, so check this here.
    if ( entity <= MaxClients ) return;
    
    decl String:classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));
    
    if ( strcmp(classname, "tf_projectile_jar") == 0 )
    {
        // Deal with physexplosion stuff.
        OnJarateHit(entity);
    }
}

/*    Called when a hooked sentry is created.    */
public OnSentrySpawned(sentry)
{
    // If not already a mini-sentry, make mini.
    new bool:mini = (GetEntProp(sentry, Prop_Send, "m_bMiniBuilding") == 1) ? true : false;
    
    if ( !mini )
    {
        SetEntProp(sentry, Prop_Send, "m_bMiniBuilding", 1);
        SetEntPropFloat(sentry, Prop_Send, "m_flModelScale", 0.75);
    }
    
    SDKUnhook(sentry, SDKHook_Spawn, OnSentrySpawned);
}

public OnRoundTimerSpawned(timer)
{
    SetVariantInt(GetConVarInt(cv_SetupTime));
    AcceptEntityInput(timer, "SetSetupTime");
    
    SetVariantInt(GetConVarInt(cv_RoundTime));
    AcceptEntityInput(timer, "SetMaxTime");
    SetVariantInt(GetConVarInt(cv_RoundTime));
    AcceptEntityInput(timer, "SetTime");
    
    // Reset the timer reference here - the function will find it again if it exists.
    // This is because this hook is called when the round starts but before the actual RoundStart event is fired,
    // so the reference to the CP master could be stale.
    // Really we need a better method for keeping track of the master...
    ControlPointMaster(true);
    decl String:name[64];
    name[0] = '\0';
    GetControlPointMasterName(name, sizeof(name));
    if ( GetConVarInt(cv_Debug) & DEBUG_ROUNDTIMER == DEBUG_ROUNDTIMER ) LogMessage("CPM name: %s", name);
    
    decl String:buffer[128];
    Format(buffer, sizeof(buffer), "OnFinished %s:SetWinner:%d:0:-1", name, TEAM_RED);
    if ( GetConVarInt(cv_Debug) & DEBUG_ROUNDTIMER == DEBUG_ROUNDTIMER ) LogMessage("AddOutput string: %s", buffer);
    
    SetVariantString(buffer);
    AcceptEntityInput(timer, "AddOutput");
}

public Action:TF2_CalcIsAttackCritical(client, weapon, String:weaponname[], &bool:result)
{
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
         g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ||
         g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ) return Plugin_Continue;
    
    // If we are throwing Jarate, log us as the global Jarate index so that we can assign our index to the next Jarate projectile created.
    if ( strcmp(weaponname, "tf_weapon_jar") == 0 )
    {
        g_NextJarate = GetClientUserId(client);
    }
    
    return Plugin_Continue;
}

// Called when a hooked jar explodes.
stock OnJarateHit(jar)
{
    // Explosion entities didn't work when pushing players so we have a custom function now.
    
    new Float:pos[3];
    GetEntPropVector(jar, Prop_Send, "m_vecOrigin", pos);
    new team = GetEntProp(jar, Prop_Send, "m_iTeamNum");

    // Find the owner of the jar.
    new owner = -1;
    new gindex = -1;
    for ( new i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame(i) )
        {
            new index = _PD_GetClientSlot(i);
            if ( _PD_GetJarateRef(index) == EntIndexToEntRef(jar) )
            {
                gindex = index;
                owner = i;
                break;
            }
        }
    }
    
    // Push players near the Jarate.
    for ( new i = 1; i <= MaxClients; i++ )
    {
        if ( !IsClientInGame(i) ) continue;
        
        new clientTeam = GetClientTeam(i);
        if ( IsPlayerAlive(i) && clientTeam >= TEAM_RED )    // If client and team are valid:
        {
            if    (
                    ( owner == i && ( clientTeam == TEAM_BLUE || (clientTeam == TEAM_RED && GetConVarBool(cv_RedJarateKnock)) ) )            // We are the owner and are allowed to be pushed
                    ||
                    ( clientTeam != team && ( (clientTeam == TEAM_BLUE && GetConVarBool(cv_RedJarateKnock)) || clientTeam == TEAM_RED ) )    // We are on the opposite team to the Jarate and are allowed to be pushed
                    
                )
            {
                new Float:push[3], Float:targetPos[3], Float:mins[3], Float:maxs[3];
                GetEntPropVector(i, Prop_Send, "m_vecMins", mins);
                GetEntPropVector(i, Prop_Send, "m_vecMaxs", maxs);
                
                // Calculate the centre of the client's bounding box.
                for ( new j = 0; j <= 2; j++ )
                {
                    targetPos[j] = (maxs[j] - mins[j])/2.0;
                }
                
                if ( RepulseVectorSpline(pos, targetPos, GetConVarFloat(cv_JarateKnockForce), push, 100.0, 192.0) )
                {
                    TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, push);
                }
            }
        }
    }
    
//      ( && (    // Client and team are valid, and:
//         (GetConVarBool(cv_RedJarateKnock) && owner == i) ||                            // Red Jarate can knock and we are the owner, or:
//         ( clientTeam != team && ((clientTeam == TEAM_BLUE && GetConVarBool(cv_RedJarateKnock)) || (clientTeam == TEAM_RED)) )    // The Jarate has come from the other team and we're allowed to be pushed:
//         ) )
    
    new Float:dir[3] = {0.0, 0.0, 1.0};
    TE_SetupSparks(pos, dir, 50, 8);
    TE_SendToAll();
    
    // Clear out the index.
    if ( gindex >= 0 ) PD_ResetPropertyToDefault(gindex, JarateRef);
}

// Calculates the repulsion vector from the source for an object at the target position dependant on the magnitude, using linear or quadratic falloff.
// Returns true if the target is within the specified radius and the resulting repulsion vector is strictly larger than threshold. If radius is 0 or less, it is ignored.
// Note that as of yet the magnitude of the repulsion is not modified to fall off neatly inside the overridden radius (ie. it's simply clipped by the radius).
// If the function returns false, the output vector is left unchanged.
stock bool:RepulseVector(const Float:source[3], const Float:target[3], const Float:magnitude, Float:out[3], const Float:threshold = 0.0, const Float:radius = 0.0, const bool:quadratic = false)
{
    new Float:distance = GetVectorDistance(source, target, quadratic);    // Distance of target from source.
    if ( radius > 0.0 && distance > radius ) return false;                // Return if we are outside the desired radius.
    if ( distance < 1.0 ) distance = 1.0;                                // The maximum scalar we want to get is that of magnitude.
    new Float:scalar = magnitude/distance;                                // Force is greater the closer you get to the source.
    if ( scalar < threshold ) return false;                                // Ensure the repulsion is large enough for us to care about.
    
    SubtractVectors(target, source, out);                                // Direction vector from source to target.
    NormalizeVector(out, out);                                            // Normalise the vector.
    ScaleVector(out, scalar);                                            // Scale the velocity.
    return true;
}

// Calculates the repulsion vector from the source for an object at the target position dependant on the magnitude, using a simple spline falloff curve.
// Returns true if the magnitude of the resulting vector is greater than or equal to the passed threshold value, otherwise returns false.
// The falloff is calculated using the radius parameter. If this is zero or less, the magnitude value is used as the radius.
// Falloff scales with the radius: at the source position, the magnitude is unchanged and on the radius border it is zero.
// If the magnitude is less than zero, the resulting vector will be zero.
// This function is basically an updated version of RepulseVector without the quirk that linear reciprocal falloff never reaches zero.
stock bool:RepulseVectorSpline(const Float:source[3], const Float:target[3], const Float:magnitude, Float:out[3], const Float:threshold = 0.0, const Float:radius = 0.0)
{
    if ( magnitude <= 0.0 )                                                // If magnitude is invalid:
    {
        ScaleVector(out, 0.0);                                            // Our vector will be null.
        return (threshold <= 0.0);                                        // If our value is strictly less than the threshold we should return false.
    }
    
    new Float:distance = GetVectorDistance(source, target);                // Calculate distance of target from source.
    new Float:newRadius = radius > 0.0 ? radius : magnitude;            // Record radius.
    new Float:frac = distance/newRadius;                                // Calculate the distance as a fraction of the radius.
    
    if ( frac >= 1.0 )                                                    // If we're outside the radius:
    {
        ScaleVector(out, 0.0);                                            // Our vector will be null.
        return (threshold <= 0.0);                                        // If our value is strictly less than the threshold we should return false.
    }
    
    new Float:scalar = magnitude * SimpleSpline(1.0 - frac);            // Multiply the magnitude by the spline value to get a scalar.
    SubtractVectors(target, source, out);                                // Direction vector from source to target.
    NormalizeVector(out, out);                                            // Normalise the vector.
    ScaleVector(out, scalar);                                            // Scale it according to our scalar.
    return (scalar >= threshold);                                        // Return whether the scalar was large enough.
}

/*    Remaps an input value [0 1] to an output value [0 1] along an ease-in, ease-out spline curve.
    (Thanks Valve)    */
stock Float:SimpleSpline(Float:value)
{
    new Float:valuesquared = value * value;
    return (-2.0 * valuesquared * value) + (3.0 * valuesquared);    // -2x^3 + 3x^2
}

// Spline curve with value clamped to [0 1].
stock SimpleSplineClamped(Float:value)
{
    if ( value < 0.0 ) value = 0.0;
    else if ( value > 1.0 ) value = 1.0;
    return SimpleSpline(value);
}

/*    Called when processing client movement buttons.    */
public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
    // Don't run if there are any abnormal states.
    if ( g_PluginState > 0 ) return Plugin_Continue;
    
    // Don't run if the client is not a Blue zombie.
    if ( GetClientTeam(client) != TEAM_BLUE ) return Plugin_Continue;
    
    new index = _PD_GetClientSlot(client);
    if ( !_PD_IsFlagSet(index, UsrZombie) ) return Plugin_Continue;
    
    //If the zombie is not on the ground, is pressing jump and has not jumped yet, do super-jump.
    if ( !_PD_IsFlagSet(index, UsrSuperJump) )
    {
        if ( GetEntPropEnt(client, Prop_Data, "m_hGroundEntity") < 0 && !_PD_IsFlagSet(index, UsrJumpPrevFrame) && (buttons & IN_JUMP) == IN_JUMP )
        {
            new Float:vec[3], Float:velocity[3];
            GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
            vec[0] = velocity[0];
            vec[1] = velocity[1];
            vec[2] = velocity[2];
            
            // Set to = rather than +=, since falling downwards can negate a lot of the super jump.
            vec[2] = GetConVarFloat(cv_SuperJumpForce);
            
            // Set client's speed to the new value.
            // NOTE: Doing this for the Scout doesn't work. Going to try applying on a 0.1 second timer instead.
            if ( TF2_GetPlayerClass(client) != TFClass_Scout )
            {
                TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vec);
            
                // Set jumping flag.
                SetEntProp(client, Prop_Send, "m_bJumping", 1);
                PD_SetFlag(index, UsrSuperJump, true);
            }
            else
            {
                // m_iAirDash holds double-jump status - 0 = none/single jump, 1 = double jump, 2 = atomiser jump.
                // We want to super-jump if AirDash is 1 normally, or if 2 when the atomiser is equipped.
                new dashVal = 1;
                new weap = GetPlayerWeaponSlot(client, SLOT_MELEE);
                if ( IsValidEntity(weap) )
                {
                    if ( GetEntProp(weap, Prop_Send, "m_iItemDefinitionIndex") == 450 ) dashVal = 2;
                }
                
                if ( GetEntProp(client, Prop_Send, "m_iAirDash") >= dashVal )
                {
                    new Handle:pack;
                    CreateDataTimer(0.1, Timer_ScoutJump, pack);
                    WritePackCell(pack, GetClientUserId(client));
                }
            }
        }
    }
    else    // The zombie has super-jumped - keep an eye out for when they next land on the ground.
    {
        if ( GetEntPropEnt(client, Prop_Data, "m_hGroundEntity") >= 0 ) PD_SetFlag(index, UsrSuperJump, false);
    }
    
    PD_SetFlag(index, UsrJumpPrevFrame, (buttons & IN_JUMP) == IN_JUMP);
    
    return Plugin_Continue;
}

// =======================================================================================
// =================================== Custom functions ==================================
// =======================================================================================

/*    Keeps all the functions common to RoundWin and RoundStalemate together.    */
Event_RoundEnd()
{
    // Set the NOT_IN_ROUND flag.
    g_PluginState |= STATE_NOT_IN_ROUND;
    
    Cleanup(CLEANUP_ROUNDEND);
    
    if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
}

/*    Wins the round for the specified team.    */
stock RoundWin(team = 0)
{
    if ( !IsServerProcessing() || !IsValidEntity(0) ) return;
    
    new ent = ControlPointMaster();
    
    SetVariantInt(team);
    AcceptEntityInput(ent, "SetWinner");
}

stock ControlPointMaster(bool: reset = false)
{
    static cpm = INVALID_ENT_REFERENCE;
    
    if ( reset )
    {
        cpm = INVALID_ENT_REFERENCE;
        return -1;
    }
    
    if ( cpm == INVALID_ENT_REFERENCE )
    {
        new ent = FindEntityByClassname(-1, "team_control_point_master");
        
        if (ent <= MaxClients)
        {
            ent = CreateEntityByName("team_control_point_master");
            if ( ent <= MaxClients ) ThrowError("Could not create team_control_point_master!");
            
            DispatchKeyValue(ent, "targetname", TFBH_CPM);
            DispatchSpawn(ent);
            AcceptEntityInput(ent, "Enable");
        }
        else
        {
            DispatchKeyValue(ent, "targetname", TFBH_CPM);
        }
        
        cpm = EntIndexToEntRef(ent);
        return ent;
    }
    else
    {
        return EntRefToEntIndex(cpm);
    }
}

stock GetControlPointMasterName(String: name[], size)
{
    GetEntPropString(ControlPointMaster(), Prop_Data, "m_iName", name, size);
}

/*    Ends the round and cleans up.    */
stock RoundWinWithCleanup(team = 0)
{
    RoundWin(team);
    Cleanup(CLEANUP_ROUNDEND);
}

stock Cleanup(mode)
{
    new cvDebug = GetConVarInt(cv_Debug);
    
    switch (mode)
    {
        case CLEANUP_ROUNDEND:
        {
            if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ) return;
            
            // for ( new i = 0; i < MAXPLAYERS; i++ )
            // {
                // g_Health[i] = 0;
                // g_MaxHealth[i] = 0;
                // g_StartBoost[i] = false;
                // g_Rage[i] = 0.0;
                // g_TeleportLevel[i] = 0.0;
                // g_Raging[i] = false;
                // g_HasSuperJumped[i] = false;
                // g_PrevJumpState[i] = false;
                // g_Jarate[i] = -1;
                // g_UtilFlags[i] = FLAG_NONE;
            // }
            
            PD_Reset();         // Reset sets defaults to all, which is what we want. The default state flag has zombification set.
            g_NextJarate = 0;
            g_RoundTimer = INVALID_ENT_REFERENCE;
            ControlPointMaster(true);
        }
        
        case CLEANUP_FIRSTSTART:
        {
            if ( g_PluginState & STATE_DISABLED == STATE_DISABLED )    // Don't set up if we're not enabled.
            {
                LogMessage("Warning! CLEANUP_FIRSTSTART called when plugin is disabled!");
                return;
            }
            
            // Store current values for balance cvars
            if ( cv_Unbalance != INVALID_HANDLE )
            {
                cvdef_Unbalance = GetConVarInt(cv_Unbalance);
                LogMessage("Stored value for mp_teams_unbalance_limit: %d", cvdef_Unbalance);
            }
            
            if ( cv_Autobalance != INVALID_HANDLE )
            {
                cvdef_Autobalance = GetConVarInt(cv_Autobalance);
                LogMessage("Stored value for mp_autoteambalance: %d", cvdef_Autobalance);
            }
            
            if ( cv_Scramble != INVALID_HANDLE )
            {
                cvdef_Scramble = GetConVarInt(cv_Scramble);
                LogMessage("Stored value for mp_scrambleteams_auto: %d", cvdef_Scramble);
            }
            
            if ( cv_Stalemate != INVALID_HANDLE )
            {
                cvdef_Stalemate = GetConVarInt(cv_Stalemate);
                LogMessage("Stored value for mp_stalemate_enable: %d", cvdef_Stalemate);
            }
            
            if ( timer_ZRefresh == INVALID_HANDLE )
            {
                timer_ZRefresh = CreateTimer(0.2, Timer_ZombieHealthRefresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
            }
            
            if ( timer_Cond == INVALID_HANDLE )
            {
                timer_Cond = CreateTimer(1.0, Timer_CondRefresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
            }
            
            if ( hs_ZText == INVALID_HANDLE )
            {
                hs_ZText = CreateHudSynchronizer();
            }
            
            // Set balance cvars to desired values
            ServerCommand("mp_teams_unbalance_limit %d", DES_UNBALANCE);
            ServerCommand("mp_autoteambalance %d", DES_AUTOBALANCE);
            ServerCommand("mp_scrambleteams_auto %d", DES_SCRAMBLE);
            
            // If a round is currently in progress, end it.
            if ( g_PluginState & STATE_NOT_IN_ROUND != STATE_NOT_IN_ROUND )
            {
                RoundWinWithCleanup();
            }
            
            // Go through each player who is connected and set up their data.
            for ( new i = 1; i <= MaxClients; i++ )
            {
                if ( IsClientConnected(i) && !IsClientReplay(i) && !IsClientSourceTV(i) )
                {
                    if ( cvDebug & DEBUG_DATA == DEBUG_DATA ) LogMessage("Client %N is connected.", i);
                    
                    // Give the client a slot in the data arrays.
                    new index = PD_RegisterClient(i);
                    if ( index < 0 )
                    {
                        LogError("MAJOR ERROR: Cannot find a free data index for client %N (MaxClients %d, MAXPLAYERS %d).", i, MaxClients, MAXPLAYERS);
                        return;
                    }
                    
                    if ( cvDebug & DEBUG_DATA == DEBUG_DATA ) LogMessage("Client %N has user ID %d and data index %d.", i, GetClientUserId(i), index);

                    DHookEntity(hDamageHook, false, i); 
                    SDKHook(i, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
                    
                    if ( cvDebug & DEBUG_DATA == DEBUG_DATA ) LogMessage("Data at index %d: user ID %d, zombie %d.", index, _PD_GetUserId(index), _PD_IsFlagSet(index, UsrZombie));
                }
            }
            
            // Check player counts.
            if ( PlayerCountAdequate() ) g_PluginState &= ~STATE_FEW_PLAYERS;
            else g_PluginState |= STATE_FEW_PLAYERS;
            
            ControlPointMaster(true);
        }
        
        case CLEANUP_ENDALL:    // Called when the plugin is unloaded or is disabled.
        {
            new cvdebug = GetConVarInt(cv_Debug);
            if ( cvdebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("Ending plugin:");
            // Reset balance cvars
            ServerCommand("mp_teams_unbalance_limit %d", cvdef_Unbalance);
            ServerCommand("mp_autoteambalance %d", cvdef_Autobalance);
            ServerCommand("mp_scrambleteams_auto %d", cvdef_Scramble);
            
            // End the current round in progress.
            if ( cvdebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("Winning round.");
            RoundWin();
            
            // for ( new i = 0; i < MAXPLAYERS; i++ )
            // {
                // ClearAllArrayDataForIndex(i, true);
            // }
            if ( cvdebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("Resetting data arrays.");
            PD_Reset(true);
            
            if ( cvdebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("Killing timers.");
            if ( timer_ZRefresh != INVALID_HANDLE )
            {
                KillTimer(timer_ZRefresh);
                timer_ZRefresh = INVALID_HANDLE;
            }
            
            if ( timer_Cond != INVALID_HANDLE )
            {
                KillTimer(timer_Cond);
                timer_Cond = INVALID_HANDLE;
            }
            
            if ( hs_ZText != INVALID_HANDLE )
            {
                CloseHandle(hs_ZText);
                hs_ZText = INVALID_HANDLE;
            }
            
            ControlPointMaster(true);
        }
        
        case CLEANUP_ROUNDSTART:    // Called even if plugin is disabled, so don't put anything important here.
        {
            PD_Reset();
        }
        
        case CLEANUP_MAPSTART:
        {
            // MapStart gets called when the plugin is loaded as well as OnPluginStart.
            // If PluginStart has already run, reset the flag and exit.
            // This is to make sure the data indices don't get cleared multiple times.
            if ( b_Setup )
            {
                b_Setup = false;
                return;
            }
            
            if ( timer_ZRefresh == INVALID_HANDLE )
            {
                timer_ZRefresh = CreateTimer(0.2, Timer_ZombieHealthRefresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
            }
            
            if ( timer_Cond == INVALID_HANDLE )
            {
                timer_Cond = CreateTimer(1.0, Timer_CondRefresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
            }
            
            if ( hs_ZText == INVALID_HANDLE )
            {
                hs_ZText = CreateHudSynchronizer();
            }
            
            // Reset all data arrays.
            // Is this needed?
            PD_Reset(true);
            
            new gamerules = FindEntityByClassname(-1, "tf_gamerules");
            
            if ( gamerules < 1 )
            {
                gamerules = CreateEntityByName("tf_gamerules");
                
                if ( gamerules < 1 )
                {
                    LogError("ERROR: tf_gamerules unable to be found or created!");
                    return;
                }
                
                DispatchKeyValue(gamerules, "targetname", "tf_gamerules");
                
                if ( !DispatchSpawn(gamerules) )
                {
                    LogError("ERROR: tf_gamerules unable to be found or created!");
                    return;
                }
            }
            
            g_GameRules = EntIndexToEntRef(gamerules);
            g_RoundTimer = INVALID_ENT_REFERENCE;
            ControlPointMaster(true);
        }
        
        case CLEANUP_MAPEND:
        {
            // Reset all data arrays.
            PD_Reset(true);
            
            if ( timer_ZRefresh != INVALID_HANDLE )
            {
                KillTimer(timer_ZRefresh);
                timer_ZRefresh = INVALID_HANDLE;
            }
            
            if ( timer_Cond != INVALID_HANDLE )
            {
                KillTimer(timer_Cond);
                timer_Cond = INVALID_HANDLE;
            }
            
            if ( hs_ZText != INVALID_HANDLE )
            {
                CloseHandle(hs_ZText);
                hs_ZText = INVALID_HANDLE;
            }
            
            g_GameRules = INVALID_ENT_REFERENCE;
            g_RoundTimer = INVALID_ENT_REFERENCE;
            ControlPointMaster(true);
        }
    }
}

/*  Returns true if there are enough players to play a match.
    Own function for convenience.    */
stock bool:PlayerCountAdequate()
{
    if ( !IsServerProcessing() ) return false;
    else if ( GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE) > 1 ) return true;
    else return false;
}

/*    Steps to make a client a zombie:
    - Kill their buildings
    - Change their team
    - Mark them as a zombie in the data arrays
    - Resupply them
    - Set their health multiplier
    - Take away any disallowed weapons
    - Equip melee    */
stock MakeClientZombie2(client)
{
    KillBuildings(client, BUILD_SENTRY | BUILD_DISPENSER | BUILD_TELEPORTER);    // Kill the client's buildings (class is checked in function).
    
    new index = _PD_GetClientSlot(client);
    
    TF2_RemoveCondition(client, TFCond_Taunting);       // Zombification while taunting could cause issues.
    PD_SetFlag(index, UsrZombie, true);                 // Mark the client as a zombie.
    PD_SetRageLevel(index, 0.0);                        // Reset their rage.
    PD_SetTeleportLevel(index, 0.0);                    // Reset their teleport level.
    PD_SetFlag(index, UsrRaging, false);                // Flag not raging.
    PD_SetFlag(index, UsrSuperJump, false);             // Reset jump state.
    PD_SetFlag(index, UsrJumpPrevFrame, false);         // Reset previous frame's jump button state.
    
    new tempstate = GetEntProp(client, Prop_Send, LIFESTATE_PROP);
    SetEntProp(client, Prop_Send, LIFESTATE_PROP, 2);               // Make sure the client won't die when we change their team.
    ChangeClientTeam(client, TEAM_BLUE);                            // Change them to Blue.
    SetEntProp(client, Prop_Send, LIFESTATE_PROP, tempstate);       // Reset the lifestate variable.
    TF2_RegeneratePlayer(client);                                   // Resupply.
    
    if ( GetConVarInt(cv_Debug) & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("%N's class : %d", client, TF2_GetPlayerClass(client));
    SetLargeHealth(client);
    
    ManageZombieWeapons(client);                                    // Remove appropriate weapons.
    EquipSlot(client, SLOT_MELEE);                                  // Equip melee.
}

/*    Removes/replaces a client's weapons that are disallowed when they are a zombie.    */
stock ManageZombieWeapons(client)
{
    // Check weapons are allowed.
    CheckWeaponSlot(client, SLOT_PRIMARY);
    CheckWeaponSlot(client, SLOT_SECONDARY);
    CheckWeaponSlot(client, SLOT_MELEE);

    switch (TF2_GetPlayerClass(client))
    {
        /*case TFClass_Scout, TFClass_Sniper, TFClass_Soldier, TFClass_DemoMan, TFClass_Medic, TFClass_Heavy, TFClass_Pyro:
        {
            // Check weapons are allowed.
            CheckWeaponSlot(client, SLOT_PRIMARY);
            CheckWeaponSlot(client, SLOT_SECONDARY);
            CheckWeaponSlot(client, SLOT_MELEE);
        }*/
        
        case TFClass_Spy, TFClass_Engineer:
        {
            // Check PDA slots for these classes.
            CheckWeaponSlot(client, 3);
            CheckWeaponSlot(client, 4);
            CheckWeaponSlot(client, 5);
        }
    }
}

/*    Performs checks on a client's weapon in a specific slot.    */
stock CheckWeaponSlot(client, slotnumber)
{
    new slot = GetPlayerWeaponSlot(client, slotnumber);
    if ( IsValidEntity(slot) )
    {
        decl String:classname[64];
        if ( GetEntityClassname(slot, classname, sizeof(classname)) && StrContains(classname, "tf_weapon", false) != -1 )
        {
            if ( slotnumber == SLOT_MELEE )    // Melee is a blacklist, other is a whitelist.
            {
                new currentIndex = GetEntProp(slot, Prop_Send, "m_iItemDefinitionIndex");
                decl String:weaponName[32];
                new newIndex = IsZMeleeAllowed(currentIndex, weaponName, sizeof(weaponName));
                
                if ( currentIndex != newIndex )    // If the melee weapon should be replaced:
                {
                    TF2_RemoveWeaponSlot(client, slotnumber);                                                // Remove the melee weapon.
                    new weapon = GiveClientWeapon(client, weaponName, newIndex, GetRandomInt(0, 100), 0);    // Replace it.
                    if ( weapon != -1 ) EquipPlayerWeapon(client, weapon);                                    // Equip it.
                }
            }
            else
            {
                if ( !IsZWeaponAllowed(GetEntProp(slot, Prop_Send, "m_iItemDefinitionIndex")) ) TF2_RemoveWeaponSlot(client, slotnumber);    // Remove if not allowed.
            }
        }
        else TF2_RemoveWeaponSlot(client, slotnumber);
    }
}

/*    Streamlines giving a client a weapon through TF2Items.
    With this function the attributes passed do not have to be constant at compile time,
    as opposed to the string-based version from the Saxton Hale function.    */
stock GiveClientWeapon(client, String:name[], index, level, quality, attIndex[] = {}, Float:attValue[] = {}, attNum = 0)
{
    new Handle:weapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);    // Create a weapon handle to store weapon info.
    if ( weapon == INVALID_HANDLE ) return -1;
    
    // Set up basic params.
    TF2Items_SetClassname(weapon, name);
    TF2Items_SetItemIndex(weapon, index);
    TF2Items_SetLevel(weapon, level);
    TF2Items_SetQuality(weapon, quality);
    
    // Set up attributes:
    if ( attNum > 15 ) attNum = 15;                // Clamp this to the maximum allowed number of attributes.
    else if ( attNum < 0 ) attNum = 0;
    
    TF2Items_SetNumAttributes(weapon, attNum);    // Specify how many attributes we'll have.
    
    // Iterate through the list to assign attributes.
    for ( new i = 0; i < attNum; i++ )
    {
        TF2Items_SetAttribute(weapon, i, attIndex[i], attValue[i]);
    }
    
    // Create the weapon itself.
    new entity = TF2Items_GiveNamedItem(client, weapon);
    CloseHandle(weapon);
    
    return entity;
}

// Copied the Saxton Hale giveweapon function verbatim because in some cases the conciseness of the string attribute format is preferred.
// Can we overload functions in SP?
// Nope.
stock GiveClientWeapon2(client, String:name[], index, level, qual, String:att[])
{
    new Handle:hWeapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
    if (hWeapon == INVALID_HANDLE)
        return -1;
    TF2Items_SetClassname(hWeapon, name);
    TF2Items_SetItemIndex(hWeapon, index);
    TF2Items_SetLevel(hWeapon, level);
    TF2Items_SetQuality(hWeapon, qual);
    
    new String:atts[32][32];
    new count = ExplodeString(att, " ; ", atts, 32, 32);
    if (count > 0)
    {
        TF2Items_SetNumAttributes(hWeapon, count/2);
        new i2 = 0;
        for (new i = 0; i < count; i += 2)
        {
            TF2Items_SetAttribute(hWeapon, i2, StringToInt(atts[i]), StringToFloat(atts[i+1]));
            i2++;
        }
    }
    else
        TF2Items_SetNumAttributes(hWeapon, 0);

    new entity = TF2Items_GiveNamedItem(client, hWeapon);
    CloseHandle(hWeapon);
    //EquipPlayerWeapon(client, entity);
    return entity;
}

stock ValidateSurvivorWeapons(client)
{
    for ( new slot = SLOT_PRIMARY; slot <= SLOT_MELEE; slot++ )
    {
        new weapon = GetPlayerWeaponSlot(client, slot);
        if ( IsValidEntity(weapon) )
        {
            new currentIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
            decl String:weaponName[32];
            new newIndex = IsSWeaponAllowed(currentIndex, weaponName, sizeof(weaponName));
            
            if ( currentIndex != newIndex )    // If the weapon should be replaced:
            {
                TF2_RemoveWeaponSlot(client, slot);                                                    // Remove the weapon.
                new weap = GiveClientWeapon(client, weaponName, newIndex, GetRandomInt(0, 100), 0);    // Replace it.
                if ( weap != -1 ) EquipPlayerWeapon(client, weap);                                    // Equip it.
            }
        }
    }
    
    // TODO: Move the following into a neat separate file just for the sake of my sanity.
    switch(TF2_GetPlayerClass(client))
    {
        // TODO: Don't think this works?
        case TFClass_Sniper:    // Add explosive sniper shots for the standard sniper and its reskins.
        {
            new weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);
            
            if (GetEntProp(weapon, Prop_Send, "m_iEntityQuality") != 10)    // Quality 10 means it's already been replaced.
            {
                new idindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
                if ( idindex == -1 ) idindex = 17;
                decl String:atts[128];
                atts[0] = '\0';
                
                switch (idindex)
                {
                    case 14, 201, 664, 792, 801, 851, 881, 890, 899, 908, 957, 966:
                    {
                        Format(atts, sizeof(atts), "%s", defSniperRifle);
                    }
                }
                
                TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);
                new ent = GiveClientWeapon2(client, "tf_weapon_sniperrifle", idindex, GetRandomInt(0, 100), 10, atts);
                EquipPlayerWeapon(client, ent);
            }
        }
        
        case TFClass_Medic:    // Add uber on hit for syringe gun.
        {
            new weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);
            
            if (GetEntProp(weapon, Prop_Send, "m_iEntityQuality") != 10)    // Quality 10 means it's already been replaced.
            {
                new idindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
                if ( idindex == -1 ) idindex = 17;
                new numAtts = 0, attIndex[15], Float:attValue[15];
                
                switch(idindex)
                {
                    case 17, 204:    // Syringe gun (strange)
                    {
                        attIndex[0] = UBER_ON_HIT;
                        attValue[0] = GetConVarFloat(cv_UberOnHit)/100.0;
                        numAtts = 1;
                    }
                    
                    case 36:    // Blutsauger
                    {
                        attIndex[0] = UBER_ON_HIT;
                        attValue[0] = GetConVarFloat(cv_UberOnHit)/100.0;
                        
                        attIndex[1] = HEALTH_ON_HIT;
                        attValue[1] = 3.0;
                        
                        attIndex[2] = HEALTH_REGEN;
                        attValue[2] = -2.0;
                        numAtts = 3;
                    }
                    
                    case 305:    // Crusader's Crossbow
                    {
                        attIndex[0] = UBER_ON_HIT;
                        attValue[0] = GetConVarFloat(cv_UberOnBolt)/100.0;
                        
                        attIndex[1] = HEALING_BOLTS;
                        attValue[1] = 1.0;
                        
                        attIndex[2] = REDUCE_PRI_AMMO;
                        attValue[2] = 0.25;
                        
                        attIndex[3] = DECREASED_RELOAD;
                        attValue[3] = 0.6;
                        numAtts = 4;
                    }
                    
                    case 412:    // Overdose
                    {
                        attIndex[0] = UBER_ON_HIT;
                        attValue[0] = GetConVarFloat(cv_UberOnHit)/100.0;
                        
                        attIndex[1] = LUNCHBOX_MINICRITS;    // (For some reason I think this is speed depending on Uber)
                        attValue[1] = 1.0;
                        
                        attIndex[2] = DECREASED_DAMAGE;
                        attValue[2] = 0.9;
                        numAtts = 3;
                    }
                }
                
                TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);
                new ent = GiveClientWeapon(client, (idindex == 305) ? "tf_weapon_crossbow" : "tf_weapon_syringegun_medic", idindex, GetRandomInt(0, 100), 10, attIndex, attValue, numAtts);
                EquipPlayerWeapon(client, ent);
            }
        }
        
        // I wrote this ages ago and now I'm really not sure what it does.
        // I think it forces custom attributes that are defined at the beginning of the file.
        case TFClass_Engineer:
        {
            new weapon = GetPlayerWeaponSlot(client, SLOT_MELEE);
            
            if (GetEntProp(weapon, Prop_Send, "m_iEntityQuality") != 10)    // Quality 10 means it's already been replaced.
            {
                new idindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
                if ( idindex == -1 ) idindex = 17;
                decl String:atts[128];
                atts[0] = '\0';
                
                switch (idindex)
                {
                    case 7, 197, 662, 795, 804, 884, 893, 902, 911, 960, 969:
                    {
                        Format(atts, sizeof(atts), "%s", defWrench);
                    }
                    
                    case 169, 423:
                    {
                        Format(atts, sizeof(atts), "%s", defGoldenWrench);
                    }
                    
                    case 142:
                    {
                        Format(atts, sizeof(atts), "%s", defGunslinger);
                    }
                    
                    case 155:
                    {
                        Format(atts, sizeof(atts), "%s", defSouthHosp);
                    }
                    
                    case 329:
                    {
                        Format(atts, sizeof(atts), "%s", defJag);
                    }
                    
                    case 589:
                    {
                        Format(atts, sizeof(atts), "%s", defEurekaEffect);
                    }
                }
                
                TF2_RemoveWeaponSlot(client, SLOT_MELEE);
                new ent = GiveClientWeapon2(client, (idindex == 142) ? "tf_weapon_robot_arm" : "tf_weapon_wrench", idindex, GetRandomInt(0, 100), 10, atts);
                EquipPlayerWeapon(client, ent);
            }
        }
    }
}

/*    Returns whether a primary/secondary weapon with a specified item definition index is allowed.
    Effectively a whitelist that keeps all the ID indices together.
    Note that this does not include melee.*/
stock bool:IsZWeaponAllowed(index)
{
    /*    ========== Allowed weapons: ==========
        [46]    Bonk
        [60]    Cloak and Dagger
        [163]    Crit-a-Cola
        [59]    Dead Ringer
        [27]    Disguise Kit
        [297]    Enthusiast's Timepiece
        [30]    Invisibility Watch
        [212]    Invisibility Watch (Renamed/Strange)
        [58]    Jarate
        [222]    Mad Milk
        [947]    Quackenbirdt
        [810]    Red-Tape Recorder
        [831]    Red-Tape Recorder (Genuine)
        [735]    Sapper
        [736]    Sapper (Renamed/Strange)
        ======================================    */
        
    switch(index)
    {
        case 27, 30, 46, 58, 59, 60, 163, 222, 297, 735, 736, 810, 831, 947:    return true;
    }
    
    return false;
}
/*    If a melee weapon is disallowed, returns the item def index of the weapon it
    should be replaced with, along with the weapon name.
    This is a blacklist instead of a whitelist, since melee by default is allowed.    */
stock IsZMeleeAllowed(index, String:name[] = {}, maxlength = 0)
{
    switch(index)
    {
        //case 404:    { Format(name, maxlength, "tf_weapon_sword");        return 132;    }    // Persian Persuader    --->    Eyelander
        case 656:     { Format(name, maxlength, "tf_weapon_fists");        return 5;    }    // Holiday Punch        --->    Fists
    }
    
    return index;
}

/*    If a survivor weapon is disallowed, returns the item def index of the weapon it
    should be replaced with, along with the weapon name.    */
stock IsSWeaponAllowed(index, String:name[] = {}, maxlength = 0)
{
    switch(index)
    {
        case 60:    { Format(name, maxlength, "tf_weapon_invis");        return 30;    }    // Cloak and Dagger        --->    Invis Watch
        //case 226:    { Format(name, maxlength, "tf_weapon_buff_item");    return 129;    }    // Batallion's Backup    --->    Buff Banner
        case 331:    { Format(name, maxlength, "tf_weapon_fists");        return 5;    }    // Fists of Steel        --->    Fists
        case 772:    { Format(name, maxlength, "tf_weapon_scattergun");    return 13;    }    // Baby Face's Blaster    --->    Scattergun
    }
    
    return index;
}

/*    Deals with setting a client's health.    */
stock SetLargeHealth(client)
{
    new i_maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
    new Float:maxHealth = float(i_maxHealth);                                    // Get the client's current max health.
    new newHealth = RoundToCeil(maxHealth * CalculateZombieHealthMultiplier());    // Calculate the new max health.
    
    if ( GetConVarInt(cv_Debug) & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("%N's max health: %d", client, newHealth);
    
    SetEntProp(client, Prop_Data, "m_iMaxHealth", newHealth);    // Update the client's max health value.
    SetEntProp(client, Prop_Send, "m_iHealth", newHealth);
    
    new slot = _PD_GetClientSlot(client);
    PD_SetCurrentHealth(slot, newHealth);
    PD_SetMaxHealth(slot, i_maxHealth);
}

/*    Kills the specified buildings owned by a client.    */
stock KillBuildings(client, flags)
{
    if ( client < 1 || client > MaxClients || !IsClientInGame(client) || TF2_GetPlayerClass(client) != TFClass_Engineer ) return;
    
    // Sentries:
    if ( (flags & BUILD_SENTRY) == BUILD_SENTRY )
    {
        new ent = -1;
        while ( (ent = FindEntityByClassname(ent, "obj_sentrygun")) != -1 )
        {
            if ( IsValidEntity(ent) && GetEntPropEnt(ent, Prop_Send, "m_hBuilder") == client )
            {
                SetVariantInt( GetEntProp(ent, Prop_Send, "m_iMaxHealth") + 1 );
                AcceptEntityInput(ent, "RemoveHealth");
                AcceptEntityInput(ent, "Kill");
            }
        }
    }
    
    // Dispensers:
    if ( (flags & BUILD_DISPENSER) == BUILD_DISPENSER )
    {
        new ent = -1;
        while ( (ent = FindEntityByClassname(ent, "obj_dispenser")) != -1 )
        {
            if ( IsValidEntity(ent) && GetEntPropEnt(ent, Prop_Send, "m_hBuilder") == client )
            {
                SetVariantInt( GetEntProp(ent, Prop_Send, "m_iMaxHealth") + 1 );
                AcceptEntityInput(ent, "RemoveHealth");
                AcceptEntityInput(ent, "Kill");
            }
        }
    }
    
    // Teleporters
    if ( (flags & BUILD_TELEPORTER) == BUILD_TELEPORTER )
    {
        new ent = -1;
        while ( (ent = FindEntityByClassname(ent, "obj_teleporter")) != -1 )
        {
            if ( IsValidEntity(ent) && GetEntPropEnt(ent, Prop_Send, "m_hBuilder") == client )
            {
                SetVariantInt( GetEntProp(ent, Prop_Send, "m_iMaxHealth") + 1 );
                AcceptEntityInput(ent, "RemoveHealth");
                AcceptEntityInput(ent, "Kill");
            }
        }
    }
}

/*    Calculates what multiple of normal health a zombie should have.    */
stock Float:CalculateZombieHealthMultiplier()
{
    new Float:zMin = GetConVarFloat(cv_ZHMin);
    new Float:zMax = GetConVarFloat(cv_ZHMax);
    new Float:zMinPl = GetConVarFloat(cv_ZHMinPlayers);
    new Float:zMaxPl = GetConVarFloat(cv_ZHMaxPlayers);
    new cvDebug = GetConVarInt(cv_Debug);
    
    // Health is determined on a per-spawn basis, linearly interpolated between a minimum and maximum health multiplier.
    // Minimum health is given when there are 'zMinPl' opponents on Red, and maximum given when there are 'zMaxPl' or greater.
    
    // Firstly, clamp the health proportion values. Min should not be greater than max.
    if ( zMin > zMax )
    {
        LogMessage("tfbh_zhscale_min %f larger than tfbh_zhscale_max %f.", zMin, zMax);
        
        zMax = zMin;    // Set max health to match min health.
    }
    
    if ( zMinPl > zMaxPl )
    {
        LogMessage("tfbh_zhscale_minplayers %d larger than tfbh_zhscale_maxplayers %d.", zMinPl, zMaxPl);
        
        zMaxPl = zMinPl;    // Set max to match min.
    }
    
    // Value = number of players left alive on Red.
    // A = min players
    // B = max players
    // X = min health multiplier
    // Y = max health multiplier
    // As number of players alive grows smaller, health multiplier gets smaller.
    
    // Get the number of live players on Red.
    new redCount;
    
    for ( new i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) ) redCount++;
    }
    
    if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("%d players alive on Red.", redCount);
    
    // Calculate the raw multiplier value.
    new Float:multiplier = Remap(float(redCount), zMinPl, zMaxPl, zMin, zMax);
    
    if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("Raw multiplier: %f", multiplier);
    
    // Clamp the multiplier value to fall within our limits.
    if ( multiplier < zMin )
    {
        if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("Multiplier %f < %f, clamping.", multiplier, zMin);
        multiplier = zMin;
    }
    else if ( multiplier > zMax )
    {
        if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("Multiplier %f > %f, clamping.", multiplier, zMax);
        multiplier = zMax;
    }
    else if ( multiplier <= 0.0 )    // If the multiplier is <= 0, return 1.
    {
        if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("Multiplier <= 0, clamping to 1.0.");
        multiplier = 1.0;
    }
    
    return multiplier;
}

/*    Equips a weapon given a slot.    */
stock EquipSlot(client, slot)
{
    if ( client < 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) ||
            GetClientTeam(client) > TEAM_BLUE || GetClientTeam(client) < TEAM_RED ) return;
    
    new weapon = GetPlayerWeaponSlot(client, slot);
    if ( weapon == -1 || !IsValidEntity(weapon) ) return;
    
    EquipPlayerWeapon(client, weapon);
}

/*    Calculates a more representative point of reference for radial player checks.    */
stock CalcPlayerMidpoint(client, Float:out[3])
{
    new Float:mins[3], Float:maxs[3];
    GetEntPropVector(client, Prop_Send, "m_vecMins", mins);
    GetEntPropVector(client, Prop_Send, "m_vecMaxs", maxs);
    
    // Calculate the centre of the client's bounding box.
    for ( new j = 0; j <= 2; j++ )
    {
        out[j] = (maxs[j] - mins[j])/2.0;
    }
}

/*    Tints a zombie depending on their health.    */
stock TintZombie(client)
{
    // RGB of colour we want to tint at full intensity: 41 138 30
    // If the health level is at normal class level or below, tint with 255 255 255
    // If the health level is normal class level * tfbh_zhscale_max (or above), tint with 41 138 30
    
    if ( client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_BLUE ) return;
    
    new index = _PD_GetClientSlot(client);
    new R = 255, G = 255, B = 255;
    new Float:classmax;
    new Float:zMax = GetConVarFloat(cv_ZHMax);    // tfbh_zhscale_max can never be below 1.0, so no trouble with inverse relationships here.
    
    // Value = g_Health[index]
    // A = normal class level
    // B = normal class level * tfbh_zhscale_max
    // X = 255
    // Y = max tint
    
    switch (TF2_GetPlayerClass(client))
    {
        case TFClass_Scout:     classmax = 125.0;
        case TFClass_Sniper:    classmax = 125.0;
        case TFClass_Soldier:   classmax = 200.0;
        case TFClass_DemoMan:   classmax = 175.0;
        case TFClass_Heavy:     classmax = 300.0;
        case TFClass_Medic:     classmax = 150.0;
        case TFClass_Pyro:      classmax = 175.0;
        case TFClass_Spy:       classmax = 125.0;
        case TFClass_Engineer:  classmax = 125.0;
        default:                classmax = 125.0;
    }
    
    R = RoundFloat(Remap(float(_PD_GetCurrentHealth(index)), classmax, classmax * zMax, 255.0, 41.0));    
    if ( R < 41 ) R = 41;                                                                    // Clamp value, eg. if health is less than normal class max.
    else if ( R > 255 ) R = 255;
    
    G = RoundFloat(Remap(float(_PD_GetCurrentHealth(index)), classmax, classmax * zMax, 255.0, 138.0));
    if ( G < 138 ) G = 138;
    else if ( G > 255 ) G = 255;
    
    B = RoundFloat(Remap(float(_PD_GetCurrentHealth(index)), classmax, classmax * zMax, 255.0, 30.0));
    if ( B < 30 ) B = 30;
    else if ( B > 255 ) B = 255;
    
    SetEntityRenderColor(client, R, G, B, 255);    // Set the client's colour.
}

/*    Remaps value on a scale of a-b to a scale of x-y.
    As value approaches a, return approaches x.
    As value approaches b, return approaches y.
    For inverse relationships, make b larger than a (where x and y remain the same).
    
    |----------|----|
    a          v    b
               |
    |----------+----|
    x          |    y
            return
    */
stock Float:Remap(Float:value, Float:a, Float:b, Float:x, Float:y)
{
    // Don't divide by zero!
    if ( b == a ) return x+((y-x)/2);    // Technically this is undefined but the midpoint should be good enough as a failsafe.
    
    return x + (((value-a)/(b-a)) * (y-x));
}

stock ModifyRespawnTimes()
{
    new gamerules = EntRefToEntIndex(g_GameRules);
    if ( !IsValidEntity(gamerules) ) return;
    
    new min = GetConVarInt(cv_ZRespawnMin);
    new max = GetConVarInt(cv_ZRespawnMax);
    new totalPlayers = GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE);
    new redPlayers;
    
    for ( new i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) ) redPlayers++;
    }
    
    // Value: Number of players alive on Red
    // A: Total players on Red and Blue
    // B: 1 player
    // X: min
    // Y: max
    
    new respawnWave = RoundFloat(Remap(float(redPlayers), float(totalPlayers), 1.0, float(min), float(max)));
    if ( respawnWave > max) respawnWave = max;
    else if ( respawnWave < min ) respawnWave = min;
    
    SetVariantInt(respawnWave);
    AcceptEntityInput(gamerules, "SetBlueTeamRespawnWaveTime");
}

/*    Given a client and a weapon classname, returns the weapon's entindex, or -1 on failure.    */
stock GetClientWeaponFromName(client, String:name[])
{
    // Cycle through slots for player.
    for ( int i = 0; i <= 5; i++ )
    {
        TFClassType:class = TF2_GetPlayerClass(client);
        if ( (i == 3 || i == 4) && class != TFClass_Engineer && class != TFClass_Spy ) break;
        else if ( i == 5 && class != TFClass_Engineer ) break;
        
        new index = GetPlayerWeaponSlot(client, i);
        decl String::classname[64];
        GetEntityClassname(index, classname, sizeof(classname));
        
        if ( strcmp(name, classname) == 0 ) return index;
    }
    
    return -1;
}

/*    Builds and fires a death message when a zombie kills a human.    */
stock bool:BuildZombieMessage(client, attacker, inflictor, damagetype, weapon)
{
    // From what I can see of Saxton Hale, the "weapon" string in the death event defines what icon will be displayed.
    // "unarmed_combat" for the Unarmed Combat weapon.
    
    new Handle:event = CreateEvent("player_death", true);
    if ( event == INVALID_HANDLE ) return false;
    
    SetEventInt(event, "userid", GetClientUserId(client));
    SetEventInt(event, "victim_entindex", client);
    SetEventInt(event, "inflictor_entindex", inflictor);
    SetEventInt(event, "attacker", (attacker > 0 && attacker <= MaxClients) ? GetClientUserId(attacker) : -1);
    SetEventInt(event, "damagebits", damagetype);
    
    SetEventString(event, "weapon", "unarmed_combat");
    SetEventString(event, "weapon_logclassname", "unarmed_combat");
    SetEventInt(event, "weaponid", TF_WEAPON_BAT);
    
    SetEventInt(event, "customkill", 0);
    SetEventInt(event, "assister", -1);
    SetEventInt(event, "stun_flags", 0);
    SetEventInt(event, "death_flags", 0);
    SetEventBool(event, "silent_kill", false);
    SetEventInt(event, "playerpenetratecount", 0);
    SetEventString(event, "assister_fallback", "");
    
    FireEvent(event);
    return true;
}

/*    Calculates the average distance from a client to nearest players.
    Specify the team to check (pass TEAM_INVALID to ignore) and the number of players.
    Returns -1.0 on failure.    */
stock Float:CalcAvgDistance(client, team, number)
{
    if ( client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) ) return -1.0;
    
    new Float:cOrigin[3];
    //GetClientAbsOrigin(client, cOrigin);
    CalcPlayerMidpoint(client, cOrigin);
    
    // Build a list of distances.
    new teamcount, Float:distances[MaxClients];
    
    for ( new i = 1; i <= MaxClients; i++ )
    {
        // If the player is alive and on the correct team, insert their distance into the array.
        if ( IsClientInGame(i) && IsPlayerAlive(i) )
        {
            if ( team != TEAM_INVALID && GetClientTeam(i) != team ) continue;
            
            new Float:iOrigin[3];
            //GetClientAbsOrigin(i, iOrigin);
            CalcPlayerMidpoint(i, iOrigin);
            distances[teamcount] = GetVectorDistance(cOrigin, iOrigin);
            
            teamcount++;
        }
    }
    
    if ( teamcount < 1 ) return -1.0;
    
    // Array has been built and there is at least one entry.
    // Sort the array into ascending order.
    SortFloats(distances, teamcount);
    
    // Take the average of the number of nearest players specified.
    new Float:average;
    if ( number > teamcount ) number = teamcount;    // Make sure we don't try and average more than the number of players we found.
    
    for ( new i = 0; i < number; i++ )
    {
        average += distances[i];
    }
    
    return average / float(number);
}

/*    Thanks SaxtonHale.    */
stock AttachParticle(ent, String:particleType[], Float:offset = 0.0, bool:battach = true)
{
    new particle = CreateEntityByName("info_particle_system");
    
    decl String:tName[32];
    new Float:pos[3];
    GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
    pos[2] += offset;
    TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
    
    Format(tName, sizeof(tName), "target%i", ent);
    DispatchKeyValue(ent, "targetname", tName);
    DispatchKeyValue(particle, "targetname", "tf2particle");
    DispatchKeyValue(particle, "parentname", tName);
    DispatchKeyValue(particle, "effect_name", particleType);
    DispatchSpawn(particle);
    
    if (battach)
    {
        SetVariantString(tName);
        AcceptEntityInput(particle, "SetParent", particle, particle, 0);
        SetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity", ent);
    }
    
    ActivateEntity(particle);
    AcceptEntityInput(particle, "start");
    return particle;
}

public Action:Timer_EnableStunnedSentry(Handle:timer, Handle:pack)
{
    // Unpack the data.
    SetPackPosition(pack, 0);
    new sentry = EntRefToEntIndex(ReadPackCell(pack));
    new particle = EntRefToEntIndex(ReadPackCell(pack));
    CloseHandle(pack);
    
    if ( IsValidEntity(sentry) )
    {
        decl String:classname[64];
        GetEntityClassname(sentry, classname, sizeof(classname));
        
        if ( StrEqual(classname, "obj_sentrygun") ) SetEntProp(sentry, Prop_Send, "m_bDisabled", 0);
    }
    
    if ( IsValidEntity(particle) )
    {
        decl String:classname[64];
        GetEntityClassname(particle, classname, sizeof(classname));
        
        if ( StrEqual(classname, "info_particle_system") ) AcceptEntityInput(particle, "Kill");
    }
}

public Action:Timer_CheckTeams(Handle:timer)
{
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
            g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
            g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return;
    
    new redCount;
    new cvDebug = GetConVarInt(cv_Debug);
    
    for ( new i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) ) redCount++;
    }
    
    if ( redCount < 1 )
    {
        if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Red team is out of players.");
        RoundWinWithCleanup(TEAM_BLUE);
        return;
    }
    
    ModifyRespawnTimes();
}

public Action:Timer_RespawnTelePlayer(Handle:timer, Handle:pack)
{
    ResetPack(pack);
    new userid = ReadPackCell(pack);
    new Float:clientPos[3], Float:clientAng[3];
    
    clientPos[0] = ReadPackFloat(pack);
    clientPos[1] = ReadPackFloat(pack);
    clientPos[2] = ReadPackFloat(pack);
    clientAng[0] = ReadPackFloat(pack);
    clientAng[1] = ReadPackFloat(pack);
    clientAng[2] = ReadPackFloat(pack);
    
    if ( userid < 1 ) return;
    
    new client = GetClientOfUserId(userid);
    if ( client < 1 || client > MaxClients || !IsClientInGame(client) ) return;
    TF2_RespawnPlayer(client);
    TeleportEntity(client, clientPos, clientAng, NULL_VECTOR);
}

/*    Periodically resets m_iHealth on zombies to their health value stored in g_Health.
    This is to negate the overheal effect when setting large values of health.
    NEW: Rage and other things are calculated here.    */
public Action:Timer_ZombieHealthRefresh(Handle:timer, Handle:pack)
{
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
            g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
            g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return Plugin_Handled;
    
    for ( new i = 1; i < MaxClients; i++ )
    {
        if ( IsClientInGame(i) && !IsClientReplay(i) && !IsClientSourceTV(i) )
        {
            new index = _PD_GetClientSlot(i);
            
            if ( GetClientTeam(i) == TEAM_BLUE && IsPlayerAlive(i) && _PD_IsFlagSet(index, UsrZombie) )
            {
                // Check whether the zombie's health is above what we last recorded. If it is, update.
                // Since health only drops over time, if we have more than last time then that's fine.
                new health = GetEntProp(i, Prop_Send, "m_iHealth");
                
                if ( health > _PD_GetCurrentHealth(index) ) PD_SetCurrentHealth(index, health);
                else
                {
                    SetEntProp(i, Prop_Send, "m_iHealth", _PD_GetCurrentHealth(index));
                }
                
                // Tint the zombie depending on his health level.
                if ( !TF2_IsPlayerInCondition(i, TFCond_Disguised) || (TF2_IsPlayerInCondition(i, TFCond_Disguised) && GetEntProp(i, Prop_Send, "m_nDisguiseTeam") == TEAM_BLUE)) TintZombie(i);
                else SetEntityRenderColor(i, 255, 255, 255, 255);
                
                new Float:debug_dist, Float:debug_rage;
                
                // Update the client's rage level.
                if ( !_PD_IsFlagSet(index, UsrRaging) )    // If not currently raging:
                {
                    new Float:dist = CalcAvgDistance(i, TEAM_RED, 3);    // Check the nearest 3 players on Red.
                    if ( GetConVarBool(cv_DebugRage) ) debug_dist = dist;
                    
                    // Remap: when a zombie is on average 128 units or closer to players, rage fills at 10% per second.
                    // When a zombie is on average 1024 units or further from players, rage fills at 1% per second.
                    // Timer is refired every 0.2 seconds, so rage should fill at 2% and 0.2% respectively each refire.
                    
                    // Value: avg dist
                    // A: near dist
                    // B: far dist
                    // X: high charge
                    // Y: low charge
                    new Float:mincharge = GetConVarFloat(cv_ZRageChargeFar)/5.0, Float:maxcharge = GetConVarFloat(cv_ZRageChargeClose)/5.0;            // Convar is % per sec, divide by 5 to get % per 0.2 sec.
                    new Float:rage = Remap(dist, GetConVarFloat(cv_ZRageCloseDist), GetConVarFloat(cv_ZRageFarDist), maxcharge, mincharge);
                    
                    // Clamp the rage value.
                    if ( rage < mincharge ) rage = mincharge;
                    else if ( rage > maxcharge ) rage = maxcharge;
                    
                    // If the zombie is Jarate'd or milked, take away some rage.
                    if ( TF2_IsPlayerInCondition(i, TFCond_Jarated) || TF2_IsPlayerInCondition(i, TFCond_Milked) ) rage -= (GetConVarFloat(cv_WetRagePenalty) / 5.0);
                    
                    if ( GetConVarBool(cv_DebugRage) ) debug_rage = rage;
                    
                    // Update the zombie's rage.
                    PD_IncrementRageLevel(index, rage);
                    if ( _PD_GetRageLevel(index) > 100.0 ) PD_SetRageLevel(index, 100.0);
                    else if ( _PD_GetRageLevel(index) < 0.0 ) PD_SetRageLevel(index, 0.0);
                }
                else    // If raging:
                {
                    // Work out how many points to deduct from the meter depending on the duration convar.
                    new Float:deduct = 20.0/GetConVarFloat(cv_ZRageDuration);    // 100/var per second, but we're refiring every 0.2 secs.
                    PD_DecrementRageLevel(index, deduct);
                    
                    // If we have now reached zero, clamp and disable rage.
                    if ( _PD_GetRageLevel(index) <= 0.0 )
                    {
                        PD_SetRageLevel(index, 0.0);
                        PD_SetFlag(index, UsrRaging, false);
                    }
                    else    // We're not at zero yet, apply effects that happen during duration of rage (stuns are handled in taunt hook).
                    {
                        // Apply crits to the raging player.
                        TF2_AddCondition(i, TFCond_HalloweenCritCandy, 0.25);
                        
                        // NOTE: This is reserved for Medics now.
                        // Apply mini-crits to players in the specified radius, as long as they do not already have crits.
                        /*new Float:cOrigin[3];
                        GetClientAbsOrigin(i, cOrigin);
                        
                        for ( new j = 1; j <= MaxClients; j++ )
                        {
                            if ( j != i && IsClientInGame(j) && GetClientTeam(j) == TEAM_BLUE && IsPlayerAlive(j) && g_Zombie[DataIndexForUserId(GetClientUserId(j))]
                            && !TF2_IsPlayerInCondition(j, TFCond_Buffed) && !TF2_IsPlayerInCondition(j, TFCond_HalloweenCritCandy) && !TF2_IsPlayerInCondition(j, TFCond_Kritzkrieged) )
                            {
                                new Float:tOrigin[3];
                                GetClientAbsOrigin(j, tOrigin);
                                
                                if ( GetVectorDistance(cOrigin, tOrigin) <= GetConVarFloat(cv_ZRageRadius) )
                                {
                                    TF2_AddCondition(j, TFCond_Buffed, 0.25);
                                }
                            }
                        }*/
                    }
                }
                                
                // Update the client's teleport level if they are an Engineer.
                if ( TF2_GetPlayerClass(i) == TFClass_Engineer )
                {
                    // Increment the client's teleport counter.
                    // We refire every 0.2 seconds, so get the charge rate and divide it by 5.
                    PD_IncrementTeleportLevel(index, GetConVarFloat(cv_TeleChargePerSec) / 5.0);
                    
                    // Clamp at 100%.
                    if ( _PD_GetTeleportLevel(index) > 100.0 )
                    {
                        PD_SetTeleportLevel(index, 100.0);
                    }
                }
                
                // Update the HUD text.
                if ( _PD_IsFlagSet(index, UsrRaging) || _PD_GetRageLevel(index) >= 100.0 || _PD_GetTeleportLevel(index) >= 100.0 )    // If currently raging or meter is full, print in red.
                {
                    SetHudTextParams(-1.0,
                                    0.84,
                                    0.21,
                                    255,
                                    79,
                                    79,
                                    255,
                                    0,
                                    0.0,
                                    0.0,
                                    0.0);
                }
                else
                {
                    SetHudTextParams(-1.0,
                                    0.84,
                                    0.21,
                                    255,
                                    255,
                                    255,
                                    255,
                                    0,
                                    0.0,
                                    0.0,
                                    0.0);
                }
                
                decl String:prebuffer[64];
                prebuffer[0] = '\0';
                
                // If the player is an Engineer zombie, display their teleport status. 
                if ( TF2_GetPlayerClass(i) == TFClass_Engineer )
                {
                    Format(prebuffer, sizeof(prebuffer), "\n%T: %d\%", "Teleport charge", i, RoundToFloor(_PD_GetTeleportLevel(index)));
                }
                
                decl String:buffer[128];
                
                // Health: xxx
                // Rage: xx% Dist xx.xx Rate xx.xx
                // Teleport charge: xx%
                if ( GetConVarBool(cv_DebugRage) ) Format(buffer, sizeof(buffer), "%T: %d\n%T: %d\% Dist %f Rate %f%s", "Health", i, GetEntProp(i, Prop_Send, "m_iHealth"), "Rage", i, RoundToFloor(_PD_GetRageLevel(index)), debug_dist, debug_rage * 5, prebuffer );
                
                // Why does this not display the '%' after the rage level?? :c
                
                // Health: xxx
                // Rage: xx%
                // Teleport charge: xx%
                // Percent symbols have gone derpy.
                else Format(buffer, sizeof(buffer), "%T: %d\n%T: %d%c %s", "Health", i, GetEntProp(i, Prop_Send, "m_iHealth"), "Rage", i, RoundToFloor(_PD_GetRageLevel(index)), '%', prebuffer);
                
                ShowSyncHudText(i, hs_ZText, buffer);
            }
            else if ( GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) && TF2_GetPlayerClass(i) == TFClass_Medic )
            {
                // Print Ubercharge level if we have the primary out.
                new weapon = GetEntPropEnt(i, Prop_Send, "m_hActiveWeapon");
                new medigun = GetPlayerWeaponSlot(i, SLOT_SECONDARY);
                new oldUberFlag = _PD_IsFlagSet(index, UsrUberReady);
                
                if ( medigun > MaxClients )
                {
                    if ( RoundToFloor(GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel") * 100.0) >= 100 ) PD_SetFlag(index, UsrUberReady, true);
                    else if ( GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel") < 0.05 ) PD_SetFlag(index, UsrUberReady, false);
                }
                
                if ( medigun > MaxClients && weapon > MaxClients && GetPlayerWeaponSlot(i, SLOT_PRIMARY) == weapon )
                {
                    decl String:buffer[128];
                    new charge = RoundToFloor(GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel") * 100.0);
                    
                    if ( charge >= 100 )
                    {
                        SetHudTextParams(-1.0, 0.84, 0.21, 255, 79, 79, 255, 0, 0.0, 0.0, 0.0);
                        
                        // If we've just moved to having an uber ready, play the voice line.
                        if ( oldUberFlag && _PD_IsFlagSet(index, UsrUberReady) )
                        {
                            FakeClientCommandEx(i, "voicemenu 1 7");
                        }
                    }
                    else
                    {
                        SetHudTextParams(-1.0, 0.84, 0.21, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
                    }
                    
                    Format(buffer, sizeof(buffer), "%T: %d\%", "Ubercharge", i, charge);
                    ShowSyncHudText(i, hs_ZText, buffer);
                }
            }
        }
    }
    
    return Plugin_Handled;
}

public Action:Timer_CondRefresh(Handle:timer, Handle:pack)
{
    if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
            g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
            g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return Plugin_Handled;
    
    // Search through the g_StartBoost array to find zombies who should be boosted.
    for ( new i = 0; i < MAXPLAYERS; i++ )
    {
        if ( _PD_IsFlagSet(i, UsrStartBoost) == true )    // If zombie should be boosted:
        {
            // Check client is valid.
            new client = GetClientOfUserId(_PD_GetUserId(i));
            if ( client < 1 ) continue;
            
            // NOTE: HP is now disabled altogether.
            // If using the Holiday Punch, critical hits just cause players to laugh and do no physical damage.
            // This means that if there's only one zombie alive at the start of the round and they're crit boosted
            // with the HP, they won't be able to deal any damage.
            // We need to check whether the client is using the HP before we crit boost them.
            /*new bool:hp = false;
            if ( TF2_GetPlayerClass(client) == TFClass_Heavy )
            {
                new weapon = GetPlayerWeaponSlot(client, SLOT_MELEE);
                if ( weapon > MaxClients )
                {
                    if ( GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 656 ) hp = true;
                }
            }
            
            if ( !hp ) */
            TF2_AddCondition(client, TFCond_HalloweenCritCandy, 1.05);    // Crits
            if ( TF2_GetPlayerClass(client) != TFClass_Scout ) TF2_AddCondition(client, TFCond_SpeedBuffAlly, 1.05);        // Speed boost
        }
    }
    
    // Apply general effects to players.
    for ( new i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame(i) && IsPlayerAlive(i) )
        {
            //if ( TF2_GetPlayerClass(i) == TFClass_Spy ) LogMessage("Remove me! Dead ringer condition: %d", TF2_IsPlayerInCondition(i, TFCond_DeadRingered));
            
            if ( GetClientTeam(i) == TEAM_RED )
            {
                switch ( TF2_GetPlayerClass(i) )
                {
                    case TFClass_Scout:    // Scout:
                    {
                        // Modify Scout's speed depending on the currently equipped weapon slot.
                        new activeweapon = GetEntPropEnt(i, Prop_Send, "m_hActiveWeapon");
                        
                        // If we have the primary or secondary weapon out, set speed to Medic speed.
                        if ( activeweapon > MaxClients && (activeweapon == GetPlayerWeaponSlot(i, SLOT_PRIMARY) || activeweapon == GetPlayerWeaponSlot(i, SLOT_SECONDARY)) )
                        {
                            SetEntPropFloat(i, Prop_Send, "m_flMaxspeed", 320.0);
                        }
                        // Otherwise set to Scout speed.
                        else
                        {
                            SetEntPropFloat(i, Prop_Send, "m_flMaxspeed", 400.0);
                        }
                    }
                    
                    case TFClass_DemoMan:    // Demo:
                    {
                        // Looks like we have to do it a stupid way...
                        new shield = -1;
                        while ( (shield = FindEntityByClassname(shield, "tf_wearable_demoshield")) != -1 )
                        {
                            if (GetEntPropEnt(shield, Prop_Send, "m_hOwnerEntity") == i && !GetEntProp(shield, Prop_Send, "m_bDisguiseWearable")) TF2_AddCondition(i, TFCond_HalloweenCritCandy, 1.05);
                        }
                    }
                    
                    case TFClass_Spy:    // Spy:
                    {
                        if ( TF2_IsPlayerInCondition(i, TFCond_Disguised) && GetEntProp(i, Prop_Send, "m_nDisguiseTeam") == TEAM_BLUE ) SetEntityRenderColor(i, 148, 197, 143, 255);
                        else SetEntityRenderColor(i, 255, 255, 255, 255);
                    }
                }
            }
        }
    }
    
    // Count the number of players left alive on Red and give the last couple mini-crits.
    new playercount, players[2];
    
    for ( new i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) )
        {
            // If playercount is 0 or 1, add the player to the array.
            if ( playercount < 2 ) players[playercount] = i;
            
            // Increment the player count.
            playercount++;
        }
    }
    
    if ( playercount == 2 )    // If two players left, give both mini-crits.
    {
        // The players' client indices will be at players[0] and players[1].
        /*decl Float:vel[3];
        GetEntPropVector(players[0], Prop_Send, "m_vecVelocity", vel);
        if ( GetVectorLength(vel) > 64.0 ) */
        TF2_AddCondition(players[0], TFCond_Buffed, 1.05);
        
        /*GetEntPropVector(players[1], Prop_Send, "m_vecVelocity", vel);
        if ( GetVectorLength(vel) > 64.0 ) */
        TF2_AddCondition(players[1], TFCond_Buffed, 1.05);
    }
    else if ( playercount == 1 )    // If one player left, give mini-crits and a boost.
    {
        // The single player's client index will be at players[0].
        /*decl Float:vel[3];
        GetEntPropVector(players[0], Prop_Send, "m_vecVelocity", vel);
        if ( GetVectorLength(vel) > 64.0 ) */
        TF2_AddCondition(players[0], TFCond_Buffed, 1.05);
        TF2_AddCondition(players[0], TFCond_SpeedBuffAlly, 1.05);
    }
    
    return Plugin_Handled;
}

/*    Applying super-jump for Scout.    */
public Action:Timer_ScoutJump(Handle:timer, Handle:pack)
{
    // Don't run if there are any abnormal states.
    if ( g_PluginState > 0 ) return Plugin_Handled;
    
    ResetPack(pack);
    new client = GetClientOfUserId(ReadPackCell(pack));
    
    if ( client < 1 ) return Plugin_Handled;
    
    // Don't run if the client is not a Blue zombie.
    if ( GetClientTeam(client) != TEAM_BLUE ) return Plugin_Handled;
    
    new index = _PD_GetClientSlot(client);
    if ( !_PD_IsFlagSet(index, UsrZombie) ) return Plugin_Handled;
    
    new Float:vec[3], Float:velocity[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
    vec[0] = velocity[0];
    vec[1] = velocity[1];
    vec[2] = velocity[2];
    
    // Set to = rather than +=, since falling downwards can negate a lot of the super jump.
    vec[2] = GetConVarFloat(cv_SuperJumpForce);
    
    // Set client's speed to the new value.
    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vec);
    
    // Set jumping flag.
    SetEntProp(client, Prop_Send, "m_bJumping", 1);
    PD_SetFlag(index, UsrSuperJump, true);
    
    return Plugin_Handled;
}

public Action:Timer_RespawnPlayerInSetup(Handle:timer, any:userid)
{
    RespawnPlayerInSetup(userid);
    return Plugin_Stop;
}

stock RespawnPlayerInSetup(userid)
{
    // Check whether the client is still in the game and dead.
    new client = GetClientOfUserId(userid);
    if ( client < 1 || client > MaxClients || IsPlayerAlive(client) ) return;
    
    // Check whether we are still in setup time.
    if ( g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND )
    {
        // Respawn player.
        TF2_RespawnPlayer(client);
    }
    else
    {
        // We are not in setup time any more - convert the client to a zombie.
        // Note: since the client is dead here, we want to change their team and respawn them before we make them into a zombie.
        ChangeClientTeam(client, TEAM_BLUE);
        TF2_RespawnPlayer(client);
        MakeClientZombie2(client);
    }
}

/* Fills the given array with indices of players on the given team.
   Returns the number of clients that were added. */
stock GetClientIndexArray(array[], size, team)
{
    // Record number of clients added.
    new clientsAdded = 0;
    
    // If we can't add any anyway, return.
    if ( size < 1 )
    {
        return clientsAdded;
    }

    // Cycle through each client.
    for ( new i = 1; i <= MaxClients; i++ )
    {
        // If the client is on the specified team, add them to the array.
        if ( IsClientInGame(i) && GetClientTeam(i) == team )
        {
            array[clientsAdded] = i;
            clientsAdded++;
            
            // Check whether we have now reached the max number of clients we can add.
            if ( clientsAdded >= size ) break;
        }
    }
    
    // Return the number we added.
    return clientsAdded;
}

#if DEVELOPER == 1
/*    Outputs player data arrays to the console.    */
public Action:Debug_ShowData(client, args)
{
    if ( client < 0 ) return Plugin_Handled;
    else if ( client > 0 && !IsClientInGame(client) ) return Plugin_Handled;
    
    // Disabling this for now since the player data arrays have changed.
#if false
    if ( GetCmdArgs() > 0 )
    {
        new String:arg[16];
        GetCmdArg(1, arg, sizeof(arg));
        new i = StringToInt(arg);
        
        if ( i < 0 || i >= MAXPLAYERS )
        {
            ReplyToCommand(client, "Index must be between 0 and %d inclusive!", MAXPLAYERS-1);
            return Plugin_Handled;
        }
        
        PrintToConsole(client, "%d: UserID %d\tzombie %d\thealth %d\tmaxhealth %d\tstartboost %d\trage %f\traging %d", i, g_userIDMap[i], g_Zombie[i], g_Health[i], g_MaxHealth[i], g_StartBoost[i], g_Rage[i], g_Raging[i]);
    }
    
    for (new i = 0; i < MAXPLAYERS; i++ )
    {
        PrintToConsole(client, "%d: UserID %d\tzombie %d\thealth %d\tmaxhealth %d\tstartboost %d\trage %f\traging %d", i, g_userIDMap[i], g_Zombie[i], g_Health[i], g_MaxHealth[i], g_StartBoost[i], g_Rage[i], g_Raging[i]);
    }
#endif
    
    return Plugin_Handled;
}

public Action:Debug_FullRage(client, args)
{
    new slot = _PD_GetClientSlot(client);
    if ( client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == TEAM_BLUE && _PD_IsFlagSet(slot, UsrZombie) && !_PD_IsFlagSet(slot, UsrRaging) )
    {
        PD_SetRageLevel(slot, 100.0);
    }
    
    return Plugin_Handled;
}
#endif

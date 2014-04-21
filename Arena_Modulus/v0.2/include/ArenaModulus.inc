// Arena Modulus include file

/*
	Information on event firing order:
	At the beginning of an Arena round the post_inventory_application event is fired, followed by player_spawn, for
	each player. Once all of these have taken place, teamplay_round_start is then fired (and consequently ArenaMod_RoundStart).
*/

#if defined _arenamodulus_included
 #endinput
#endif
#define _arenamodulus_included

// ================================
// =========== Natives ============
// ================================

/*
 * Registers a mode into the handler.
 *
 * @param	String:ModeName		Name of the mode. Should be translated into LANG_SERVER before being passed. Max length 64 characters.
 * @param	String:ModeTagline	Tagline to display to players when the round starts. Should be translated into LANG_SERVER before being passed. Max length 64 characters.
 * @param	String:ModeDesc		Fuller description of the mode. Should be translated into LANG_SERVER before being passed. Max length 128 characters.
 * @param	MinPlayersRed		Minimum number of players that must be on the Red team for this mode to activate.
 * @param	MinPlayersBlue		Minimum number of players that must be on the Blue team for this mode to activate.
 * @param 	TeamIndependent		If 1, team-specific counts will be ignored and the total number of min players (MinPlayersRed + MinPlayersBlue) will be checked regardless of teams.
								Use this if you require a minimum number of players but it doesn't matter whether they are on Red or Blue.
 * @return		    			ID of the mode as registered in the handler, or -10 if unable to be registered (so as not to clash with the ID for normal Arena).
 */
native ArenaMod_RegisterMode(String:ModeName[], String:ModeTagline[], String:ModeDesc[], MinPlayersRed, MinPlayersBlue, TeamIndependent = 0);

/*
 * Cancels the current mode in progress.
 *
 * @param	modeID				ID of the mode calling the function.
 * @return		    			No return.
 */
native ArenaMod_CancelCurrentRound(modeID);

/*
 * Notifies the handler that a custom mode has been unloaded.
 * The mode data will stay in the handler until the next map load, but will no longer be selected to be played.
 * If the mode concerned is being played when this call is made, the round will end.
 * WARNING! If a custom mode is unloaded, it cannot be loaded again until the next map starts.
 *
 * @param	modeID				ID of the mode calling the function.
 * @return		    			No return.
 */
native ArenaMod_UnloadMode(modeID);

// ================================
// =========== Forwards ===========
// ================================

/*
 * Broadcasts a search for modes. Modes that use this function must call ArenaMod_RegisterMode to register their presence.
 * Any OnMapStart logic that must occur after the handler has executed OnMapStart should occur in this forward as well.
 *
 * @return						No return.
 */
forward ArenaMod_SearchForModes();

/*
 * Called once a mode has been chosen on RoundStart. Note that the arena_round_start event will not yet have fired.
 *
 * @param	modeID				ID (0 - MAX_MODES-1 inclusive) of the chosen mode. Modes should check this ID against theirs and activate if it matches. -1 if no mode.
 * @return						Plugin_Handled on success, Plugin_Stop on failure.
 */
forward Action:ArenaMod_RoundStart(modeID);
 
/*
 * Called when a round is ended.
 *
 * @param	modeID				ID (0 - MAX_MODES-1 inclusive) of the chosen mode. The mode with this ID should clean up all the resources it is using in preparation for the next round.
 * @param	winning_team		Team who won the round; 0 on stalemate.
 * @return						Plugin_Handled on success, Plugin_Stop on failure.
 */
forward Action:ArenaMod_RoundEnd(modeID, winning_team);
 
/*
 * Called when the map ends. All modes should respond to this forward by clearing up all of their resources.
 *
 * @return						No return.
 */
forward ArenaMod_MapEnd();

/*
 * Called if the main handler is loaded mid-round. Custom modes should update their AMLibExists flag.
 * Note that general setup/registering modes should NOT happen here; this is only useful if the handler has been
 * unloaded previously and is now being loaded again, otherwise custom modes would remain disabled until
 * they were individually reloaded or the server restarted.
 *
 * @return						No return.
 */
forward ArenaMod_HandlerLoad();

/*
 * Called if the main handler is unloaded. Custom modes should clean up, disable themselves and clear out their mode IDs.
 *
 * @return						No return.
 */
forward ArenaMod_HandlerUnload();
 
public SharedPlugin:__pl_ArenaModulus = 
{
	name = "ArenaModulus",
	file = "ArenaModulus.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_ArenaModulus_SetNTVOptional()
{
	MarkNativeAsOptional("ArenaMod_RegisterMode");
	MarkNativeAsOptional("ArenaMod_CancelCurrentRound");
}
#endif
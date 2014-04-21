/*
  _______ ______ ___    _____  __  __ 
 |__   __|  ____|__ \  |  __ \|  \/  |
    | |  | |__     ) | | |  | | \  / |
    | |  |  __|   / /  | |  | | |\/| |
    | |  | |     / /_  | |__| | |  | |
    |_|  |_|    |____| |_____/|_|  |_|

    A deathmatch game mode for TF2.
    Created by [X6] Herbius on 05/11/12 at 14:02.
*/

/*	Cleanup states	*/
enum CleanupState
{
	RoundStart = 0,
	RoundEnd,
	FirstStart,
	EndAll,
	MapStart,
	MapEnd
};
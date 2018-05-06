/* =================================================
    ClientRecords - X6Herbius, 06/05/2018
   ================================================= */

#if defined _CLIENTRECORDS_INC
 #endinput
#endif
#define _CLIENTRECORDS_INC

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dynamic>

typedef ClientRecord_InitFunc = function void(int client, Dynamic &item);

static Dynamic _records[MAXPLAYERS] = { INVALID_DYNAMIC_OBJECT, ... };
static Handle _fwdConstructor = INVALID_HANDLE;
static bool _bInitialised = false;

/**
 * Initialises client records.
 *
 * @param constructor   Function to call to initialise each dynamic item to its default value when a client connects.
 *
 * @noreturn
 */
void ClientRecords_Initialise(ClientRecord_InitFunc constructor)
{
    if ( _bInitialised )
    {
        ThrowError("ClientRecords: Already initialised.");
    }

    _fwdConstructor = CreateForward(ET_Ignore, Param_Cell, Param_CellByRef);
    AddToForward(_fwdConstructor, INVALID_HANDLE, constructor);

    // Set this before we start calling for connected clients below.
    _bInitialised = true;

    // Just in case this was called during a game, make sure we initialise
    // for all currently connected clients.
    for ( int i = 1; i <= MaxClients; ++i )
    {
        if ( !IsClientConnected(i) )
        {
            continue;
        }

        ClientRecords_NotifyClientConnected(i);
    }
}

/**
 * Destroys any existing client records.
 *
 * @noreturn
 */
void ClientRecords_Destroy()
{
    if ( _bInitialised )
    {
        return;
    }

    for ( int i = 0; i < MAXPLAYERS; ++i )
    {
        if ( _records[i].IsValid )
        {
            _records[i].Dispose();
            _records[i] = INVALID_DYNAMIC_OBJECT;
        }
    }

    CloseHandle(_fwdConstructor);
    _bInitialised = false;
}

void ClientRecords_NotifyClientConnected(int client)
{
    if ( !_bInitialised )
    {
        ThrowError("ClientRecords: Not initialised.");
    }

    if ( client < 1 || client >= MAXPLAYERS )
    {
        ThrowError("ClientRecords: Client index %d is out of range.", client);
    }

    if ( _records[client].IsValid )
    {
        _records[client].Dispose();
    }

    _records[client] = INVALID_DYNAMIC_OBJECT;

    Call_StartForward(_fwdConstructor);
    Call_PushCell(client);
    Call_PushCellRef(_records[client]);
    Call_Finish();

    if (_records[client] == INVALID_DYNAMIC_OBJECT )
    {
        ThrowError("ClientRecords: Record for client %d was not correctly initialised.", client);
    }
}

void ClientRecords_NotifyClientDisconnected(int client)
{
    if ( !_bInitialised )
    {
        ThrowError("ClientRecords: Not initialised.");
    }

    if ( client < 1 || client >= MAXPLAYERS )
    {
        ThrowError("ClientRecords: Client index %d is out of range.", client);
    }

    if ( _records[client].IsValid )
    {
        _records[client].Dispose();
        _records[client] = INVALID_DYNAMIC_OBJECT;
    }
}

stock Dynamic ClientRecords_GetRecord(int client)
{
    if ( !_bInitialised )
    {
        ThrowError("ClientRecords: Not initialised.");
    }

    if ( client < 1 || client >= MAXPLAYERS )
    {
        ThrowError("ClientRecords: Client index %d is out of range.", client);
    }

    return _records[client];
}

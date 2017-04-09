#if defined _TF2DM_WEAPONSETREADERCORE_INC
 #endinput
#endif
#define _TF2DM_WEAPONSETREADERCORE_INC

#pragma semicolon 1
#pragma newdecls required

#include <keyvalues>
#include <tf2>
#include <adt_trie>

#define MAX_WEAPONSETS 8
#define MAX_WEAPONSET_SLOTS 8
#define WEAPONSET_CLASS_COUNT 9
#define MAX_WEAPONSET_NAME_LENGTH 32

#define TFCLASS_LOWER_BOUND TFClass_Scout
#define TFCLASS_UPPER_BOUND TFClass_Engineer

#define INVALID_WEAPON_INDEX -1

static const char _nClassNames[WEAPONSET_CLASS_COUNT][16] =
{
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

static int _nWeaponSets[MAX_WEAPONSETS][MAX_WEAPONSET_SLOTS][WEAPONSET_CLASS_COUNT];
static char _strWeaponSetNames[MAX_WEAPONSETS][MAX_WEAPONSET_NAME_LENGTH];
static int _nWeaponSetCount = 0;

public void WepSetRxCore_Initialise()
{
    ClearWeaponSets();
}

public void WepSetRxCore_Shutdown()
{
    
}

public bool WepSetRxCore_ReadWeaponSets(const char[] strFileName)
{
    KeyValues kvNode = new KeyValues("weaponsets");
    
    if ( !kvNode.ImportFromFile(strFileName) )
    {
        LogError("Unable to open weapon sets file '%s'", strFileName);
        delete kvNode;
        return false;
    }
    
    char strSectionName[32];
    kvNode.GetSectionName(strSectionName, sizeof(strSectionName));
    
    if ( !StrEqual(strSectionName, "weaponsets") )
    {
        LogError("Reading weapon sets from file '%s': expected root node of 'weaponsets' but got '%s'.", strFileName, strSectionName);
        delete kvNode;
        return false;
    }
    
    Populate(kvNode);
    
    delete kvNode;
    return true;
}

stock void Populate(KeyValues kvNode)
{
    StringMap smStoredWeaponSets = new StringMap();
    
    for ( bool bNextSubKey = kvNode.GotoFirstSubKey(true); bNextSubKey; bNextSubKey = kvNode.GotoNextKey(true) )
    {
        if ( _nWeaponSetCount >= MAX_WEAPONSETS )
        {
            LogError("WeaponSetReader: Number of weapon sets exceeds maximum count of %i, truncating.", MAX_WEAPONSETS);
            break;
        }
        
        char buffer[32];
        kvNode.GetSectionName(buffer, sizeof(buffer));
        
        {
            int nDummyValue = 0;
            if ( smStoredWeaponSets.GetValue(buffer, nDummyValue) )
            {
                LogError("WeaponSetReader: Duplicate weapon set with identifier '%s'.", buffer);
                continue;
            }
        }
        
        smStoredWeaponSets.SetValue(buffer, _nWeaponSetCount, true);
        
        PopulateWeaponSet(_nWeaponSetCount, kvNode);
        StoreWeaponSetDescriptiveName(kvNode);
        
        ++_nWeaponSetCount;
    }
    
    delete smStoredWeaponSets;
    kvNode.GoBack();
}

stock void PopulateWeaponSet(int nWeaponSet, KeyValues kvNode)
{
    for ( bool bNextSubKey = kvNode.GotoFirstSubKey(true); bNextSubKey; bNextSubKey = kvNode.GotoNextKey(true) )
    {
        int nSlotId = kvNode.GetNum("id", -1);
        if ( nSlotId < 0 )
        {
            LogError("WeaponSetReader: Slot within weaponset %i has no ID.", nWeaponSet);
            continue;
        }
        
        if ( nSlotId >= MAX_WEAPONSET_SLOTS )
        {
            LogError("WeaponSetReader: Slot %i is greater than maximum slot index %i.", nSlotId, MAX_WEAPONSET_SLOTS);
            continue;
        }
        
        PopulateSlot(nWeaponSet, nSlotId, kvNode);
    }
    
    kvNode.GoBack();
}

stock void StoreWeaponSetDescriptiveName(KeyValues kvNode)
{
    char strDefaultName[MAX_WEAPONSET_NAME_LENGTH];
    Format(strDefaultName, sizeof(strDefaultName), "Weaponset %i", _nWeaponSetCount+1);
    
    char buffer[MAX_WEAPONSET_NAME_LENGTH];
    kvNode.GetString("name", buffer, sizeof(buffer), strDefaultName);
    
    strcopy(_strWeaponSetNames[_nWeaponSetCount], sizeof(_strWeaponSetNames[]), buffer);
}

stock void PopulateSlot(int nWeaponSet, int nSlot, KeyValues kvNode)
{
    for ( TFClassType nClass = TFCLASS_LOWER_BOUND; nClass <= TFCLASS_UPPER_BOUND; ++nClass )
    {
        SetItemIndexFromKV(nWeaponSet, nSlot, nClass, kvNode);
    }
}

stock void SetItemIndexFromKV(int nWeaponSet, int nSlot, TFClassType nClass, KeyValues kvNode)
{
    int nItemIndex = kvNode.GetNum(_nClassNames[view_as<int>(nClass)-1], INVALID_WEAPON_INDEX);
    SetItemIndex(nWeaponSet, nSlot, nClass, nItemIndex);
}

stock void SetItemIndex(int nWeaponSet, int nSlot, TFClassType nClass, int nItemIndex)
{
    _nWeaponSets[nWeaponSet][nSlot][view_as<int>(nClass)-1] = nItemIndex;
}

public int WepSetRxCore_GetItemIndex(int nWeaponSet, int nSlot, TFClassType nClass)
{
    return _nWeaponSets[nWeaponSet][nSlot][view_as<int>(nClass)-1];
}

public void WepSetRxCore_GetWeaponSetDescriptiveName(int nWeaponSet, char[] strBuffer, int nLength)
{
    strcopy(strBuffer, nLength, _strWeaponSetNames[nWeaponSet]);
}

stock void ClearWeaponSets()
{
    for ( int nSet = 0; nSet < MAX_WEAPONSETS; ++nSet )
    {
        for ( int nSlot = 0; nSlot < MAX_WEAPONSET_SLOTS; ++nSlot )
        {
            for ( TFClassType nClass = TFCLASS_LOWER_BOUND; nClass <= TFCLASS_UPPER_BOUND; ++nClass )
            {
                SetItemIndex(nSet, nSlot, nClass, INVALID_WEAPON_INDEX);
            }
        }
        
        _strWeaponSetNames[nSet][0] = 0;
    }
    
    _nWeaponSetCount = 0;
}
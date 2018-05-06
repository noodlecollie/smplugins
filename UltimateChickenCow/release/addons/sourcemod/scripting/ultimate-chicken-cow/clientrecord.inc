#if defined _TF2UCC_CLIENTRECORD_INC
 #endinput
#endif
#define _TF2UCC_CLIENTRECORD_INC

#pragma semicolon 1
#pragma newdecls required

// For convenience: caches a member offset for efficiency.
// See dynamic-example.inc.
#define STATIC_OFFSET(%1) \
    static DynamicOffset offset = INVALID_DYNAMIC_OFFSET; \
    if ( offset == INVALID_DYNAMIC_OFFSET ) \
    { \
        offset = this.GetMemberOffset(%1); \
        if ( offset == INVALID_DYNAMIC_OFFSET ) \
        { \
            ThrowError("Unable to get Dynamic offset for member '%s'.", (%1)); \
        } \
    }

methodmap UCC_ClientRecord < Dynamic
{
    public UCC_ClientRecord()
    {
        Dynamic obj = Dynamic(64, 0);

        return view_as<UCC_ClientRecord>(obj);
    }
}

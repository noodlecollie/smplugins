#if defined _TF2UCC_CLIENTRECORD_INC
 #endinput
#endif
#define _TF2UCC_CLIENTRECORD_INC

#pragma semicolon 1
#pragma newdecls required

methodmap UCC_ClientRecord < Dynamic
{
    public UCC_ClientRecord()
    {
        Dynamic obj = Dynamic(64, 0);

        obj.SetInt("Client", 0);

        return view_as<UCC_ClientRecord>(obj);
    }

    // Annoyingly, it doesn't appear we can have private methods yet.
    // Just prefix in an obvious way for now.
    public DynamicOffset Private_GetOffset(DynamicOffset &offset, const char[] memberName)
    {
        if ( offset == INVALID_DYNAMIC_OFFSET )
        {
            offset = this.GetMemberOffset(memberName);
            if ( offset == INVALID_DYNAMIC_OFFSET )
            {
                ThrowError("Unable to get Dynamic offset for member '%s'.", memberName);
            }
        }

        return offset;
    }

    property int Client
    {
        public get()
        {
            static DynamicOffset offset = INVALID_DYNAMIC_OFFSET;
            return this.GetIntByOffset(this.Private_GetOffset(offset, "Client"));
        }

        public set(int value)
        {
            static DynamicOffset offset = INVALID_DYNAMIC_OFFSET;
            return this.SetIntByOffset(this.Private_GetOffset(offset, "Client"), value);
        }
    }
}

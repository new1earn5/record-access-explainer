/**
 * Plain wrapper around a single UserRecordAccess row (or equivalent from a fake provider
 * used in tests), decoupled from the SObject shape so callers do not need to know
 * whether the data came from a live query or a test double.
 */
public class RAA_EffectiveAccessResult {
    public Id userId;
    public Boolean hasReadAccess;
    public Boolean hasEditAccess;
    public Boolean hasDeleteAccess;
    public Boolean hasTransferAccess;
    public Boolean hasAllAccess;
    public String maxAccessLevel;

    public RAA_EffectiveAccessResult(
        Id userId,
        Boolean hasReadAccess,
        Boolean hasEditAccess,
        Boolean hasDeleteAccess,
        Boolean hasTransferAccess,
        Boolean hasAllAccess,
        String maxAccessLevel
    ) {
        this.userId = userId;
        this.hasReadAccess = hasReadAccess;
        this.hasEditAccess = hasEditAccess;
        this.hasDeleteAccess = hasDeleteAccess;
        this.hasTransferAccess = hasTransferAccess;
        this.hasAllAccess = hasAllAccess;
        this.maxAccessLevel = maxAccessLevel;
    }

    public Boolean hasAnyAccess() {
        return hasReadAccess == true ||
            hasEditAccess == true ||
            hasDeleteAccess == true ||
            hasTransferAccess == true ||
            hasAllAccess == true;
    }
}

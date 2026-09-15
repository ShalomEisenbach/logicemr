public with sharing class ClaimExportController {
    private static final String MANAGE_CLAIMS_PERMISSION = 'LogicEMR_Manage_Claims';
    @TestVisible private static Boolean manageClaimsOverride;

    @AuraEnabled(cacheable=true)
    public static String getCanonicalJson(Id superbillId) {
        requireManageClaims();
        return ClaimExportService.serialize(superbillId);
    }

    private static void requireManageClaims() {
        Boolean allowed = manageClaimsOverride != null
            ? manageClaimsOverride
            : FeatureManagement.checkPermission(MANAGE_CLAIMS_PERMISSION);
        if (!allowed) throw new AuraHandledException('You do not have permission to export LogicEMR claims.');
    }
}

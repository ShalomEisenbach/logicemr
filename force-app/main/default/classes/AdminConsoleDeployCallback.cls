public with sharing class AdminConsoleDeployCallback implements Metadata.DeployCallback {
    @TestVisible
    static String lastJobId;
    @TestVisible
    static Boolean lastSuccess;
    @TestVisible
    static String lastMessage;

    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        lastJobId = result != null ? result.id : null;
        lastSuccess = result != null && result.success == true;
        if (result == null) {
            lastMessage = 'Deploy result was null.';
            return;
        }
        if (result.success == true) {
            lastMessage = 'Custom metadata deploy completed.';
            return;
        }
        List<String> parts = new List<String>();
        if (result.details != null && result.details.componentFailures != null) {
            for (Metadata.DeployMessage failure : result.details.componentFailures) {
                if (failure != null && String.isNotBlank(failure.problem)) {
                    parts.add(failure.problem);
                }
            }
        }
        lastMessage = parts.isEmpty() ? 'Custom metadata deploy failed.' : String.join(parts, ' ');
    }
}

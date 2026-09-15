public class ClaimSubmissionConfig {
    public String providerName { get; set; }
    public String namedCredential { get; set; }
    public String usageIndicator { get; set; }
    public String submitterName { get; set; }
    public String submitterIdentifier { get; set; }
    public String contactName { get; set; }
    public String contactPhone { get; set; }

    public void validate() {
        List<String> issues = new List<String>();
        if (String.isBlank(providerName)) issues.add('provider name');
        if (String.isBlank(namedCredential)) issues.add('Named Credential');
        if (usageIndicator != 'T' && usageIndicator != 'P') issues.add('usage indicator (T or P)');
        if (String.isBlank(submitterName)) issues.add('submitter name');
        if (String.isBlank(contactName)) issues.add('contact name');
        String phone = digits(contactPhone);
        if (phone == null || phone.length() != 10) issues.add('10-digit contact phone');
        if (!issues.isEmpty()) {
            throw new ClaimSubmissionProviderFactory.ClaimSubmissionException(
                'Claim Submission Setting requires ' + String.join(issues, ', ') + '.'
            );
        }
        contactPhone = phone;
    }

    private static String digits(String value) {
        return String.isBlank(value) ? null : value.replaceAll('[^0-9]', '');
    }
}

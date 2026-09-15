public interface ClaimSubmissionProvider {
    ClaimSubmissionResult submit(
        VendorNeutralClaim claim,
        ClaimSubmissionConfig config,
        String idempotencyKey,
        String patientControlNumber
    );
}

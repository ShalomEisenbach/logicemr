public class ClaimSubmissionResult {
    public Boolean success { get; set; }
    public Boolean rejected { get; set; }
    public String requestPayload { get; set; }
    public String responsePayload { get; set; }
    public Integer httpStatusCode { get; set; }
    public String providerStatus { get; set; }
    public String correlationId { get; set; }
    public String clearinghouseClaimId { get; set; }
    public String controlNumber { get; set; }
    public String errorMessage { get; set; }

    public ClaimSubmissionResult() {
        success = false;
        rejected = false;
    }
}
